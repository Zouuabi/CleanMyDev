import Foundation

/// One category's worth of findings from a module scan.
public struct ScanResult: Sendable, Identifiable {
    public var id: ScanCategory { category }
    public let category: ScanCategory
    public var items: [FileItem]
    /// When true the UI pre-checks every item. Categories that need a human
    /// decision (large files, dormant project deps, app leftovers) are false.
    public let autoSelect: Bool

    public init(category: ScanCategory, items: [FileItem], autoSelect: Bool? = nil) {
        self.category = category
        self.items = items
        self.autoSelect = autoSelect ?? category.autoSelect
    }

    public var totalSize: UInt64 { items.reduce(0) { $0 + $1.size } }
    public var fileCount: Int { items.count }
    public var formattedSize: String { ByteFormatter.string(totalSize) }
}

public struct ModuleScanResult: Sendable, Identifiable {
    public var id: String { moduleID }
    public let moduleID: String
    public let moduleName: String
    public var categories: [ScanResult]
    public let scanDuration: TimeInterval

    public init(moduleID: String, moduleName: String, categories: [ScanResult], scanDuration: TimeInterval) {
        self.moduleID = moduleID
        self.moduleName = moduleName
        self.categories = categories
        self.scanDuration = scanDuration
    }

    public var totalSize: UInt64 { categories.reduce(0) { $0 + $1.totalSize } }
    public var totalFileCount: Int { categories.reduce(0) { $0 + $1.fileCount } }
    public var formattedSize: String { ByteFormatter.string(totalSize) }
}

public extension Array where Element == ScanResult {
    /// Drops items the current process could not delete anyway, and anything
    /// under a user "never touch" folder, so the UI only shows actionable rows.
    func filteringUncleanable(neverTouch: [String]) -> [ScanResult] {
        map { result in
            ScanResult(
                category: result.category,
                items: result.items.filter { CleanFilter.isActionable($0.url, neverTouch: neverTouch) },
                autoSelect: result.autoSelect
            )
        }
        .filter { !$0.items.isEmpty }
    }

    /// Bytes for the selected URLs, counting each URL once even if it appears
    /// in several categories.
    func selectedSize(_ selected: Set<URL>) -> UInt64 {
        var counted = Set<URL>()
        var total: UInt64 = 0
        for result in self {
            for item in result.items where selected.contains(item.url) && counted.insert(item.url).inserted {
                total += item.size
            }
        }
        return total
    }
}
