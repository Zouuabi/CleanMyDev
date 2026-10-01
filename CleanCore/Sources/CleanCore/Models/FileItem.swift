import Foundation
import UniformTypeIdentifiers

/// One cleanable path. Equality and hashing are by URL so the same path found
/// by two categories collapses into one selection.
public struct FileItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let size: UInt64
    public let allocatedSize: UInt64
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let isPackage: Bool
    public let contentType: UTType?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let lastAccessDate: Date?
    public let inode: UInt64
    public let deviceID: Int32
    /// Short, human explanation of why this item is a candidate
    /// ("Regenerates on next build", "Project untouched for 94 days").
    public var reason: String?

    public init(
        url: URL,
        name: String? = nil,
        size: UInt64,
        allocatedSize: UInt64? = nil,
        isDirectory: Bool,
        isSymlink: Bool = false,
        isPackage: Bool = false,
        contentType: UTType? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        lastAccessDate: Date? = nil,
        inode: UInt64 = 0,
        deviceID: Int32 = 0,
        reason: String? = nil
    ) {
        self.id = UUID()
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.size = size
        self.allocatedSize = allocatedSize ?? size
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.contentType = contentType
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.lastAccessDate = lastAccessDate
        self.inode = inode
        self.deviceID = deviceID
        self.reason = reason
    }

    public var formattedSize: String { ByteFormatter.string(size) }
    public var fileExtension: String { url.pathExtension.lowercased() }
    public var path: String { url.path(percentEncoded: false) }

    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
    public static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
}

public enum ByteFormatter {
    nonisolated(unsafe) private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    public static func string(_ bytes: UInt64) -> String {
        formatter.string(fromByteCount: Int64(clamping: bytes))
    }

    public static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
