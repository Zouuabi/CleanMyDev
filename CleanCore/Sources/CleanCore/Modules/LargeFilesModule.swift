import Foundation

/// Big and old files in the home folder. Never auto-selected and excluded
/// from Smart Care's "junk found" total, because a big file is not junk.
public struct LargeFilesModule: ScanModule {
    public let id = "large_files"
    public let name = "Large & Old Files"
    public let group = ModuleGroup.files
    public let includedInSmartScan = false

    public init() {}

    public func scan(context: ScanContext) async -> [ScanResult] {
        let scanner = TargetedScanner()
        let minSize = context.settings.largeFileThreshold
        let items = await scanner.scan(targets: [
            ScanTarget(path: CMConstants.home, recursive: true, maxDepth: 8, minSize: minSize,
                       excludePatterns: ["Library", ".Trash", "node_modules", ".git", "Pods", "venv", ".venv", "target", ".colima", "DerivedData"],
                       skipHiddenDirectories: true),
        ])
        let (large, old) = Self.split(items: items, minSize: minSize, now: context.now)
        var results: [ScanResult] = []
        if !large.isEmpty { results.append(ScanResult(category: .largeFiles, items: large)) }
        if !old.isEmpty { results.append(ScanResult(category: .oldFiles, items: old)) }
        return results
    }

    public static func split(items: [FileItem], minSize: UInt64, oldThreshold: TimeInterval = 180 * 86_400, now: Date) -> (large: [FileItem], old: [FileItem]) {
        var large: [FileItem] = []
        var old: [FileItem] = []
        let cutoff = now.addingTimeInterval(-oldThreshold)
        for var item in items where !item.isDirectory {
            let accessed = item.lastAccessDate ?? item.modificationDate
            if item.size >= minSize {
                item.reason = accessed.map { "Last opened \(Int(now.timeIntervalSince($0) / 86_400)) days ago" }
                large.append(item)
            }
            if let accessed, accessed < cutoff {
                var o = item
                o.reason = "Not opened for \(Int(now.timeIntervalSince(accessed) / 86_400)) days"
                old.append(o)
            }
        }
        large.sort { $0.size > $1.size }
        old.sort { ($0.lastAccessDate ?? .distantFuture) < ($1.lastAccessDate ?? .distantFuture) }
        return (large, Array(old.prefix(500)))
    }
}

public struct TrashModule: ScanModule {
    public let id = "trash"
    public let name = "Trash"
    public let group = ModuleGroup.cleanup
    public init() {}

    public func scan(context: ScanContext) async -> [ScanResult] {
        let scanner = TargetedScanner()
        var targets = [ScanTarget.wholeDirectory(CMConstants.userTrash, reason: "In the Trash")]
        if let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) {
            for v in volumes where v.path != "/" {
                targets.append(.wholeDirectory(v.appending(path: ".Trashes/\(getuid())"), reason: "In the Trash on \(v.lastPathComponent)"))
            }
        }
        let items = await scanner.scan(targets: targets)
        return items.isEmpty ? [] : [ScanResult(category: .trashBins, items: items)]
    }
}
