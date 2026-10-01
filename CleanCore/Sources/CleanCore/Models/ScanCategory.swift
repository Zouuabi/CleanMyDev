import Foundation

/// Every kind of thing the app can find. Grouped by the module that produces it.
public enum ScanCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    // System junk
    case userCaches, systemCaches, userLogs, systemLogs, crashReports
    case documentVersions, brokenPreferences, brokenLoginItems
    case iosDeviceBackups, oldUpdates, unusedDiskImages, incompleteDownloads
    case appLeftovers, editorCaches, aiToolCaches, chatAppCaches

    // Dev junk
    case packageManagerCaches, mlModelCaches, xcodeJunk, simulators
    case projectDependencies, projectBuildOutput
    case dockerImages, dockerVolumes, dockerBuildCache, dockerContainers

    // Protection
    case malware, suspiciousPersistence, browserCache, browserHistory, systemPrivacy

    // Files
    case largeFiles, oldFiles, duplicates
    case trashBins, mailAttachments

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .userCaches: "User Caches"
        case .systemCaches: "System Caches"
        case .userLogs: "User Logs"
        case .systemLogs: "System Logs"
        case .crashReports: "Crash Reports"
        case .documentVersions: "Document Versions"
        case .brokenPreferences: "Broken Preferences"
        case .brokenLoginItems: "Broken Login Items"
        case .iosDeviceBackups: "iOS Device Backups"
        case .oldUpdates: "Old Installer Packages"
        case .unusedDiskImages: "Unused Disk Images"
        case .incompleteDownloads: "Incomplete Downloads"
        case .appLeftovers: "Leftovers from Deleted Apps"
        case .editorCaches: "Editor Caches"
        case .aiToolCaches: "AI Tool Caches"
        case .chatAppCaches: "Chat App Caches"
        case .packageManagerCaches: "Package Manager Caches"
        case .mlModelCaches: "ML Model Caches"
        case .xcodeJunk: "Xcode Junk"
        case .simulators: "Simulators"
        case .projectDependencies: "Project Dependencies"
        case .projectBuildOutput: "Project Build Output"
        case .dockerImages: "Docker Images"
        case .dockerVolumes: "Docker Volumes"
        case .dockerBuildCache: "Docker Build Cache"
        case .dockerContainers: "Stopped Containers"
        case .malware: "Known Malware"
        case .suspiciousPersistence: "Suspicious Startup Items"
        case .browserCache: "Browser Caches"
        case .browserHistory: "Browser History"
        case .systemPrivacy: "Recent Items Lists"
        case .largeFiles: "Large Files"
        case .oldFiles: "Old Files"
        case .duplicates: "Duplicates"
        case .trashBins: "Trash"
        case .mailAttachments: "Mail Attachments"
        }
    }

    public var subtitle: String {
        switch self {
        case .userCaches: "App temporary files. Regenerated on next launch."
        case .systemCaches: "macOS-managed caches. Rebuilt automatically."
        case .userLogs: "Diagnostic logs written by your apps."
        case .systemLogs: "macOS diagnostic logs."
        case .crashReports: "Crash and hang reports older than a week."
        case .documentVersions: "Old autosaved document revisions."
        case .brokenPreferences: "Preference files whose app is gone."
        case .brokenLoginItems: "Launch agents pointing at apps that are gone."
        case .iosDeviceBackups: "Local iPhone and iPad backups older than 30 days."
        case .oldUpdates: "Installer packages left behind after updating."
        case .unusedDiskImages: "DMG and ISO files sitting in Downloads for over a week."
        case .incompleteDownloads: "Partially downloaded files."
        case .appLeftovers: "Support files from apps you've uninstalled."
        case .editorCaches: "VS Code, Cursor, Antigravity caches. Settings and extensions stay."
        case .aiToolCaches: "Claude and Codex caches. History and sessions stay."
        case .chatAppCaches: "Slack, Discord, Notion caches. They refill on next launch."
        case .packageManagerCaches: "npm, pnpm, pip, uv, cargo, go, gradle, brew. All re-downloadable."
        case .mlModelCaches: "Downloaded Hugging Face and Torch model weights."
        case .xcodeJunk: "DerivedData, archives, device support, previews."
        case .simulators: "Simulator devices whose runtime is gone or that are unused."
        case .projectDependencies: "node_modules, venvs, Pods in projects you haven't touched in a while."
        case .projectBuildOutput: ".next, dist, target, build in dormant projects."
        case .dockerImages: "Images no container uses. Sizes count only layers not shared with kept images."
        case .dockerVolumes: "Volumes not attached to any container."
        case .dockerBuildCache: "BuildKit layer cache."
        case .dockerContainers: "Containers that exited and never restarted."
        case .malware: "Files matching known macOS adware and malware families."
        case .suspiciousPersistence: "Startup items that are unsigned or run shell payloads."
        case .browserCache: "Page caches. Logins and bookmarks stay."
        case .browserHistory: "Browsing history. Cookies and sessions stay."
        case .systemPrivacy: "Recent documents and server lists."
        case .largeFiles: "The biggest files in your home folder."
        case .oldFiles: "Files not opened in six months."
        case .duplicates: "Identical copies of the same file."
        case .trashBins: "Items currently in the Trash."
        case .mailAttachments: "Cached copies of Mail attachments."
        }
    }

    public var systemImage: String {
        switch self {
        case .userCaches, .systemCaches: "folder.badge.gearshape"
        case .userLogs, .systemLogs: "doc.text"
        case .crashReports: "exclamationmark.triangle"
        case .documentVersions: "doc.on.doc"
        case .brokenPreferences: "gearshape.2"
        case .brokenLoginItems: "person.crop.circle.badge.exclamationmark"
        case .iosDeviceBackups: "iphone"
        case .oldUpdates: "shippingbox"
        case .unusedDiskImages: "opticaldisc"
        case .incompleteDownloads: "arrow.down.circle.dotted"
        case .appLeftovers: "shippingbox.and.arrow.backward"
        case .editorCaches: "chevron.left.forwardslash.chevron.right"
        case .aiToolCaches: "sparkles"
        case .chatAppCaches: "bubble.left.and.bubble.right"
        case .packageManagerCaches: "shippingbox.fill"
        case .mlModelCaches: "brain"
        case .xcodeJunk: "hammer"
        case .simulators: "iphone.gen3"
        case .projectDependencies: "cube.box"
        case .projectBuildOutput: "wrench.and.screwdriver"
        case .dockerImages, .dockerVolumes, .dockerBuildCache, .dockerContainers: "shippingbox"
        case .malware: "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .suspiciousPersistence: "exclamationmark.shield"
        case .browserCache, .browserHistory: "safari"
        case .systemPrivacy: "hand.raised"
        case .largeFiles: "arrow.up.right.square"
        case .oldFiles: "clock.arrow.circlepath"
        case .duplicates: "plus.square.on.square"
        case .trashBins: "trash"
        case .mailAttachments: "paperclip"
        }
    }

    /// Categories that are safe enough to pre-check in the UI.
    public var autoSelect: Bool {
        switch self {
        case .largeFiles, .oldFiles, .duplicates, .appLeftovers,
             .projectDependencies, .projectBuildOutput, .mlModelCaches,
             .dockerVolumes, .dockerImages, .iosDeviceBackups, .browserHistory, .simulators,
             .brokenPreferences, .malware, .suspiciousPersistence:
            false
        default:
            true
        }
    }

    /// Whether a scheduled background run may clean this without asking.
    /// Everything else is "show me first". Users can tighten this in settings
    /// but never loosen it beyond this list.
    public var eligibleForAutoClean: Bool {
        switch self {
        case .userCaches, .userLogs, .crashReports, .incompleteDownloads,
             .packageManagerCaches, .editorCaches, .aiToolCaches, .chatAppCaches,
             .browserCache, .xcodeJunk, .dockerBuildCache:
            true
        default:
            false
        }
    }
}
