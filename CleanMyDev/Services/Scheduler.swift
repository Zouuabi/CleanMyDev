import Foundation
import CleanCore

/// Installs or removes a per-user LaunchAgent that opens the app with
/// `--background-clean` once a day. The app handles that flag by running the
/// auto-clean categories through quarantine and quitting.
enum Scheduler {
    static let label = "Mouvema.CleanMyDev.daily"
    static var plistURL: URL { CMConstants.userLaunchAgents.appending(path: "\(label).plist") }

    static func apply(_ settings: CleanSettings) {
        if settings.scheduleEnabled { install(hour: settings.scheduleHour) } else { remove() }
    }

    static func install(hour: Int) {
        guard let exe = Bundle.main.executableURL?.path(percentEncoded: false) else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe, "--background-clean"],
            "StartCalendarInterval": ["Hour": hour, "Minute": 0],
            "RunAtLoad": false,
        ]
        try? FileManager.default.createDirectory(at: CMConstants.userLaunchAgents, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: plistURL)
            Task { _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", plistURL.path(percentEncoded: false)]) ; _ = await Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path(percentEncoded: false)]) }
        }
    }

    static func remove() {
        Task { _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", plistURL.path(percentEncoded: false)]) }
        try? FileManager.default.removeItem(at: plistURL)
    }

    /// Headless run: scan the smart modules, quarantine only auto-clean
    /// categories, log, and exit.
    static func runBackgroundClean() async {
        let settings = CleanSettings.load()
        let registry = ProjectRegistry.load()
        QuarantineStore.purgeExpired(retention: settings.quarantineRetention)
        let ctx = ScanContext(settings: settings, registry: registry)
        let runner = ScanRunner(modules: AllModules.make())
        let results = await runner.run(smartScanOnly: true, context: ctx) { _ in }
        let allowed = settings.effectiveAutoCleanCategories
        let items = results.flatMap(\.categories).filter { allowed.contains($0.category) }.flatMap(\.items)
        let protectedRoots = await ProjectScanService.shared.protectedRoots()
        let dispatcher = CleanDispatcher(
            engine: CleaningEngine(guardRails: SafetyGuard(neverTouch: settings.neverTouch, protectedProjectRoots: protectedRoots)),
            virtualCleaners: AllModules.virtualCleaners()
        )
        let r = await dispatcher.clean(items: items, mode: .quarantine, label: "scheduled")
        var s = settings
        s.lastScanDate = Date()
        if r.removedCount > 0 { s.lastCleanDate = Date(); s.lastCleanFreedBytes = r.freedBytes }
        try? s.save()
    }
}
