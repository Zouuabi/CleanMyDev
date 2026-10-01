import Foundation

/// Everything the user can tune. Persisted as JSON in Application Support so
/// it survives reinstalls and can be edited by hand.
public struct CleanSettings: Codable, Sendable, Equatable {
    /// Folders to look for projects in. Defaults to the home folder; `Library`
    /// and hidden folders are always skipped during project discovery.
    public var scanRoots: [String]
    /// Absolute folders nothing in the app may ever delete from.
    public var neverTouch: [String]
    /// A project is Active if it had a commit or file change within this many days.
    public var activeDays: Int
    /// A project is Dormant once untouched for this many days. Between
    /// `activeDays` and `dormantDays` it is Idle: shown, never auto-selected.
    public var dormantDays: Int
    /// Large-file threshold in bytes.
    public var largeFileThreshold: UInt64
    /// Keep quarantined items this many days before purging them for good.
    public var quarantineRetentionDays: Int
    /// What "Clean" does by default.
    public var defaultCleanMode: CleaningEngine.Mode
    /// Scheduled runs: enabled, and which categories may be cleaned without asking.
    public var scheduleEnabled: Bool
    public var autoCleanCategories: Set<ScanCategory>
    /// Hour of day (0-23) for the daily background run.
    public var scheduleHour: Int
    /// Show the menu bar extra.
    public var menuBarEnabled: Bool
    public var soundsEnabled: Bool
    /// Last time a scan completed, for the menu bar readout.
    public var lastScanDate: Date?
    public var lastCleanDate: Date?
    public var lastCleanFreedBytes: UInt64

    public init(
        scanRoots: [String] = [CMConstants.homePath],
        neverTouch: [String] = CleanSettings.defaultNeverTouch,
        activeDays: Int = 14,
        dormantDays: Int = 30,
        largeFileThreshold: UInt64 = 100 * 1024 * 1024,
        quarantineRetentionDays: Int = 7,
        defaultCleanMode: CleaningEngine.Mode = .quarantine,
        scheduleEnabled: Bool = false,
        autoCleanCategories: Set<ScanCategory> = [.userCaches, .userLogs, .crashReports, .packageManagerCaches, .editorCaches, .aiToolCaches],
        scheduleHour: Int = 12,
        menuBarEnabled: Bool = true,
        soundsEnabled: Bool = true,
        lastScanDate: Date? = nil,
        lastCleanDate: Date? = nil,
        lastCleanFreedBytes: UInt64 = 0
    ) {
        self.scanRoots = scanRoots
        self.neverTouch = neverTouch
        self.activeDays = activeDays
        self.dormantDays = dormantDays
        self.largeFileThreshold = largeFileThreshold
        self.quarantineRetentionDays = quarantineRetentionDays
        self.defaultCleanMode = defaultCleanMode
        self.scheduleEnabled = scheduleEnabled
        self.autoCleanCategories = autoCleanCategories
        self.scheduleHour = scheduleHour
        self.menuBarEnabled = menuBarEnabled
        self.soundsEnabled = soundsEnabled
        self.lastScanDate = lastScanDate
        self.lastCleanDate = lastCleanDate
        self.lastCleanFreedBytes = lastCleanFreedBytes
    }

    public static let defaultNeverTouch: [String] = {
        let home = CMConstants.homePath
        return [
            "\(home)/Library/Keychains",
            "\(home)/Library/Application Support/Claude/vm_bundles",
            "\(home)/.colima",
            "\(home)/.ssh",
            "\(home)/.gnupg",
        ]
    }()

    enum CodingKeys: String, CodingKey {
        case scanRoots, neverTouch, activeDays, dormantDays, largeFileThreshold, quarantineRetentionDays, defaultCleanMode,
             scheduleEnabled, autoCleanCategories, scheduleHour, menuBarEnabled, soundsEnabled, lastScanDate, lastCleanDate, lastCleanFreedBytes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CleanSettings()
        scanRoots = try c.decodeIfPresent([String].self, forKey: .scanRoots) ?? d.scanRoots
        neverTouch = try c.decodeIfPresent([String].self, forKey: .neverTouch) ?? d.neverTouch
        activeDays = try c.decodeIfPresent(Int.self, forKey: .activeDays) ?? d.activeDays
        dormantDays = try c.decodeIfPresent(Int.self, forKey: .dormantDays) ?? d.dormantDays
        largeFileThreshold = try c.decodeIfPresent(UInt64.self, forKey: .largeFileThreshold) ?? d.largeFileThreshold
        quarantineRetentionDays = try c.decodeIfPresent(Int.self, forKey: .quarantineRetentionDays) ?? d.quarantineRetentionDays
        defaultCleanMode = try c.decodeIfPresent(CleaningEngine.Mode.self, forKey: .defaultCleanMode) ?? d.defaultCleanMode
        scheduleEnabled = try c.decodeIfPresent(Bool.self, forKey: .scheduleEnabled) ?? d.scheduleEnabled
        autoCleanCategories = try c.decodeIfPresent(Set<ScanCategory>.self, forKey: .autoCleanCategories) ?? d.autoCleanCategories
        scheduleHour = try c.decodeIfPresent(Int.self, forKey: .scheduleHour) ?? d.scheduleHour
        menuBarEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? d.menuBarEnabled
        soundsEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? d.soundsEnabled
        lastScanDate = try c.decodeIfPresent(Date.self, forKey: .lastScanDate)
        lastCleanDate = try c.decodeIfPresent(Date.self, forKey: .lastCleanDate)
        lastCleanFreedBytes = try c.decodeIfPresent(UInt64.self, forKey: .lastCleanFreedBytes) ?? 0
    }

    public var quarantineRetention: TimeInterval { TimeInterval(quarantineRetentionDays * 86_400) }

    /// Only categories the engine deems safe may be auto-cleaned, whatever the file says.
    public var effectiveAutoCleanCategories: Set<ScanCategory> {
        autoCleanCategories.filter(\.eligibleForAutoClean)
    }

    // MARK: - Persistence

    public static func load(from url: URL = CMConstants.settingsFile) -> CleanSettings {
        guard let data = try? Data(contentsOf: url) else { return CleanSettings() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(CleanSettings.self, from: data)) ?? CleanSettings()
    }

    public func save(to url: URL = CMConstants.settingsFile) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
