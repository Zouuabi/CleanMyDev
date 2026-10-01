import SwiftUI
import AppKit
import CleanCore

/// Single source of truth for the UI. Owns settings, project overrides, and
/// one scan/clean state per sidebar scope.
@Observable
@MainActor
final class AppModel {
    // MARK: Persistent
    var settings: CleanSettings { didSet { try? settings.save() } }
    var registry: ProjectRegistry { didSet { try? registry.save() } }

    // MARK: Navigation
    var selection: SidebarItem = .smartCare

    // MARK: Scan state, keyed by scope
    enum Phase: Equatable {
        case idle
        case scanning(progress: Double, module: String, found: UInt64)
        case results
        case cleaning(progress: Double)
        case done(removed: Int, freed: UInt64, errors: Int, mode: CleaningEngine.Mode)

        static func == (l: Phase, r: Phase) -> Bool {
            switch (l, r) {
            case (.idle, .idle), (.results, .results): true
            case let (.scanning(a, b, c), .scanning(d, e, f)): a == d && b == e && c == f
            case let (.cleaning(a), .cleaning(b)): a == b
            case let (.done(a, b, c, d), .done(e, f, g, h)): a == e && b == f && c == g && d == h
            default: false
            }
        }
    }

    private(set) var phases: [SidebarItem: Phase] = [:]
    private(set) var results: [SidebarItem: [ModuleScanResult]] = [:]
    var selected: [SidebarItem: Set<URL>] = [:]
    private var scanTasks: [SidebarItem: Task<Void, Never>] = [:]

    // MARK: Data panels
    var projects: [ProjectScanService.Entry] = []
    var projectsLoading = false
    var stats: SystemStats?
    var apps: [AppInfo] = []
    var appsLoading = false
    var quarantineRuns: [QuarantineManifest] = []
    var persistence: [PersistenceItem] = []
    var ports: [OpenPort] = []
    var diskRoot: DiskNode?
    var diskScanProgress: DiskTreeScanner.Progress?
    var diskScanning = false

    private let runner = ScanRunner(modules: AllModules.make())
    private var statsTimer: Timer?

    init() {
        settings = CleanSettings.load()
        registry = ProjectRegistry.load()
        quarantineRuns = QuarantineStore.runs()
        QuarantineStore.purgeExpired(retention: settings.quarantineRetention)
        startStats()
    }

    // MARK: - Accessors

    func phase(_ scope: SidebarItem) -> Phase { phases[scope] ?? .idle }
    func results(_ scope: SidebarItem) -> [ModuleScanResult] { results[scope] ?? [] }
    func selection(_ scope: SidebarItem) -> Set<URL> { selected[scope] ?? [] }

    func allItems(_ scope: SidebarItem) -> [FileItem] {
        results(scope).flatMap(\.categories).flatMap(\.items)
    }

    func selectedItems(_ scope: SidebarItem) -> [FileItem] {
        let sel = selection(scope)
        var seen = Set<URL>()
        return allItems(scope).filter { sel.contains($0.url) && seen.insert($0.url).inserted }
    }

    func selectedBytes(_ scope: SidebarItem) -> UInt64 {
        results(scope).flatMap(\.categories).selectedSize(selection(scope))
    }

    func totalBytes(_ scope: SidebarItem) -> UInt64 {
        results(scope).reduce(0) { $0 + $1.totalSize }
    }

    func context() -> ScanContext {
        ScanContext(settings: settings, registry: registry)
    }

    // MARK: - Scanning

    func scan(_ scope: SidebarItem) {
        guard let ids = scope.moduleIDs else { return }
        scanTasks[scope]?.cancel()
        phases[scope] = .scanning(progress: 0, module: "Starting", found: 0)
        results[scope] = []
        selected[scope] = []
        let ctx = context()
        let smart = scope == .smartCare
        scanTasks[scope] = Task { [weak self] in
            guard let self else { return }
            let out = await runner.run(only: smart ? nil : ids, smartScanOnly: smart, context: ctx) { p in
                Task { @MainActor [weak self] in
                    guard let self, case .scanning = self.phase(scope) else { return }
                    self.phases[scope] = .scanning(progress: p.fraction, module: p.currentModule, found: p.bytesFound)
                }
            }
            if Task.isCancelled { return }
            self.results[scope] = out.filter { !$0.categories.isEmpty }
            var auto = Set<URL>()
            for r in out { for c in r.categories where c.autoSelect { c.items.forEach { auto.insert($0.url) } } }
            self.selected[scope] = auto
            self.phases[scope] = .results
            self.settings.lastScanDate = Date()
            if ids.contains("dev_junk") || smart { self.projects = await ProjectScanService.shared.entries }
        }
    }

    func cancelScan(_ scope: SidebarItem) {
        scanTasks[scope]?.cancel()
        phases[scope] = .idle
    }

    func reset(_ scope: SidebarItem) {
        scanTasks[scope]?.cancel()
        phases[scope] = .idle
        results[scope] = []
        selected[scope] = []
    }

    func toggle(_ item: FileItem, in scope: SidebarItem) {
        var s = selection(scope)
        if s.contains(item.url) { s.remove(item.url) } else { s.insert(item.url) }
        selected[scope] = s
    }

    func setCategory(_ cat: ScanResult, selected on: Bool, in scope: SidebarItem) {
        var s = selection(scope)
        for i in cat.items { if on { s.insert(i.url) } else { s.remove(i.url) } }
        selected[scope] = s
    }

    func isCategoryFullySelected(_ cat: ScanResult, in scope: SidebarItem) -> Bool {
        let s = selection(scope)
        return !cat.items.isEmpty && cat.items.allSatisfy { s.contains($0.url) }
    }

    // MARK: - Cleaning

    func clean(_ scope: SidebarItem, mode: CleaningEngine.Mode? = nil) {
        let items = selectedItems(scope)
        guard !items.isEmpty, case .results = phase(scope) else { return }
        let mode = mode ?? settings.defaultCleanMode
        phases[scope] = .cleaning(progress: 0)
        let protectedRoots = projects.filter { !$0.decision.status.allowsCleaning }.map(\.project.path)
        let dispatcher = CleanDispatcher(
            engine: CleaningEngine(guardRails: SafetyGuard(neverTouch: settings.neverTouch, protectedProjectRoots: protectedRoots)),
            virtualCleaners: AllModules.virtualCleaners()
        )
        Task { [weak self] in
            guard let self else { return }
            let result = await dispatcher.clean(items: items, mode: mode, label: scope.title) { p in
                Task { @MainActor [weak self] in self?.phases[scope] = .cleaning(progress: p.fraction) }
            }
            self.phases[scope] = .done(removed: result.removedCount, freed: result.freedBytes, errors: result.errors.count, mode: mode)
            if mode != .dryRun {
                self.settings.lastCleanDate = Date()
                self.settings.lastCleanFreedBytes = result.freedBytes
            }
            self.quarantineRuns = QuarantineStore.runs()
            // Drop removed items from the stored results so a second look is honest.
            self.results[scope] = self.results(scope).map { m in
                var m = m
                m.categories = m.categories.map { c in
                    var c = c
                    c.items.removeAll { result.removedURLs.contains($0.url) }
                    return c
                }.filter { !$0.items.isEmpty }
                return m
            }.filter { !$0.categories.isEmpty }
            self.selected[scope] = []
            self.stats = await SystemStatsCollector.shared.sample()
        }
    }

    // MARK: - Projects

    func refreshProjects() {
        projectsLoading = true
        let ctx = context()
        Task { [weak self] in
            let entries = await ProjectScanService.shared.refresh(context: ctx)
            await MainActor.run { self?.projects = entries; self?.projectsLoading = false }
        }
    }

    func setStatus(_ entry: ProjectScanService.Entry, to status: ProjectStatus?, until: Date? = nil) {
        switch status {
        case .pinned: registry.pin(entry.project, until: until)
        case .cleanable: registry.markCleanable(entry.project)
        default: registry.clearOverride(entry.project)
        }
        let ctx = context()
        Task { [weak self] in
            let entries = await ProjectScanService.shared.reclassify(context: ctx)
            await MainActor.run {
                guard let self else { return }
                self.projects = entries
                self.pruneProjectResults()
            }
        }
    }

    /// After a status change, drop artifacts of newly protected projects from
    /// any pending results and unselect them.
    private func pruneProjectResults() {
        let protected = projects.filter { !$0.decision.status.allowsCleaning }.map(\.project.path)
        for scope in [SidebarItem.smartCare, .devJunk] {
            results[scope] = results(scope).map { m in
                var m = m
                m.categories = m.categories.map { c in
                    var c = c
                    if c.category == .projectDependencies || c.category == .projectBuildOutput {
                        c.items.removeAll { PathExclusion.isExcluded($0.url, by: protected) }
                    }
                    return c
                }.filter { !$0.items.isEmpty }
                return m
            }.filter { !$0.categories.isEmpty }
            selected[scope] = selection(scope).filter { !PathExclusion.isExcluded($0, by: protected) }
        }
    }

    // MARK: - Apps

    func loadApps() {
        guard apps.isEmpty, !appsLoading else { return }
        appsLoading = true
        Task { [weak self] in
            let list = await AppDiscovery.shared.discoverApps()
            await MainActor.run { self?.apps = list; self?.appsLoading = false }
        }
    }

    func uninstall(_ app: AppInfo, leftovers: [FileItem], includeApp: Bool, mode: CleaningEngine.Mode) async -> CleaningEngine.Result {
        var items = leftovers
        if includeApp {
            items.insert(FileItem(url: app.path, size: app.size, isDirectory: true, isPackage: true), at: 0)
        }
        let engine = CleaningEngine(guardRails: SafetyGuard(neverTouch: settings.neverTouch))
        let r = await engine.clean(items: items, mode: mode, label: "Uninstall \(app.name)")
        quarantineRuns = QuarantineStore.runs()
        if includeApp, r.removedURLs.contains(app.path) { apps.removeAll { $0 == app } }
        return r
    }

    // MARK: - Protection, ports, disk

    func loadPersistence() {
        Task.detached { [weak self] in
            let items = PersistenceAudit.audit()
            await MainActor.run { self?.persistence = items }
        }
    }

    func loadPorts() {
        Task { [weak self] in
            let p = await PortService.listListeningPorts()
            await MainActor.run { self?.ports = p }
        }
    }

    func kill(port: OpenPort) {
        Task { [weak self] in
            await PortService.kill(pid: port.pid)
            try? await Task.sleep(for: .milliseconds(300))
            self?.loadPorts()
        }
    }

    func scanDisk(root: URL) {
        diskScanning = true
        diskRoot = nil
        diskScanProgress = nil
        Task { [weak self] in
            let node = await DiskTreeScanner.scan(root: root, skipping: [".Trash"]) { p in
                Task { @MainActor [weak self] in self?.diskScanProgress = p }
            }
            await MainActor.run { self?.diskRoot = node; self?.diskScanning = false }
        }
    }

    func quarantine(paths: [URL], label: String) async -> CleaningEngine.Result {
        let items = paths.map { url -> FileItem in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = isDir ? DirectorySizer.size(of: url).allocated : UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return FileItem(url: url, size: size, isDirectory: isDir)
        }
        let protectedRoots = projects.filter { !$0.decision.status.allowsCleaning }.map(\.project.path)
        let engine = CleaningEngine(guardRails: SafetyGuard(neverTouch: settings.neverTouch, protectedProjectRoots: protectedRoots))
        let r = await engine.clean(items: items, mode: .quarantine, label: label)
        quarantineRuns = QuarantineStore.runs()
        return r
    }

    func restore(_ run: QuarantineManifest) {
        QuarantineStore.restore(run: run)
        quarantineRuns = QuarantineStore.runs()
    }

    func purge(_ run: QuarantineManifest) {
        QuarantineStore.purge(run: run)
        quarantineRuns = QuarantineStore.runs()
    }

    // MARK: - Stats

    private func startStats() {
        Task { [weak self] in self?.stats = await SystemStatsCollector.shared.sample() }
        statsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stats = await SystemStatsCollector.shared.sample()
            }
        }
    }
}

extension ProjectStatus {
    var tint: Color {
        switch self {
        case .active: .green
        case .idle: .yellow
        case .dormant: .orange
        case .pinned: .cyan
        case .cleanable: .pink
        }
    }
}
