import Foundation

/// Pure description of what to enumerate. Consumed by `TargetedScanner`.
public struct ScanTarget: Sendable, Equatable {
    public let path: URL
    public let recursive: Bool
    public let maxDepth: Int?
    public let fileExtensions: Set<String>?
    public let minAge: TimeInterval?
    public let maxAge: TimeInterval?
    public let minSize: UInt64?
    public let excludePatterns: [String]
    public let skipHiddenDirectories: Bool
    /// When true, directories are reported as single items (sized recursively)
    /// instead of descending into them. Right for "delete this whole cache
    /// folder" categories; wrong for "find big files".
    public let reportDirectoriesAsItems: Bool
    public let reason: String?

    public init(
        path: URL,
        recursive: Bool = true,
        maxDepth: Int? = nil,
        fileExtensions: Set<String>? = nil,
        minAge: TimeInterval? = nil,
        maxAge: TimeInterval? = nil,
        minSize: UInt64? = nil,
        excludePatterns: [String] = [],
        skipHiddenDirectories: Bool = false,
        reportDirectoriesAsItems: Bool = false,
        reason: String? = nil
    ) {
        self.path = path
        self.recursive = recursive
        self.maxDepth = maxDepth
        self.fileExtensions = fileExtensions.map { Set($0.map { $0.lowercased() }) }
        self.minAge = minAge
        self.maxAge = maxAge
        self.minSize = minSize
        self.excludePatterns = excludePatterns
        self.skipHiddenDirectories = skipHiddenDirectories
        self.reportDirectoriesAsItems = reportDirectoriesAsItems
        self.reason = reason
    }

    /// Convenience: the whole directory as one deletable unit, with its
    /// immediate children listed so the user can keep some.
    public static func wholeDirectory(_ path: URL, reason: String? = nil, excluding: [String] = []) -> ScanTarget {
        ScanTarget(path: path, recursive: false, excludePatterns: excluding,
                   reportDirectoriesAsItems: true, reason: reason)
    }

    public static func isHiddenEntry(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".")
    }

    public func matchesByNameRules(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        for pattern in excludePatterns where name.localizedCaseInsensitiveContains(pattern) {
            return false
        }
        if let extensions = fileExtensions, !extensions.isEmpty {
            if !extensions.contains(url.pathExtension.lowercased()) { return false }
        }
        return true
    }

    public func passesSizeFilter(_ size: UInt64) -> Bool {
        guard let minSize else { return true }
        return size >= minSize
    }

    public func passesAgeFilters(modificationDate: Date?, now: Date = Date()) -> Bool {
        guard minAge != nil || maxAge != nil else { return true }
        guard let modDate = modificationDate else { return false }
        let age = now.timeIntervalSince(modDate)
        if let minAge, age < minAge { return false }
        if let maxAge, age > maxAge { return false }
        return true
    }
}
