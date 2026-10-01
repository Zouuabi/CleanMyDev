import Foundation
import AppKit

/// App discovery and leftover matching.
///
/// Matching engine adapted from Mac Sai's AppMatching / OrphanedAppFiles
/// (BSD-3-Clause), which in turn credits Pearcleaner's approach.
public actor AppDiscovery {
    public static let shared = AppDiscovery()

    public func discoverApps() -> [AppInfo] {
        var apps: [AppInfo] = []
        var seen = Set<String>()
        let caskApps = Self.homebrewCaskAppNames()
        for dir in [URL(filePath: "/Applications"), CMConstants.home.appending(path: "Applications")] {
            for url in Self.appBundles(in: dir) {
                let path = url.path(percentEncoded: false)
                guard seen.insert(path).inserted, let info = Self.appInfo(from: url, caskApps: caskApps) else { continue }
                apps.append(info)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func appBundles(in dir: URL, maxDepth: Int = 4) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if enumerator.level >= maxDepth { enumerator.skipDescendants() }
            if url.pathExtension == "app" {
                found.append(url)
                enumerator.skipDescendants()
            }
        }
        return found
    }

    static func appInfo(from url: URL, caskApps: Set<String>) -> AppInfo? {
        let plistURL = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        let version = plist["CFBundleShortVersionString"] as? String
        let isApple = bundleID.hasPrefix("com.apple.")
        let size = DirectorySizer.size(of: url).allocated
        let source: AppInfo.Source
        if isApple { source = .system }
        else if FileManager.default.fileExists(atPath: url.appending(path: "Contents/_MASReceipt").path(percentEncoded: false)) { source = .appStore }
        else if caskApps.contains(url.lastPathComponent.lowercased()) { source = .homebrew }
        else { source = .direct }
        let lastOpened = Self.lastUsed(url)
        return AppInfo(bundleIdentifier: bundleID, name: name, path: url, version: version, size: size,
                       lastOpened: lastOpened, isAppleApp: isApple, source: source)
    }

    /// Spotlight's kMDItemLastUsedDate is the only honest "last opened".
    static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Names of `.app` bundles installed by Homebrew casks (lowercased).
    static func homebrewCaskAppNames() -> Set<String> {
        var names = Set<String>()
        for root in ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"] {
            guard let tokens = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for token in tokens {
                guard let versions = try? FileManager.default.contentsOfDirectory(atPath: "\(root)/\(token)") else { continue }
                for v in versions {
                    guard let files = try? FileManager.default.contentsOfDirectory(atPath: "\(root)/\(token)/\(v)") else { continue }
                    for f in files where f.hasSuffix(".app") { names.insert(f.lowercased()) }
                }
            }
        }
        return names
    }
}

public enum AppMatching {
    public enum MatchLevel: Int, CaseIterable, Sendable {
        case bundleIDExact = 1, displayName, appDirName, normalizedName, bundleIDComponents, baseBundleID, versionStripped, companyName
    }

    public static let librarySubdirectories: [String] = [
        "Application Support", "Caches", "Containers", "Group Containers", "Preferences", "Logs",
        "Application Scripts", "Cookies", "HTTPStorages", "LaunchAgents", "Saved Application State",
        "Internet Plug-Ins", "PreferencePanes", "PrivilegedHelperTools", "Services", "WebKit", "Frameworks",
    ]

    public static func generatePatterns(for app: AppInfo, maxLevel: MatchLevel = .versionStripped) -> Set<String> {
        var patterns: Set<String> = []
        for level in MatchLevel.allCases where level.rawValue <= maxLevel.rawValue {
            switch level {
            case .bundleIDExact: patterns.insert(app.bundleIdentifier.lowercased())
            case .displayName: patterns.insert(app.name.lowercased())
            case .appDirName: patterns.insert(app.path.deletingPathExtension().lastPathComponent.lowercased())
            case .normalizedName:
                let n = app.name.lowercased().filter(\.isLetter)
                if n.count >= 3 { patterns.insert(n) }
            case .bundleIDComponents:
                let c = app.bundleIdentifier.components(separatedBy: ".")
                if c.count >= 2 { patterns.insert(c.suffix(2).joined(separator: ".").lowercased()) }
            case .baseBundleID:
                var base = app.bundleIdentifier.lowercased()
                for s in [".helper", ".agent", ".daemon", ".launcher", ".updater"] where base.hasSuffix(s) { base = String(base.dropLast(s.count)) }
                patterns.insert(base)
            case .versionStripped:
                let s = app.name.replacingOccurrences(of: "\\d+(\\.\\d+)*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces).lowercased()
                if s.count >= 3 { patterns.insert(s) }
            case .companyName:
                let c = app.bundleIdentifier.components(separatedBy: ".")
                if c.count >= 2, c[1].count >= 3, c[1].lowercased() != "apple" { patterns.insert(c[1].lowercased()) }
            }
        }
        let generic: Set<String> = ["app", "mac", "macos", "desktop", "client", "helper", "google", "microsoft"]
        return patterns.filter { $0.count >= 3 && !generic.contains($0) }
    }

    public static func filenameMatches(_ fileName: String, patterns: Set<String>) -> Bool {
        let lower = fileName.lowercased()
        return patterns.contains { !$0.isEmpty && lower.contains($0) }
    }
}

public struct AppPathFinder: Sendable {
    public let maxLevel: AppMatching.MatchLevel
    public init(maxLevel: AppMatching.MatchLevel = .versionStripped) { self.maxLevel = maxLevel }

    public func findAssociatedFiles(for app: AppInfo) -> [FileItem] {
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: maxLevel)
        var found: [FileItem] = []
        let fm = FileManager.default
        var dirs = AppMatching.librarySubdirectories.map { CMConstants.userLibrary.appending(path: $0) }
        dirs += [CMConstants.systemLaunchDaemons, CMConstants.systemLaunchAgents, URL(filePath: "/Library/Application Support"), URL(filePath: "/Library/PrivilegedHelperTools")]
        for dir in dirs {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
            for url in contents where AppMatching.filenameMatches(url.lastPathComponent, patterns: patterns) {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let size = isDir ? DirectorySizer.size(of: url).allocated : UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                found.append(FileItem(url: url, size: size, isDirectory: isDir, reason: "Matches \(app.name) in \(dir.lastPathComponent)"))
            }
        }
        return found.sorted { $0.size > $1.size }
    }
}

public enum OrphanedAppFiles {
    static let helperSuffixes = [".helper", ".agent", ".daemon", ".launcher", ".updater", ".framework", ".xpc",
                                 ".findersync", ".quicklook", ".shareextension", ".widget", ".loginitem", ".service"]
    static let neverFlagPrefixes = ["com.apple.", "org.chromium.", "com.google.keystone", "org.qt-project.", "io.qt.",
                                    "com.github.electron", "com.electron.", "com.microsoft.autoupdate", "com.microsoft.edgemac",
                                    "com.google.chrome", "org.mozilla."]

    public static func isOrphan(bundleID: String, installedBundleIDs: Set<String>) -> Bool {
        let id = bundleID.lowercased()
        guard isBundleIDLike(id) else { return false }
        if neverFlagPrefixes.contains(where: { id == $0 || id.hasPrefix($0) }) { return false }
        let base = strippingHelperSuffixes(id)
        for installed in installedBundleIDs {
            let i = installed.lowercased()
            if sharesLineage(i, id) || sharesLineage(i, base) { return false }
        }
        return true
    }

    static func sharesLineage(_ a: String, _ b: String) -> Bool {
        a == b || a.hasPrefix(b + ".") || b.hasPrefix(a + ".")
    }

    static func isBundleIDLike(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    static func strippingHelperSuffixes(_ id: String) -> String {
        var r = id
        var changed = true
        while changed {
            changed = false
            for s in helperSuffixes where r.hasSuffix(s) && r.count > s.count { r = String(r.dropLast(s.count)); changed = true }
        }
        return r
    }
}

public enum AppLeftoversScanner {
    static let appSearchRoots: [URL] = [
        URL(filePath: "/Applications"), URL(filePath: "/System/Applications"),
        URL(filePath: "/System/Applications/Utilities"), URL(filePath: "/System/Library/CoreServices"),
        CMConstants.home.appending(path: "Applications"),
    ]

    static var safeRoots: [URL] {
        [CMConstants.userCaches, CMConstants.userLogs, CMConstants.userHTTPStorages, CMConstants.userSavedAppState,
         CMConstants.userWebKit, CMConstants.userAppSupport, CMConstants.userContainers]
    }

    public static func scan() -> [FileItem] {
        let installed = installedBundleIDs()
        guard installed.count > 20 else { return [] }
        let fm = FileManager.default
        var items: [FileItem] = []
        var seen = Set<URL>()
        for root in safeRoots {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for entry in entries {
                var candidate = entry.lastPathComponent
                if candidate.hasSuffix(".savedState") { candidate = String(candidate.dropLast(".savedState".count)) }
                guard OrphanedAppFiles.isOrphan(bundleID: candidate, installedBundleIDs: installed) else { continue }
                guard seen.insert(entry.standardizedFileURL).inserted else { continue }
                let size = DirectorySizer.size(of: entry).allocated
                guard size > 0 else { continue }
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? true
                items.append(FileItem(url: entry, name: "\(root.lastPathComponent)/\(entry.lastPathComponent)", size: size, isDirectory: isDir,
                                      reason: "No installed app owns \(candidate)"))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    public static func installedBundleIDs() -> Set<String> {
        var ids: Set<String> = []
        for root in appSearchRoots {
            for app in AppDiscovery.appBundles(in: root) {
                guard let data = try? Data(contentsOf: app.appending(path: "Contents/Info.plist")),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let id = plist["CFBundleIdentifier"] as? String else { continue }
                ids.insert(id.lowercased())
            }
        }
        // Running processes count as installed too (menu-bar apps living in odd places).
        for app in NSWorkspace.shared.runningApplications { if let id = app.bundleIdentifier { ids.insert(id.lowercased()) } }
        return ids
    }
}
