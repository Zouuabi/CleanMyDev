import Foundation

/// Well-known paths and safety limits. Nothing in here is user-configurable;
/// anything the user can tune lives in `CleanSettings`.
///
/// Path tables adapted from Mac Sai (BSD-3-Clause, © iliyami contributors).
public enum CMConstants {
    public static let appName = "CleanMyDev"
    public static let bundleIdentifier = "Mouvema.CleanMyDev"

    // MARK: - Safety limits

    public static let maxFilesPerOperation = 10_000
    public static let cleanChunkSize = 5_000
    public static let maxTotalItemsPerCleanOperation = 500_000

    /// Paths the engine refuses to delete under, after symlink resolution.
    public static let protectedPaths: Set<String> = [
        "/System", "/usr", "/bin", "/sbin", "/Library/Apple", "/private/var/db",
    ]

    public static let protectedApps: Set<String> = [
        "com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Terminal",
        "com.apple.systempreferences", "com.apple.ActivityMonitor", "com.apple.Console",
        "com.apple.DiskUtility", "com.apple.dt.Xcode", "com.apple.AppStore",
        "com.apple.iCal", "com.apple.AddressBook", "com.apple.Preview", "com.apple.TextEdit",
        "com.apple.calculator", "com.apple.Dictionary", "com.apple.Maps", "com.apple.Notes",
        "com.apple.reminders", "com.apple.Stickies", "com.apple.VoiceMemos", "com.apple.stocks",
        "com.apple.weather", "com.apple.Passwords", "com.apple.FaceTime", "com.apple.MobileSMS",
        "com.apple.Photos", "com.apple.Music",
    ]

    // MARK: - Home / Library

    public static let home = FileManager.default.homeDirectoryForCurrentUser
    public static let userLibrary = home.appending(path: "Library")
    public static let userCaches = userLibrary.appending(path: "Caches")
    public static let userLogs = userLibrary.appending(path: "Logs")
    public static let userPreferences = userLibrary.appending(path: "Preferences")
    public static let userAppSupport = userLibrary.appending(path: "Application Support")
    public static let userContainers = userLibrary.appending(path: "Containers")
    public static let userGroupContainers = userLibrary.appending(path: "Group Containers")
    public static let userLaunchAgents = userLibrary.appending(path: "LaunchAgents")
    public static let userSavedAppState = userLibrary.appending(path: "Saved Application State")
    public static let userCookies = userLibrary.appending(path: "Cookies")
    public static let userHTTPStorages = userLibrary.appending(path: "HTTPStorages")
    public static let userWebKit = userLibrary.appending(path: "WebKit")
    public static let userDiagnosticReports = userLogs.appending(path: "DiagnosticReports")

    public static let systemLibrary = URL(filePath: "/Library")
    public static let systemCaches = systemLibrary.appending(path: "Caches")
    public static let systemLogs = systemLibrary.appending(path: "Logs")
    public static let systemLaunchAgents = systemLibrary.appending(path: "LaunchAgents")
    public static let systemLaunchDaemons = systemLibrary.appending(path: "LaunchDaemons")
    public static let varLog = URL(filePath: "/var/log")

    public static let userTrash = home.appending(path: ".Trash")
    public static let downloads = home.appending(path: "Downloads")
    public static let documentVersions = home.appending(path: ".DocumentRevisions-V100")
    public static let mobileBackups = userAppSupport.appending(path: "MobileSync/Backup")

    // MARK: - Xcode

    public static let xcodeDerivedData = userLibrary.appending(path: "Developer/Xcode/DerivedData")
    public static let xcodeArchives = userLibrary.appending(path: "Developer/Xcode/Archives")
    public static let xcodeDeviceSupport = userLibrary.appending(path: "Developer/Xcode/iOS DeviceSupport")
    public static let coreSimulatorDevices = userLibrary.appending(path: "Developer/CoreSimulator/Devices")
    public static let coreSimulatorCaches = userLibrary.appending(path: "Developer/CoreSimulator/Caches")
    public static let xcodePreviews = userLibrary.appending(path: "Developer/Xcode/UserData/Previews")

    // MARK: - Browsers

    public static let safariCache = userCaches.appending(path: "com.apple.Safari")
    public static let chromeAppSupport = userAppSupport.appending(path: "Google/Chrome")
    public static let chromeCache = userCaches.appending(path: "Google/Chrome")
    public static let edgeAppSupport = userAppSupport.appending(path: "Microsoft Edge")
    public static let edgeCache = userCaches.appending(path: "Microsoft Edge")
    public static let braveAppSupport = userAppSupport.appending(path: "BraveSoftware/Brave-Browser")
    public static let braveCache = userCaches.appending(path: "BraveSoftware/Brave-Browser")
    public static let arcAppSupport = userAppSupport.appending(path: "Arc/User Data")
    public static let arcCache = userCaches.appending(path: "company.thebrowser.Browser")
    public static let firefoxProfiles = userAppSupport.appending(path: "Firefox/Profiles")
    public static let firefoxCache = userCaches.appending(path: "Firefox/Profiles")

    // MARK: - Package managers and dev tool caches (global, not per-project)

    public static let npmCacache = home.appending(path: ".npm/_cacache")
    public static let npxCache = home.appending(path: ".npm/_npx")
    public static let pnpmStore = userLibrary.appending(path: "pnpm/store")
    public static let pnpmCache = userCaches.appending(path: "pnpm")
    public static let yarnCache = userCaches.appending(path: "Yarn")
    public static let bunCache = home.appending(path: ".bun/install/cache")
    public static let pipCache = userCaches.appending(path: "pip")
    public static let uvCache = home.appending(path: ".cache/uv")
    public static let poetryCache = userCaches.appending(path: "pypoetry")
    public static let cargoRegistryCache = home.appending(path: ".cargo/registry/cache")
    public static let cargoRegistrySrc = home.appending(path: ".cargo/registry/src")
    public static let cargoGitCheckouts = home.appending(path: ".cargo/git/checkouts")
    public static let goModCache = home.appending(path: "go/pkg/mod/cache")
    public static let goBuildCache = userCaches.appending(path: "go-build")
    public static let gradleCaches = home.appending(path: ".gradle/caches")
    public static let gradleDaemon = home.appending(path: ".gradle/daemon")
    public static let gradleWrapperDists = home.appending(path: ".gradle/wrapper/dists")
    public static let mavenRepo = home.appending(path: ".m2/repository")
    public static let cocoapodsCache = userCaches.appending(path: "CocoaPods")
    public static let homebrewCache = userCaches.appending(path: "Homebrew")
    public static let pubCache = home.appending(path: ".pub-cache")
    public static let composerCache = userCaches.appending(path: "composer")
    public static let playwrightBrowsers = userCaches.appending(path: "ms-playwright")
    public static let puppeteerCache = userCaches.appending(path: "puppeteer")
    public static let cypressCache = userCaches.appending(path: "Cypress")
    public static let typescriptCache = userCaches.appending(path: "typescript")
    public static let nodeGypCache = userCaches.appending(path: "node-gyp")
    public static let colimaCache = userCaches.appending(path: "colima")
    public static let huggingFaceCache = home.appending(path: ".cache/huggingface")
    public static let torchCache = home.appending(path: ".cache/torch")

    // MARK: - Editors and AI tools (cache dirs only, never settings/sessions)

    public static func electronCaches(_ appSupportName: String) -> [URL] {
        let base = userAppSupport.appending(path: appSupportName)
        return ["Cache", "Code Cache", "GPUCache", "CachedData", "CachedProfilesData", "CachedExtensionVSIXs"]
            .map { base.appending(path: $0) }
    }
    public static var vsCodeCaches: [URL] { electronCaches("Code") }
    public static var cursorCaches: [URL] { electronCaches("Cursor") }
    public static var antigravityCaches: [URL] { electronCaches("Antigravity") }
    public static var slackCaches: [URL] { electronCaches("Slack") }
    public static var notionCaches: [URL] { electronCaches("Notion") }
    public static var discordCaches: [URL] { electronCaches("discord") }
    public static var claudeDesktopCaches: [URL] { electronCaches("Claude") }

    public static let claudeCache = home.appending(path: ".claude/cache")
    public static let claudePasteCache = home.appending(path: ".claude/paste-cache")
    public static let claudeShellSnapshots = home.appending(path: ".claude/shell-snapshots")
    public static let claudeCliCache = userCaches.appending(path: "claude-cli-nodejs")
    public static let codexCache = home.appending(path: ".codex/cache")
    public static let codexTmp = home.appending(path: ".codex/.tmp")

    // MARK: - App data directories

    public static let appSupportDir = userAppSupport.appending(path: appName)
    public static let quarantineDir = appSupportDir.appending(path: "Quarantine")
    public static let settingsFile = appSupportDir.appending(path: "settings.json")
    public static let projectRegistryFile = appSupportDir.appending(path: "projects.json")
    public static let operationLogDir = userLogs.appending(path: appName)
    public static let operationLogFile = operationLogDir.appending(path: "operations.log")
}
