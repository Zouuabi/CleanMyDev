import Foundation

public struct QuarantineManifest: Codable, Sendable, Identifiable {
    public struct Entry: Codable, Sendable, Identifiable {
        public var id: String { stored }
        public let original: String
        public let stored: String
        public let bytes: UInt64
    }

    public var id: String { runID }
    public let runID: String
    public let date: Date
    public let label: String
    public let mode: CleaningEngine.Mode
    public var entries: [Entry]

    public var totalBytes: UInt64 { entries.reduce(0) { $0 + $1.bytes } }
    public var formattedSize: String { ByteFormatter.string(totalBytes) }
}

/// Reads, restores, and purges quarantine runs. Each run is one folder with a
/// `manifest.json` next to the moved items.
public enum QuarantineStore {
    static let manifestName = "manifest.json"

    static func write(_ manifest: QuarantineManifest, to root: URL) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(manifest) {
            try? data.write(to: root.appending(path: manifestName))
        }
    }

    public static func runs() -> [QuarantineManifest] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: CMConstants.quarantineDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dirs.compactMap { dir -> QuarantineManifest? in
            guard let data = try? Data(contentsOf: dir.appending(path: manifestName)) else { return nil }
            return try? dec.decode(QuarantineManifest.self, from: data)
        }
        .sorted { $0.date > $1.date }
    }

    public static func totalBytes() -> UInt64 {
        runs().reduce(0) { $0 + $1.totalBytes }
    }

    /// Moves every entry back to its original path. Entries whose original
    /// location already exists again are left in quarantine and reported.
    @discardableResult
    public static func restore(run: QuarantineManifest) -> [String] {
        let fm = FileManager.default
        var failed: [String] = []
        var remaining: [QuarantineManifest.Entry] = []
        for entry in run.entries {
            let src = URL(filePath: entry.stored)
            let dst = URL(filePath: entry.original)
            guard fm.fileExists(atPath: entry.stored) else { continue }
            if fm.fileExists(atPath: entry.original) {
                failed.append(entry.original)
                remaining.append(entry)
                continue
            }
            do {
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: src, to: dst)
                OperationLog.append("[RESTORED] \(entry.original)")
            } catch {
                failed.append(entry.original)
                remaining.append(entry)
                OperationLog.append("[RESTORE-ERROR] \(entry.original) — \(error.localizedDescription)")
            }
        }
        let root = CMConstants.quarantineDir.appending(path: run.runID)
        if remaining.isEmpty {
            try? fm.removeItem(at: root)
        } else {
            var updated = run
            updated.entries = remaining
            write(updated, to: root)
        }
        return failed
    }

    /// Permanently deletes one run.
    public static func purge(run: QuarantineManifest) {
        let root = CMConstants.quarantineDir.appending(path: run.runID)
        try? FileManager.default.removeItem(at: root)
        OperationLog.append("[PURGED] quarantine run \(run.runID) (\(run.formattedSize))")
    }

    /// Permanently deletes every run older than `retention`. Returns bytes freed.
    @discardableResult
    public static func purgeExpired(retention: TimeInterval) -> UInt64 {
        let cutoff = Date().addingTimeInterval(-retention)
        var freed: UInt64 = 0
        for run in runs() where run.date < cutoff {
            freed += run.totalBytes
            purge(run: run)
        }
        return freed
    }
}
