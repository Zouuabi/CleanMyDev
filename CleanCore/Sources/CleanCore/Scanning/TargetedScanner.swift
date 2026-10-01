import Foundation
import Darwin

/// Enumerates `ScanTarget`s into `FileItem`s. Targets run in parallel; items
/// are de-duplicated by URL across targets.
///
/// Adapted from Mac Sai's TargetedScanner (BSD-3-Clause).
public actor TargetedScanner {
    public struct Outcome: Sendable {
        public let items: [FileItem]
        public let permissionDeniedPaths: [URL]
    }

    private static let resourceKeys: [URLResourceKey] = [
        .fileSizeKey, .fileAllocatedSizeKey, .totalFileSizeKey, .totalFileAllocatedSizeKey,
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .contentModificationDateKey, .creationDateKey, .contentAccessDateKey,
        .contentTypeKey, .nameKey,
    ]

    public init() {}

    public func scan(targets: [ScanTarget]) async -> [FileItem] {
        await scanReportingPermissions(targets: targets).items
    }

    public func scanReportingPermissions(targets: [ScanTarget]) async -> Outcome {
        await withTaskGroup(of: (items: [FileItem], denied: URL?).self) { group in
            for target in targets {
                group.addTask { Self.scanTarget(target) }
            }
            var all: [FileItem] = []
            var seen = Set<URL>()
            var denied: [URL] = []
            for await result in group {
                for item in result.items where seen.insert(item.url).inserted { all.append(item) }
                if let d = result.denied { denied.append(d) }
            }
            return Outcome(items: all, permissionDeniedPaths: denied)
        }
    }

    private static func isPermissionDenied(_ url: URL) -> Bool {
        let fd = open(url.path(percentEncoded: false), O_RDONLY | O_DIRECTORY)
        if fd >= 0 { close(fd); return false }
        return errno == EPERM || errno == EACCES
    }

    nonisolated private static func scanTarget(_ target: ScanTarget) -> (items: [FileItem], denied: URL?) {
        let fm = FileManager.default
        let rootPath = target.path.path(percentEncoded: false)
        guard fm.fileExists(atPath: rootPath) else { return ([], nil) }
        if isPermissionDenied(target.path) { return ([], target.path) }

        var results: [FileItem] = []

        if target.reportDirectoriesAsItems {
            guard let contents = try? fm.contentsOfDirectory(
                at: target.path, includingPropertiesForKeys: resourceKeys
            ) else { return ([], nil) }
            for url in contents {
                if Task.isCancelled { break }
                guard matchesTarget(url: url, target: target) else { continue }
                if let item = makeFileItem(from: url, sizeDirectories: true, reason: target.reason) {
                    results.append(item)
                }
            }
            return (results, nil)
        }

        if target.recursive {
            guard let enumerator = fm.enumerator(
                at: target.path, includingPropertiesForKeys: resourceKeys, options: [.skipsPackageDescendants]
            ) else { return ([], nil) }

            while let obj = enumerator.nextObject() {
                if Task.isCancelled { break }
                guard let url = obj as? URL else { continue }
                ScanTelemetry.shared.visited(url.path(percentEncoded: false))

                if let maxDepth = target.maxDepth, enumerator.level > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if target.skipHiddenDirectories && ScanTarget.isHiddenEntry(url) {
                    if isDir { enumerator.skipDescendants() }
                    continue
                }
                if matchesExcludePattern(url: url, target: target) {
                    if isDir { enumerator.skipDescendants() }
                    continue
                }
                if matchesTarget(url: url, target: target),
                   let item = makeFileItem(from: url, sizeDirectories: false, reason: target.reason) {
                    results.append(item)
                }
            }
        } else {
            guard let contents = try? fm.contentsOfDirectory(
                at: target.path, includingPropertiesForKeys: resourceKeys
            ) else { return ([], nil) }
            for url in contents {
                if Task.isCancelled { break }
                if matchesTarget(url: url, target: target),
                   let item = makeFileItem(from: url, sizeDirectories: true, reason: target.reason) {
                    results.append(item)
                }
            }
        }
        return (results, nil)
    }

    nonisolated private static func matchesExcludePattern(url: URL, target: ScanTarget) -> Bool {
        let name = url.lastPathComponent
        return target.excludePatterns.contains { name.localizedCaseInsensitiveContains($0) }
    }

    nonisolated private static func matchesTarget(url: URL, target: ScanTarget) -> Bool {
        if matchesExcludePattern(url: url, target: target) { return false }
        if let extensions = target.fileExtensions, !extensions.isEmpty,
           !extensions.contains(url.pathExtension.lowercased()) {
            return false
        }
        if target.minSize != nil || target.minAge != nil || target.maxAge != nil {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                return false
            }
            if let minSize = target.minSize, UInt64(values.fileSize ?? 0) < minSize { return false }
            if !target.passesAgeFilters(modificationDate: values.contentModificationDate) { return false }
        }
        return true
    }

    nonisolated private static func makeFileItem(from url: URL, sizeDirectories: Bool, reason: String?) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
        let isDir = values.isDirectory ?? false
        var size = UInt64(values.totalFileSize ?? values.fileSize ?? 0)
        var allocated = UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        if isDir && sizeDirectories {
            let sizes = DirectorySizer.size(of: url)
            size = sizes.logical
            allocated = sizes.allocated
        }
        var st = stat()
        let hasIdentity = lstat(url.path(percentEncoded: false), &st) == 0
        return FileItem(
            url: url,
            name: values.name ?? url.lastPathComponent,
            size: size,
            allocatedSize: allocated,
            isDirectory: isDir,
            isSymlink: values.isSymbolicLink ?? false,
            isPackage: values.isPackage ?? false,
            contentType: values.contentType,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            lastAccessDate: values.contentAccessDate,
            inode: hasIdentity ? UInt64(st.st_ino) : 0,
            deviceID: hasIdentity ? Int32(st.st_dev) : 0,
            reason: reason
        )
    }
}

/// Fast recursive directory sizing on BSD APIs. Dedupes hard links by inode.
public enum DirectorySizer {
    public struct Sizes: Sendable {
        public let logical: UInt64
        public let allocated: UInt64
        public let fileCount: Int
    }

    public static func size(of url: URL) -> Sizes {
        var logical: UInt64 = 0
        var allocated: UInt64 = 0
        var count = 0
        var seen = Set<UInt64>()
        walk(url.path(percentEncoded: false), &logical, &allocated, &count, &seen)
        return Sizes(logical: logical, allocated: allocated, fileCount: count)
    }

    private static func walk(_ path: String, _ logical: inout UInt64, _ allocated: inout UInt64,
                             _ count: inout Int, _ seen: inout Set<UInt64>) {
        guard let dir = opendir(path) else {
            // Might be a file, not a directory.
            var st = stat()
            if lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG {
                logical += UInt64(st.st_size)
                allocated += UInt64(st.st_blocks) * 512
                count += 1
            }
            return
        }
        defer { closedir(dir) }
        let fd = dirfd(dir)
        while let entry = readdir(dir) {
            var nameBuf = entry.pointee.d_name
            let name = withUnsafePointer(to: &nameBuf) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            var st = stat()
            let ok = withUnsafePointer(to: &nameBuf) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    fstatat(fd, $0, &st, AT_SYMLINK_NOFOLLOW) == 0
                }
            }
            guard ok else { continue }
            let mode = st.st_mode & S_IFMT
            if mode == S_IFDIR {
                walk(path + "/" + name, &logical, &allocated, &count, &seen)
            } else if mode == S_IFREG {
                if st.st_nlink > 1, !seen.insert(UInt64(st.st_ino)).inserted { continue }
                logical += UInt64(st.st_size)
                allocated += UInt64(st.st_blocks) * 512
                count += 1
                ScanTelemetry.shared.visited(count & 63 == 0 ? path + "/" + name : nil, bytes: UInt64(st.st_blocks) * 512)
            }
        }
    }
}
