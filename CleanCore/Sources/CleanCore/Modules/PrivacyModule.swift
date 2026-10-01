import Foundation
import AppKit

/// Browser caches and history. Cookies, logins, bookmarks, and extensions are
/// never touched. History files are only offered when the browser is closed,
/// since Chromium holds them open with a lock.
public struct PrivacyModule: ScanModule {
    public let id = "privacy"
    public let name = "Browsers"
    public let group = ModuleGroup.protection

    public init() {}

    struct Browser: Sendable {
        let name: String
        let bundleID: String
        let appSupport: URL
        let cache: URL?
        let chromium: Bool
    }

    static let browsers: [Browser] = [
        Browser(name: "Chrome", bundleID: "com.google.Chrome", appSupport: CMConstants.chromeAppSupport, cache: CMConstants.chromeCache, chromium: true),
        Browser(name: "Edge", bundleID: "com.microsoft.edgemac", appSupport: CMConstants.edgeAppSupport, cache: CMConstants.edgeCache, chromium: true),
        Browser(name: "Brave", bundleID: "com.brave.Browser", appSupport: CMConstants.braveAppSupport, cache: CMConstants.braveCache, chromium: true),
        Browser(name: "Arc", bundleID: "company.thebrowser.Browser", appSupport: CMConstants.arcAppSupport, cache: CMConstants.arcCache, chromium: true),
        Browser(name: "Firefox", bundleID: "org.mozilla.firefox", appSupport: CMConstants.firefoxProfiles, cache: CMConstants.firefoxCache, chromium: false),
        Browser(name: "Safari", bundleID: "com.apple.Safari", appSupport: CMConstants.userLibrary.appending(path: "Safari"), cache: CMConstants.safariCache, chromium: false),
    ]

    @MainActor
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    public func scan(context: ScanContext) async -> [ScanResult] {
        let running = await Self.runningBundleIDs()
        let fm = FileManager.default
        var cacheItems: [FileItem] = []
        var historyItems: [FileItem] = []

        for b in Self.browsers {
            let isRunning = running.contains(b.bundleID)
            let runningNote = isRunning ? " (\(b.name) is running, cache will refill)" : ""
            if let cache = b.cache, fm.fileExists(atPath: cache.path(percentEncoded: false)) {
                let bytes = DirectorySizer.size(of: cache).allocated
                if bytes > 0 {
                    cacheItems.append(FileItem(url: cache, name: "\(b.name) cache", size: bytes, isDirectory: true, reason: "Page cache\(runningNote)"))
                }
            }
            guard b.chromium, let profiles = try? fm.contentsOfDirectory(at: b.appSupport, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for profile in profiles {
                let pname = profile.lastPathComponent
                guard pname == "Default" || pname.hasPrefix("Profile ") || pname == "Guest Profile" else { continue }
                for sub in ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage", "Service Worker/ScriptCache", "DawnCache", "GrShaderCache", "ShaderCache"] {
                    let url = profile.appending(path: sub)
                    guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
                    let bytes = DirectorySizer.size(of: url).allocated
                    guard bytes > 0 else { continue }
                    cacheItems.append(FileItem(url: url, name: "\(b.name) \(pname) · \(sub)", size: bytes, isDirectory: true, reason: "Page cache\(runningNote)"))
                }
                if !isRunning {
                    for file in ["History", "History-journal", "Visited Links", "Top Sites", "Shortcuts"] {
                        let url = profile.appending(path: file)
                        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { continue }
                        historyItems.append(FileItem(url: url, name: "\(b.name) \(pname) · \(file)", size: UInt64(size), isDirectory: false,
                                                     reason: "Browsing history. Logins and bookmarks stay"))
                    }
                }
            }
        }

        var results: [ScanResult] = []
        if !cacheItems.isEmpty { results.append(ScanResult(category: .browserCache, items: cacheItems.sorted { $0.size > $1.size })) }
        if !historyItems.isEmpty { results.append(ScanResult(category: .browserHistory, items: historyItems)) }

        let scanner = TargetedScanner()
        let recent = await scanner.scan(targets: [
            ScanTarget(path: CMConstants.userAppSupport.appending(path: "com.apple.sharedfilelist"), recursive: true, fileExtensions: ["sfl2", "sfl3"], reason: "Recent items list"),
        ])
        if !recent.isEmpty { results.append(ScanResult(category: .systemPrivacy, items: recent, autoSelect: false)) }
        return results
    }
}
