import Foundation

/// A discovered project folder with everything needed to decide whether its
/// artifacts may be cleaned.
public struct Project: Identifiable, Sendable, Hashable {
    /// Stable identity: the git remote URL when there is one, else the path.
    /// Moving or renaming a repo keeps its pins and overrides.
    public let id: String
    public let root: URL
    public let name: String
    public let kinds: [ProjectKind]
    public let gitRemote: String?
    /// Latest of: last commit date, newest source mtime (shallow), folder mtime.
    public let lastActivity: Date?
    public let lastCommit: Date?
    public let activitySource: String
    /// Artifact directories that exist, with their sizes.
    public var artifacts: [Artifact]
    /// Live signals gathered at scan time.
    public var signals: Signals

    public struct Artifact: Sendable, Hashable, Identifiable {
        public var id: URL { url }
        public let url: URL
        public let relativePath: String
        public let isDependency: Bool
        public let bytes: UInt64
        public let kindName: String
        public var formattedSize: String { ByteFormatter.string(bytes) }
    }

    public struct Signals: Sendable, Hashable {
        public var runningContainers: Int = 0
        public var openInEditor: Bool = false
        public var devServerRunning: Bool = false
        public init() {}
        public var any: Bool { runningContainers > 0 || openInEditor || devServerRunning }
    }

    public init(root: URL, name: String, kinds: [ProjectKind], gitRemote: String?,
                lastActivity: Date?, lastCommit: Date?, activitySource: String,
                artifacts: [Artifact], signals: Signals = Signals()) {
        self.id = gitRemote.map { "git:\($0)" } ?? "path:\(root.path(percentEncoded: false))"
        self.root = root
        self.name = name
        self.kinds = kinds
        self.gitRemote = gitRemote
        self.lastActivity = lastActivity
        self.lastCommit = lastCommit
        self.activitySource = activitySource
        self.artifacts = artifacts
        self.signals = signals
    }

    public var totalArtifactBytes: UInt64 { artifacts.reduce(0) { $0 + $1.bytes } }
    public var formattedArtifactSize: String { ByteFormatter.string(totalArtifactBytes) }
    public var path: String { root.path(percentEncoded: false) }
    public var kindSummary: String { kinds.map(\.name).joined(separator: " · ") }

    public func daysSinceActivity(now: Date = Date()) -> Int? {
        lastActivity.map { Int(now.timeIntervalSince($0) / 86_400) }
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (l: Project, r: Project) -> Bool { l.id == r.id }
}

/// The decision for a project, with the reason so the UI can explain it.
public enum ProjectStatus: String, Sendable, Codable, CaseIterable {
    /// Recently touched, or has live signals. Nothing deletable.
    case active
    /// Not recent but not dormant either. Listed, never auto-selected.
    case idle
    /// Untouched long enough that deps and build output are fair game.
    case dormant
    /// User override: protect, with optional expiry.
    case pinned
    /// User override: always treat as dormant even if recently touched.
    case cleanable

    public var displayName: String {
        switch self {
        case .active: "Active"
        case .idle: "Idle"
        case .dormant: "Dormant"
        case .pinned: "Pinned"
        case .cleanable: "Cleanable"
        }
    }

    public var systemImage: String {
        switch self {
        case .active: "bolt.fill"
        case .idle: "moon.zzz"
        case .dormant: "zzz"
        case .pinned: "pin.fill"
        case .cleanable: "checkmark.circle"
        }
    }

    /// Whether artifacts under this project may be offered for cleaning.
    public var allowsCleaning: Bool {
        switch self {
        case .dormant, .cleanable: true
        case .active, .idle, .pinned: false
        }
    }
}

public struct ProjectDecision: Sendable, Hashable {
    public let status: ProjectStatus
    public let reason: String
    public let isOverride: Bool
    public let pinnedUntil: Date?

    public init(status: ProjectStatus, reason: String, isOverride: Bool = false, pinnedUntil: Date? = nil) {
        self.status = status
        self.reason = reason
        self.isOverride = isOverride
        self.pinnedUntil = pinnedUntil
    }
}
