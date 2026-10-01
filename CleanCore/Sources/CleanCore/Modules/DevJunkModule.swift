import Foundation

/// Global developer caches (always regenerable) plus per-project artifacts
/// gated on the project's status. The project list it discovers is published
/// through `lastProjects` so the UI can show the review screen.
public struct DevJunkModule: ScanModule {
    public let id = "dev_junk"
    public let name = "Dev Junk"
    public let group = ModuleGroup.developer

    public init() {}

    public func scan(context: ScanContext) async -> [ScanResult] {
        let scanner = TargetedScanner()
        async let pm = scanner.scan(targets: Self.packageManagerTargets())
        async let ml = scanner.scan(targets: [
            ScanTarget(path: CMConstants.huggingFaceCache, recursive: false, reportDirectoriesAsItems: true, reason: "Model cache, re-downloads on use"),
            ScanTarget(path: CMConstants.torchCache, recursive: false, reportDirectoriesAsItems: true, reason: "Model cache, re-downloads on use"),
        ])
        async let xcode = scanner.scan(targets: [
            .wholeDirectory(CMConstants.xcodeDerivedData, reason: "Rebuilt on next build"),
            .wholeDirectory(CMConstants.xcodeArchives, reason: "Old archive"),
            .wholeDirectory(CMConstants.xcodeDeviceSupport, reason: "Device support symbols, re-downloaded when a device connects"),
            .wholeDirectory(CMConstants.xcodePreviews, reason: "SwiftUI preview cache"),
            .wholeDirectory(CMConstants.coreSimulatorCaches, reason: "Simulator cache"),
        ])

        let projects = await ProjectScanService.shared.refresh(context: context)
        let (deps, builds) = Self.projectArtifacts(projects: projects, context: context)

        var results: [ScanResult] = []
        func add(_ cat: ScanCategory, _ items: [FileItem]) {
            if !items.isEmpty { results.append(ScanResult(category: cat, items: items.sorted { $0.size > $1.size })) }
        }
        add(.packageManagerCaches, await pm)
        add(.mlModelCaches, await ml)
        add(.xcodeJunk, await xcode)
        add(.projectDependencies, deps)
        add(.projectBuildOutput, builds)
        return results
    }

    static func packageManagerTargets() -> [ScanTarget] {
        let entries: [(URL, String)] = [
            (CMConstants.npmCacache, "npm cache"), (CMConstants.npxCache, "npx cache"),
            (CMConstants.pnpmCache, "pnpm cache"), (CMConstants.yarnCache, "yarn cache"), (CMConstants.bunCache, "bun cache"),
            (CMConstants.pipCache, "pip cache"), (CMConstants.uvCache, "uv cache"), (CMConstants.poetryCache, "poetry cache"),
            (CMConstants.cargoRegistryCache, "cargo registry cache"), (CMConstants.cargoRegistrySrc, "cargo registry sources"),
            (CMConstants.cargoGitCheckouts, "cargo git checkouts"),
            (CMConstants.goModCache, "go module cache"), (CMConstants.goBuildCache, "go build cache"),
            (CMConstants.gradleCaches, "gradle cache"), (CMConstants.gradleDaemon, "gradle daemon logs"), (CMConstants.gradleWrapperDists, "gradle distributions"),
            (CMConstants.mavenRepo, "maven repository"), (CMConstants.cocoapodsCache, "CocoaPods cache"), (CMConstants.pubCache, "pub cache"),
            (CMConstants.homebrewCache, "Homebrew downloads"), (CMConstants.composerCache, "composer cache"),
            (CMConstants.playwrightBrowsers, "Playwright browsers, re-installed with npx playwright install"),
            (CMConstants.puppeteerCache, "Puppeteer browsers"), (CMConstants.cypressCache, "Cypress binaries"),
            (CMConstants.typescriptCache, "TypeScript cache"), (CMConstants.nodeGypCache, "node-gyp headers"), (CMConstants.colimaCache, "colima image downloads"),
        ]
        return entries.map { ScanTarget(path: $0.0, recursive: false, reportDirectoriesAsItems: true, reason: "\($0.1), re-downloadable") }
    }

    static func projectArtifacts(projects: [ProjectScanService.Entry], context: ScanContext) -> (deps: [FileItem], builds: [FileItem]) {
        var deps: [FileItem] = []
        var builds: [FileItem] = []
        for entry in projects where entry.decision.status.allowsCleaning {
            let days = entry.project.daysSinceActivity(now: context.now)
            let why = entry.decision.isOverride ? entry.decision.reason : "Project untouched for \(days ?? 0) days"
            for a in entry.project.artifacts {
                let item = FileItem(url: a.url, name: "\(entry.project.name)/\(a.relativePath)", size: a.bytes, isDirectory: true,
                                    modificationDate: entry.project.lastActivity, reason: why)
                if a.isDependency { deps.append(item) } else { builds.append(item) }
            }
        }
        return (deps, builds)
    }
}

/// Holds the latest project discovery so the UI and the dev-junk module see
/// the same list and the same decisions.
public actor ProjectScanService {
    public static let shared = ProjectScanService()

    public struct Entry: Sendable, Identifiable {
        public var id: String { project.id }
        public var project: Project
        public var decision: ProjectDecision
    }

    public private(set) var entries: [Entry] = []
    public private(set) var lastRefresh: Date?

    public func refresh(context: ScanContext) async -> [Entry] {
        let roots = context.settings.scanRoots.map { URL(filePath: $0) }
        var projects = await ProjectDetector().discover(roots: roots, neverTouch: context.neverTouch)
        let signals = await ProcessProbe.gather()
        for i in projects.indices {
            projects[i].signals = signals.signals(for: projects[i].root)
        }
        entries = Self.applyAncestorProtection(projects.map { Entry(project: $0, decision: ProjectClassifier.decide($0, registry: context.registry, settings: context.settings, now: context.now)) })
        lastRefresh = Date()
        SizeCache.shared.flush()
        return entries
    }

    /// Re-run decisions without re-walking the disk (after a pin changes).
    public func reclassify(context: ScanContext) -> [Entry] {
        entries = Self.applyAncestorProtection(entries.map { Entry(project: $0.project, decision: ProjectClassifier.decide($0.project, registry: context.registry, settings: context.settings, now: context.now)) })
        return entries
    }

    /// A sub-project inside an active or pinned project inherits that protection:
    /// a monorepo package untouched for a month is still part of a live repo.
    static func applyAncestorProtection(_ entries: [Entry]) -> [Entry] {
        let protected = entries.filter { !$0.decision.status.allowsCleaning && !$0.decision.isOverride || $0.decision.status == .pinned }
        return entries.map { e in
            guard e.decision.status.allowsCleaning else { return e }
            if let parent = protected.first(where: { $0.project.path != e.project.path && PathExclusion.isInside(e.project.path, root: $0.project.path) }) {
                var copy = e
                copy.decision = ProjectDecision(status: parent.decision.status,
                                                reason: "Inside \(parent.project.name), which is \(parent.decision.status.displayName.lowercased())")
                return copy
            }
            return e
        }
    }

    /// Roots of projects that must not be touched, for the SafetyGuard.
    public func protectedRoots() -> [String] {
        entries.filter { !$0.decision.status.allowsCleaning }.map(\.project.path)
    }
}
