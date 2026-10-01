import Foundation

public struct AppInfo: Identifiable, Hashable, Sendable {
    public var id: String { path.path(percentEncoded: false) }
    public let bundleIdentifier: String
    public let name: String
    public let path: URL
    public let version: String?
    public let size: UInt64
    public let lastOpened: Date?
    public let isAppleApp: Bool
    public let source: Source

    public enum Source: String, Sendable {
        case appStore, homebrew, direct, system
    }

    public init(
        bundleIdentifier: String,
        name: String,
        path: URL,
        version: String? = nil,
        size: UInt64 = 0,
        lastOpened: Date? = nil,
        isAppleApp: Bool = false,
        source: Source = .direct
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
        self.version = version
        self.size = size
        self.lastOpened = lastOpened
        self.isAppleApp = isAppleApp
        self.source = source
    }

    public var formattedSize: String { ByteFormatter.string(size) }

    public var isUnused: Bool {
        guard let lastOpened else { return false }
        return Date().timeIntervalSince(lastOpened) > 180 * 24 * 3600
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
        hasher.combine(path)
    }

    public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.path == rhs.path
    }
}
