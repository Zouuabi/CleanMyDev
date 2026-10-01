import Foundation

/// What a module needs to know to scan: the user's settings plus the current
/// project decisions, so dev-junk modules can skip active projects and the
/// safety filter can drop never-touch paths.
public struct ScanContext: Sendable {
    public let settings: CleanSettings
    public let registry: ProjectRegistry
    public let now: Date

    public init(settings: CleanSettings, registry: ProjectRegistry, now: Date = Date()) {
        self.settings = settings
        self.registry = registry
        self.now = now
    }

    public var neverTouch: [String] { settings.neverTouch }
}

public enum ModuleGroup: String, CaseIterable, Sendable {
    case cleanup, developer, protection, applications, files

    public var displayName: String {
        switch self {
        case .cleanup: "Cleanup"
        case .developer: "Developer"
        case .protection: "Protection"
        case .applications: "Applications"
        case .files: "Files"
        }
    }
}

public protocol ScanModule: Sendable {
    var id: String { get }
    var name: String { get }
    var group: ModuleGroup { get }
    /// Whether Smart Care runs this module. Large/old files and duplicates are
    /// opt-in because their findings are not junk.
    var includedInSmartScan: Bool { get }
    func scan(context: ScanContext) async -> [ScanResult]
}

public extension ScanModule {
    var includedInSmartScan: Bool { true }
}

/// Runs a set of modules and publishes progress. Owned by the app's view model.
public actor ScanRunner {
    public struct Progress: Sendable {
        public let fraction: Double
        public let currentModule: String
        public let itemsFound: Int
        public let bytesFound: UInt64
    }

    private let modules: [ScanModule]

    public init(modules: [ScanModule]) {
        self.modules = modules
    }

    public func run(
        only ids: Set<String>? = nil,
        smartScanOnly: Bool = false,
        context: ScanContext,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) async -> [ModuleScanResult] {
        let selected = modules.filter { m in
            if let ids { return ids.contains(m.id) }
            return smartScanOnly ? m.includedInSmartScan : true
        }
        var results: [ModuleScanResult] = []
        var items = 0
        var bytes: UInt64 = 0
        ScanTelemetry.shared.reset(module: selected.first?.name ?? "")
        for (i, module) in selected.enumerated() {
            if Task.isCancelled { break }
            ScanTelemetry.shared.setModule(module.name)
            onProgress(Progress(fraction: Double(i) / Double(max(selected.count, 1)), currentModule: module.name, itemsFound: items, bytesFound: bytes))
            let start = Date()
            let raw = await module.scan(context: context)
            if Task.isCancelled { break }
            let filtered = raw.filteringUncleanable(neverTouch: context.neverTouch)
            let r = ModuleScanResult(moduleID: module.id, moduleName: module.name, categories: filtered,
                                     scanDuration: Date().timeIntervalSince(start))
            items += r.totalFileCount
            bytes += r.totalSize
            ScanTelemetry.shared.found(items: r.totalFileCount, bytes: r.totalSize)
            results.append(r)
        }
        onProgress(Progress(fraction: 1, currentModule: "", itemsFound: items, bytesFound: bytes))
        return results
    }
}

/// Non-file things (Docker images, simulators) are cleaned by their own
/// service. Items use a URL scheme the service claims.
public protocol VirtualCleaner: Sendable {
    var scheme: String { get }
    func remove(_ items: [FileItem]) async -> [(FileItem, Error?)]
}

/// Routes a mixed selection: file URLs go to `CleaningEngine`, other schemes
/// to the matching `VirtualCleaner`.
public struct CleanDispatcher: Sendable {
    public let engine: CleaningEngine
    public let virtualCleaners: [String: VirtualCleaner]

    public init(engine: CleaningEngine, virtualCleaners: [VirtualCleaner]) {
        self.engine = engine
        self.virtualCleaners = Dictionary(uniqueKeysWithValues: virtualCleaners.map { ($0.scheme, $0) })
    }

    public func clean(items: [FileItem], mode: CleaningEngine.Mode, label: String,
                      onProgress: (@Sendable (CleaningEngine.Progress) -> Void)? = nil) async -> CleaningEngine.Result {
        let files = items.filter(\.url.isFileURL)
        let others = items.filter { !$0.url.isFileURL }
        var result = await engine.clean(items: files, mode: mode, label: label, onProgress: onProgress)

        var removed = result.removedCount
        var freed = result.freedBytes
        var urls = result.removedURLs
        var errors = result.errors
        let grouped = Dictionary(grouping: others) { $0.url.scheme ?? "" }
        for (scheme, group) in grouped {
            guard let cleaner = virtualCleaners[scheme] else {
                errors.append(contentsOf: group.map { .init(path: $0.path, error: "No cleaner for \(scheme)") })
                continue
            }
            if mode == .dryRun {
                removed += group.count
                freed += group.reduce(0) { $0 + $1.size }
                group.forEach { urls.insert($0.url); OperationLog.append("[DRY-RUN] \($0.url.absoluteString)") }
                continue
            }
            for (item, error) in await cleaner.remove(group) {
                if let error {
                    errors.append(.init(path: item.url.absoluteString, error: error.localizedDescription))
                    OperationLog.append("[ERROR] \(item.url.absoluteString) — \(error.localizedDescription)")
                } else {
                    removed += 1; freed += item.size; urls.insert(item.url)
                    OperationLog.append("[REMOVED] \(item.url.absoluteString) (\(item.formattedSize))")
                }
            }
        }
        result = CleaningEngine.Result(runID: result.runID, mode: mode, removedCount: removed, freedBytes: freed,
                                       removedURLs: urls, errors: errors, skippedCount: result.skippedCount)
        return result
    }
}
