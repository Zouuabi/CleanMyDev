import Foundation
import Darwin

/// Full directory tree with sizes for the treemap. Parallel BSD walk with
/// inode de-dup; one volume only.
///
/// Adapted from MacDirStat's FileScanner / FileNode (MIT, © phalladar).
public final class DiskNode: Identifiable, @unchecked Sendable {
    public let id: UInt64
    public let name: String
    public let isDirectory: Bool
    public let ownSize: Int64
    public let category: DiskCategory
    public let modificationDate: Date?
    public weak var parent: DiskNode?
    public private(set) var children: [DiskNode] = []
    public private(set) var totalSize: Int64 = 0
    public private(set) var fileCount: Int = 0

    public var path: String {
        var parts: [String] = []
        var node: DiskNode? = self
        while let n = node { parts.append(n.name); node = n.parent }
        return parts.reversed().joined(separator: "/").replacingOccurrences(of: "//", with: "/")
    }
    public var url: URL { URL(filePath: path) }
    public var formattedSize: String { ByteFormatter.string(totalSize) }

    init(inode: UInt64, name: String, isDirectory: Bool, ownSize: Int64, category: DiskCategory, modificationDate: Date?) {
        self.id = inode
        self.name = name
        self.isDirectory = isDirectory
        self.ownSize = ownSize
        self.category = category
        self.modificationDate = modificationDate
        self.totalSize = ownSize
        self.fileCount = isDirectory ? 0 : 1
    }

    func addChild(_ c: DiskNode) { c.parent = self; children.append(c) }

    func finalize() {
        guard isDirectory else { return }
        var size = ownSize
        var files = 0
        for c in children { c.finalize(); size += c.totalSize; files += c.fileCount }
        totalSize = size
        fileCount = files
        children.sort { $0.totalSize > $1.totalSize }
    }

    public func categoryBreakdown() -> [(DiskCategory, Int64)] {
        var acc: [DiskCategory: Int64] = [:]
        accumulate(into: &acc)
        return acc.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private func accumulate(into acc: inout [DiskCategory: Int64]) {
        if !isDirectory { acc[category, default: 0] += ownSize }
        for c in children { c.accumulate(into: &acc) }
    }
}

public enum DiskCategory: String, CaseIterable, Sendable {
    case code, dependencies, build, media, image, document, archive, app, data, other

    public var displayName: String {
        switch self {
        case .code: "Code"
        case .dependencies: "Dependencies"
        case .build: "Build Output"
        case .media: "Video & Audio"
        case .image: "Images"
        case .document: "Documents"
        case .archive: "Archives"
        case .app: "Apps & Installers"
        case .data: "Databases & Data"
        case .other: "Other"
        }
    }

    static let depDirs: Set<String> = ["node_modules", "Pods", "venv", ".venv", "vendor", ".gradle", "site-packages"]
    static let buildDirs: Set<String> = ["build", "dist", "target", ".next", ".build", "DerivedData", "__pycache__", ".turbo", "out"]

    static func forExtension(_ ext: String) -> DiskCategory {
        switch ext {
        case "swift", "ts", "tsx", "js", "jsx", "py", "rs", "go", "java", "kt", "c", "cpp", "h", "m", "rb", "php", "sh", "css", "scss", "html", "vue", "svelte", "dart": .code
        case "mp4", "mov", "mkv", "avi", "webm", "mp3", "wav", "aac", "flac", "m4a", "m4v": .media
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "psd", "ai", "raw", "tiff": .image
        case "pdf", "doc", "docx", "txt", "md", "pages", "key", "numbers", "xls", "xlsx", "ppt", "pptx", "csv": .document
        case "zip", "tar", "gz", "7z", "rar", "xz", "bz2", "tgz": .archive
        case "app", "dmg", "pkg", "iso", "xip", "ipa", "apk": .app
        case "db", "sqlite", "sqlite3", "json", "parquet", "bin", "safetensors", "pt", "pth", "onnx", "gguf", "qcow2", "img", "vmdk": .data
        default: .other
        }
    }
}

public enum DiskTreeScanner {
    public struct Progress: Sendable { public let files: Int; public let bytes: Int64; public let current: String }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        let rootDevice: dev_t
        var seen = Set<UInt64>()
        var files = 0
        var bytes: Int64 = 0
        let skip: Set<String>
        let onProgress: (@Sendable (Progress) -> Void)?
        init(rootDevice: dev_t, skip: Set<String>, onProgress: (@Sendable (Progress) -> Void)?) {
            self.rootDevice = rootDevice; self.skip = skip; self.onProgress = onProgress
        }
        func markDir(_ ino: UInt64) -> Bool { lock.lock(); defer { lock.unlock() }; return seen.insert(ino).inserted }
        func addFile(_ ino: UInt64, nlink: UInt16, size: Int64, path: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if nlink > 1, !seen.insert(ino).inserted { return false }
            files += 1; bytes += size
            if files % 20_000 == 0 { onProgress?(Progress(files: files, bytes: bytes, current: path)) }
            return true
        }
    }

    public static func scan(root: URL, skipping: Set<String> = [], onProgress: (@Sendable (Progress) -> Void)? = nil) async -> DiskNode? {
        let path = root.path(percentEncoded: false)
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let state = State(rootDevice: st.st_dev, skip: skipping, onProgress: onProgress)
        guard let node = await scanDir(path: path, name: path, inheritedCategory: nil, state: state) else { return nil }
        node.finalize()
        return node
    }

    private static func scanDir(path: String, name: String, inheritedCategory: DiskCategory?, state: State) async -> DiskNode? {
        var st = stat()
        guard lstat(path, &st) == 0, state.markDir(UInt64(st.st_ino)) else { return nil }
        let node = DiskNode(inode: UInt64(st.st_ino), name: name, isDirectory: true, ownSize: 0, category: inheritedCategory ?? .other,
                            modificationDate: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)))
        guard let dir = opendir(path) else { return node }
        let fd = dirfd(dir)
        var subdirs: [(String, String)] = []
        while let entry = readdir(dir) {
            var nameBuf = entry.pointee.d_name
            let entryName = withUnsafePointer(to: &nameBuf) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            if entryName == "." || entryName == ".." { continue }
            let dtype = entry.pointee.d_type
            if dtype != DT_DIR && dtype != DT_REG && dtype != DT_UNKNOWN { continue }
            var cst = stat()
            let ok = withUnsafePointer(to: &nameBuf) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { fstatat(fd, $0, &cst, AT_SYMLINK_NOFOLLOW) == 0 } }
            guard ok, cst.st_dev == state.rootDevice else { continue }
            let childPath = path.hasSuffix("/") ? path + entryName : path + "/" + entryName
            let mode = cst.st_mode & S_IFMT
            if mode == S_IFDIR {
                if state.skip.contains(entryName) { continue }
                subdirs.append((childPath, entryName))
            } else if mode == S_IFREG {
                let size = Int64(cst.st_blocks) * 512
                guard state.addFile(UInt64(cst.st_ino), nlink: UInt16(cst.st_nlink), size: size, path: childPath) else { continue }
                let ext = entryName.split(separator: ".").last.map { String($0).lowercased() } ?? ""
                let cat = inheritedCategory ?? (entryName.contains(".") ? DiskCategory.forExtension(ext) : .other)
                node.addChild(DiskNode(inode: UInt64(cst.st_ino), name: entryName, isDirectory: false, ownSize: size, category: cat,
                                       modificationDate: Date(timeIntervalSince1970: TimeInterval(cst.st_mtimespec.tv_sec))))
            }
        }
        closedir(dir)

        if subdirs.isEmpty { return node }
        await withTaskGroup(of: DiskNode?.self) { group in
            for (p, n) in subdirs {
                let cat: DiskCategory? = DiskCategory.depDirs.contains(n) ? .dependencies : DiskCategory.buildDirs.contains(n) ? .build : inheritedCategory
                group.addTask { await scanDir(path: p, name: n, inheritedCategory: cat, state: state) }
            }
            for await child in group { if let child { node.addChild(child) } }
        }
        return node
    }
}

// MARK: - Squarified treemap layout

public struct TreemapRect: Sendable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public var area: Double { width * height }
    public var minSide: Double { min(width, height) }
    public func contains(_ p: CGPoint) -> Bool { p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height }
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
}

public struct TreemapItem: Identifiable, Sendable {
    public let id: Int
    public let node: DiskNode
    public let rect: TreemapRect
    public let depth: Int
}

/// Squarify (Bruls, Huizing, van Wijk 2000). Adapted from MacDirStat (MIT).
public struct TreemapLayout: Sendable {
    public var maxDepth: Int
    public var minPixelArea: Double
    public var padding: Double

    public init(maxDepth: Int = 6, minPixelArea: Double = 16, padding: Double = 2) {
        self.maxDepth = maxDepth; self.minPixelArea = minPixelArea; self.padding = padding
    }

    public func layout(root: DiskNode, in bounds: TreemapRect) -> [TreemapItem] {
        var items: [TreemapItem] = []
        var next = 0
        place(root, bounds, 0, &items, &next)
        return items
    }

    private func place(_ node: DiskNode, _ bounds: TreemapRect, _ depth: Int, _ items: inout [TreemapItem], _ next: inout Int) {
        guard bounds.area >= minPixelArea else { return }
        items.append(TreemapItem(id: next, node: node, rect: bounds, depth: depth)); next += 1
        guard node.isDirectory, depth < maxDepth else { return }
        let children = node.children.filter { $0.totalSize > 0 }
        guard !children.isEmpty else { return }
        let inner = TreemapRect(x: bounds.x + padding, y: bounds.y + padding + (depth == 0 ? 0 : 0),
                                width: max(0, bounds.width - 2 * padding), height: max(0, bounds.height - 2 * padding))
        guard inner.area > 0 else { return }
        let total = Double(children.reduce(0) { $0 + $1.totalSize })
        let sizes = children.map { Double($0.totalSize) / total * inner.area }
        let rects = Self.squarify(sizes: sizes, in: inner)
        for (i, c) in children.enumerated() where i < rects.count {
            place(c, rects[i], depth + 1, &items, &next)
        }
    }

    static func squarify(sizes: [Double], in bounds: TreemapRect) -> [TreemapRect] {
        guard !sizes.isEmpty else { return [] }
        var rects = [TreemapRect](repeating: TreemapRect(x: 0, y: 0, width: 0, height: 0), count: sizes.count)
        var remaining = bounds
        var index = 0
        while index < sizes.count {
            let short = remaining.minSide
            var row = [index]
            var rowSum = sizes[index]
            var bestWorst = worst([sizes[index]], rowSum, short)
            var next = index + 1
            while next < sizes.count {
                let newSum = rowSum + sizes[next]
                let newWorst = worst(row.map { sizes[$0] } + [sizes[next]], newSum, short)
                if newWorst > bestWorst { break }
                bestWorst = newWorst; row.append(next); rowSum = newSum; next += 1
            }
            let fraction = remaining.area > 0 ? rowSum / remaining.area : 0
            if remaining.width >= remaining.height {
                let w = remaining.width * fraction
                var y = remaining.y
                for i in row {
                    let h = rowSum > 0 ? (sizes[i] / rowSum) * remaining.height : 0
                    rects[i] = TreemapRect(x: remaining.x, y: y, width: w, height: h); y += h
                }
                remaining = TreemapRect(x: remaining.x + w, y: remaining.y, width: remaining.width - w, height: remaining.height)
            } else {
                let h = remaining.height * fraction
                var x = remaining.x
                for i in row {
                    let w = rowSum > 0 ? (sizes[i] / rowSum) * remaining.width : 0
                    rects[i] = TreemapRect(x: x, y: remaining.y, width: w, height: h); x += w
                }
                remaining = TreemapRect(x: remaining.x, y: remaining.y + h, width: remaining.width, height: remaining.height - h)
            }
            index = next
        }
        return rects
    }

    private static func worst(_ row: [Double], _ total: Double, _ short: Double) -> Double {
        guard short > 0, total > 0 else { return .infinity }
        let s2 = short * short
        return row.filter { $0 > 0 }.map { max((s2 * $0) / (total * total), (total * total) / (s2 * $0)) }.max() ?? 0
    }
}
