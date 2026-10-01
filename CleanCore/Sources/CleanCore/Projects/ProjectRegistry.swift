import Foundation

/// User overrides per project, keyed by the project's stable id. Persisted as
/// JSON so pins survive moves and renames of the project folder.
public struct ProjectOverride: Codable, Sendable, Equatable {
    public var status: ProjectStatus
    /// For `.pinned`: when the pin expires. nil means forever.
    public var until: Date?
    public var note: String?
    public var setAt: Date

    public init(status: ProjectStatus, until: Date? = nil, note: String? = nil, setAt: Date = Date()) {
        self.status = status
        self.until = until
        self.note = note
        self.setAt = setAt
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let until else { return false }
        return now > until
    }
}

public struct ProjectRegistry: Codable, Sendable, Equatable {
    public var overrides: [String: ProjectOverride]
    /// Projects the user hid from the list entirely (still protected from cleaning).
    public var hidden: Set<String>

    public init(overrides: [String: ProjectOverride] = [:], hidden: Set<String> = []) {
        self.overrides = overrides
        self.hidden = hidden
    }

    public func override(for project: Project, now: Date = Date()) -> ProjectOverride? {
        guard let o = overrides[project.id], !o.isExpired(now: now) else { return nil }
        return o
    }

    public mutating func pin(_ project: Project, until: Date? = nil, note: String? = nil) {
        overrides[project.id] = ProjectOverride(status: .pinned, until: until, note: note)
    }

    public mutating func markCleanable(_ project: Project) {
        overrides[project.id] = ProjectOverride(status: .cleanable)
    }

    public mutating func clearOverride(_ project: Project) {
        overrides.removeValue(forKey: project.id)
    }

    // MARK: - Persistence

    public static func load(from url: URL = CMConstants.projectRegistryFile) -> ProjectRegistry {
        guard let data = try? Data(contentsOf: url) else { return ProjectRegistry() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(ProjectRegistry.self, from: data)) ?? ProjectRegistry()
    }

    public func save(to url: URL = CMConstants.projectRegistryFile) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
