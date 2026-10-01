import Foundation
import AppKit

/// Caches, logs, leftovers. Everything here regenerates or belongs to
/// something that is gone.
///
/// Category tables adapted from Mac Sai (BSD-3-Clause).
public struct SystemJunkModule: ScanModule {
    public let id = "system_junk"
    public let name = "System Junk"
    public let group = ModuleGroup.cleanup

    public init() {}

    public func scan(context: ScanContext) async -> [ScanResult] {
        let scanner = TargetedScanner()
        let week: TimeInterval = 7 * 86_400

        async let userCaches = scanner.scan(targets: [
            .wholeDirectory(CMConstants.userCaches, reason: "App cache, regenerated on next launch",
                            excluding: ["com.apple.", "CloudKit", "com.spotify.client", "org.gradle", "pip", "pnpm",
                                        "Homebrew", "ms-playwright", "puppeteer", "Cypress", "typescript", "node-gyp",
                                        "go-build", "CocoaPods", "Yarn", "pypoetry", "composer", "colima", "claude-cli-nodejs",
                                        "Google", "Microsoft Edge", "BraveSoftware", "Firefox", "company.thebrowser"]),
        ])
        async let systemCaches = scanner.scan(targets: [
            .wholeDirectory(CMConstants.systemCaches, reason: "System cache, rebuilt automatically", excluding: ["com.apple."]),
        ])
        async let userLogs = scanner.scan(targets: [
            ScanTarget(path: CMConstants.userLogs, recursive: true, fileExtensions: ["log", "txt", "ips", "diag", "gz"],
                       excludePatterns: ["DiagnosticReports", CMConstants.appName], reason: "Diagnostic log"),
        ])
        async let crashReports = scanner.scan(targets: [
            ScanTarget(path: CMConstants.userDiagnosticReports, recursive: true, minAge: week, reason: "Crash report older than a week"),
        ])
        async let docVersions = scanner.scan(targets: [
            ScanTarget(path: CMConstants.documentVersions, recursive: true, minAge: 4 * 3600, reason: "Autosave revision"),
        ])
        async let backups = scanner.scan(targets: [
            ScanTarget(path: CMConstants.mobileBackups, recursive: false, minAge: 30 * 86_400, reason: "iOS backup older than 30 days"),
        ])
        async let oldPkgs = scanner.scan(targets: [
            ScanTarget(path: CMConstants.userAppSupport, recursive: true, maxDepth: 3, fileExtensions: ["pkg", "mpkg"], minAge: week, reason: "Installer left after updating"),
        ])
        async let dmgs = scanner.scan(targets: [
            ScanTarget(path: CMConstants.downloads, recursive: false, fileExtensions: ["dmg", "iso", "xip", "sparseimage"], minAge: week, reason: "Disk image older than a week"),
        ])
        async let partials = scanner.scan(targets: [
            ScanTarget(path: CMConstants.downloads, recursive: false, fileExtensions: ["download", "crdownload", "part", "partial", "tmp"], reason: "Partial download"),
        ])
        async let editors = scanner.scan(targets: (CMConstants.vsCodeCaches + CMConstants.cursorCaches + CMConstants.antigravityCaches)
            .map { ScanTarget(path: $0, recursive: false, reportDirectoriesAsItems: true, reason: "Editor cache") })
        async let ai = scanner.scan(targets: [CMConstants.claudeCache, CMConstants.claudePasteCache, CMConstants.claudeShellSnapshots,
                                              CMConstants.claudeCliCache, CMConstants.codexCache, CMConstants.codexTmp]
            .map { ScanTarget(path: $0, recursive: false, reportDirectoriesAsItems: true, reason: "AI tool cache") })
        async let chat = scanner.scan(targets: (CMConstants.slackCaches + CMConstants.notionCaches + CMConstants.discordCaches + CMConstants.claudeDesktopCaches)
            .map { ScanTarget(path: $0, recursive: false, reportDirectoriesAsItems: true, reason: "Chat app cache") })

        let brokenPrefs = Self.brokenPreferences()
        let brokenAgents = Self.brokenLaunchAgents()
        let leftovers = AppLeftoversScanner.scan()

        var results: [ScanResult] = []
        func add(_ cat: ScanCategory, _ items: [FileItem]) {
            if !items.isEmpty { results.append(ScanResult(category: cat, items: items.sorted { $0.size > $1.size })) }
        }
        add(.userCaches, await userCaches)
        add(.systemCaches, await systemCaches)
        add(.userLogs, await userLogs)
        add(.crashReports, await crashReports)
        add(.documentVersions, await docVersions)
        add(.iosDeviceBackups, await backups)
        add(.oldUpdates, await oldPkgs)
        add(.unusedDiskImages, await dmgs)
        add(.incompleteDownloads, await partials)
        add(.editorCaches, await editors)
        add(.aiToolCaches, await ai)
        add(.chatAppCaches, await chat)
        add(.brokenPreferences, brokenPrefs)
        add(.brokenLoginItems, brokenAgents)
        add(.appLeftovers, leftovers)
        return results
    }

    /// `~/Library/Preferences/<bundle-id>.plist` whose app no longer exists.
    static func brokenPreferences() -> [FileItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: CMConstants.userPreferences, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return [] }
        let installed = AppLeftoversScanner.installedBundleIDs()
        guard !installed.isEmpty else { return [] }
        var items: [FileItem] = []
        for url in entries where url.pathExtension == "plist" {
            let id = url.deletingPathExtension().lastPathComponent
            guard OrphanedAppFiles.isOrphan(bundleID: id, installedBundleIDs: installed) else { continue }
            // Only flag ids that look like third-party apps, never loose names.
            guard id.split(separator: ".").count >= 3 else { continue }
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            items.append(FileItem(url: url, size: UInt64(v?.fileSize ?? 0), isDirectory: false,
                                  modificationDate: v?.contentModificationDate, reason: "No app with id \(id) is installed"))
        }
        return items
    }

    /// Launch agents whose program path no longer exists.
    static func brokenLaunchAgents() -> [FileItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: CMConstants.userLaunchAgents, includingPropertiesForKeys: [.fileSizeKey]) else { return [] }
        var items: [FileItem] = []
        for url in entries where url.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                items.append(FileItem(url: url, size: 0, isDirectory: false, reason: "Unreadable plist"))
                continue
            }
            let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
            guard let program, !program.isEmpty else { continue }
            if !fm.fileExists(atPath: program) {
                let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                items.append(FileItem(url: url, size: size, isDirectory: false, reason: "Points at missing \(program)"))
            }
        }
        return items
    }
}
