import Foundation
import os

/// Remembers directory sizes between scans so re-scans don't re-walk
/// multi-gigabyte dependency trees. A cached size is reused while the
/// directory's own mtime is unchanged and the entry is younger than a day;
/// deep edits that don't touch the top-level mtime are caught by the daily
/// expiry. Persisted as JSON in Application Support.
public final class SizeCache: Sendable {
    public static let shared = SizeCache()

    struct Entry: Codable, Sendable { let bytes: UInt64; let files: Int; let mtime: TimeInterval; let measured: TimeInterval }

    private let state: OSAllocatedUnfairLock<[String: Entry]>
    private let file = CMConstants.appSupportDir.appending(path: "sizes.json")
    private let maxAge: TimeInterval = 24 * 3600

    private init() {
        var loaded: [String: Entry] = [:]
        if let data = try? Data(contentsOf: CMConstants.appSupportDir.appending(path: "sizes.json")),
           let dict = try? JSONDecoder().decode([String: Entry].self, from: data) {
            loaded = dict
        }
        state = OSAllocatedUnfairLock(initialState: loaded)
    }

    /// Size of a directory, from cache when still valid, else measured and stored.
    public func size(of url: URL) -> DirectorySizer.Sizes {
        let path = url.path(percentEncoded: false)
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let now = Date().timeIntervalSince1970
        if let e = state.withLock({ $0[path] }), e.mtime == mtime, now - e.measured < maxAge {
            ScanTelemetry.shared.visited(path, bytes: e.bytes)
            return DirectorySizer.Sizes(logical: e.bytes, allocated: e.bytes, fileCount: e.files)
        }
        let s = DirectorySizer.size(of: url)
        state.withLock { $0[path] = Entry(bytes: s.allocated, files: s.fileCount, mtime: mtime, measured: now) }
        return s
    }

    public func invalidate(_ url: URL) {
        let p = url.path(percentEncoded: false)
        state.withLock { d in d = d.filter { !$0.key.hasPrefix(p) } }
    }

    public func flush() {
        let snapshot = state.withLock { $0 }
        try? FileManager.default.createDirectory(at: CMConstants.appSupportDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
    }
}
