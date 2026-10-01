import Foundation
import OSLog

/// Deletes, trashes, quarantines, or dry-runs a set of items. Every path goes
/// through `SafetyGuard` first. Every operation is appended to a log file.
///
/// Quarantine moves the item into
/// `~/Library/Application Support/CleanMyDev/Quarantine/<run-id>/` with a
/// manifest so `restore(run:)` can put it back. `QuarantineStore.purge` drops
/// runs older than the retention window and actually frees the space.
///
/// Adapted from Mac Sai's CleaningEngine (BSD-3-Clause).
public actor CleaningEngine {
    public enum Mode: String, Sendable, Codable {
        case dryRun, trash, quarantine, permanent
    }

    public struct Result: Sendable {
        public let runID: String
        public let mode: Mode
        public let removedCount: Int
        public let freedBytes: UInt64
        public let removedURLs: Set<URL>
        public let errors: [CleanError]
        public let skippedCount: Int

        public var formattedFreed: String { ByteFormatter.string(freedBytes) }
    }

    public struct CleanError: Sendable, Identifiable {
        public var id: String { path }
        public let path: String
        public let error: String
    }

    public struct Progress: Sendable, Equatable {
        public let totalItems: Int
        public let processedItems: Int
        public let removedSoFar: Int
        public let freedBytesSoFar: UInt64
        public var fraction: Double { totalItems > 0 ? Double(processedItems) / Double(totalItems) : 0 }
    }

    private let guardRails: SafetyGuard
    private let logger = Logger(subsystem: CMConstants.bundleIdentifier, category: "CleaningEngine")

    public init(guardRails: SafetyGuard) {
        self.guardRails = guardRails
    }

    public func clean(
        items: [FileItem],
        mode: Mode,
        label: String = "manual",
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async -> Result {
        let runID = Self.makeRunID()
        if items.count > CMConstants.maxTotalItemsPerCleanOperation {
            let msg = "Refusing \(items.count) items: above the \(CMConstants.maxTotalItemsPerCleanOperation) runaway cap."
            logger.error("\(msg, privacy: .public)")
            return Result(runID: runID, mode: mode, removedCount: 0, freedBytes: 0, removedURLs: [],
                          errors: [CleanError(path: "validation", error: msg)], skippedCount: items.count)
        }

        var removed = 0
        var freed: UInt64 = 0
        var removedURLs = Set<URL>()
        var errors: [CleanError] = []
        var skipped = 0
        var manifest = QuarantineManifest(runID: runID, date: Date(), label: label, mode: mode, entries: [])

        let quarantineRoot = CMConstants.quarantineDir.appending(path: runID)
        if mode == .quarantine {
            try? FileManager.default.createDirectory(at: quarantineRoot, withIntermediateDirectories: true)
        }

        appendLog("[RUN \(runID)] mode=\(mode.rawValue) label=\(label) items=\(items.count)")

        var start = 0
        var processed = 0
        while start < items.count {
            if Task.isCancelled { break }
            let end = min(start + CMConstants.cleanChunkSize, items.count)
            let chunk = Array(items[start..<end])
            start = end

            for item in chunk {
                if Task.isCancelled { break }
                do { try guardRails.validatePath(item.url) } catch {
                    skipped += 1
                    errors.append(CleanError(path: item.path, error: error.localizedDescription))
                    appendLog("[BLOCKED] \(item.path) — \(error.localizedDescription)")
                    continue
                }
                let realSize: UInt64 = item.isDirectory ? DirectorySizer.size(of: item.url).allocated : item.allocatedSize

                switch mode {
                case .dryRun:
                    removed += 1; freed += realSize; removedURLs.insert(item.url)
                    appendLog("[DRY-RUN] \(item.path) (\(ByteFormatter.string(realSize)))")

                case .trash:
                    do {
                        try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                        removed += 1; freed += realSize; removedURLs.insert(item.url)
                        appendLog("[TRASHED] \(item.path) (\(ByteFormatter.string(realSize)))")
                    } catch let e as NSError where Self.isBenignMissing(e) {
                        skipped += 1
                    } catch {
                        errors.append(CleanError(path: item.path, error: error.localizedDescription))
                        appendLog("[ERROR] \(item.path) — \(error.localizedDescription)")
                    }

                case .quarantine:
                    do {
                        let dest = try Self.quarantineDestination(for: item.url, in: quarantineRoot)
                        try FileManager.default.moveItem(at: item.url, to: dest)
                        manifest.entries.append(.init(original: item.path, stored: dest.path(percentEncoded: false), bytes: realSize))
                        removed += 1; freed += realSize; removedURLs.insert(item.url)
                        appendLog("[QUARANTINED] \(item.path) → \(dest.lastPathComponent) (\(ByteFormatter.string(realSize)))")
                    } catch let e as NSError where Self.isBenignMissing(e) {
                        skipped += 1
                    } catch {
                        errors.append(CleanError(path: item.path, error: error.localizedDescription))
                        appendLog("[ERROR] \(item.path) — \(error.localizedDescription)")
                    }

                case .permanent:
                    do {
                        try FileManager.default.removeItem(at: item.url)
                        removed += 1; freed += realSize; removedURLs.insert(item.url)
                        appendLog("[DELETED] \(item.path) (\(ByteFormatter.string(realSize)))")
                    } catch let e as NSError where Self.isBenignMissing(e) {
                        skipped += 1
                    } catch {
                        errors.append(CleanError(path: item.path, error: error.localizedDescription))
                        appendLog("[ERROR] \(item.path) — \(error.localizedDescription)")
                    }
                }
            }
            processed += chunk.count
            onProgress?(Progress(totalItems: items.count, processedItems: processed, removedSoFar: removed, freedBytesSoFar: freed))
            await Task.yield()
        }

        if mode == .quarantine {
            if manifest.entries.isEmpty {
                try? FileManager.default.removeItem(at: quarantineRoot)
            } else {
                QuarantineStore.write(manifest, to: quarantineRoot)
            }
        }

        appendLog("[DONE \(runID)] removed=\(removed) freed=\(ByteFormatter.string(freed)) errors=\(errors.count) skipped=\(skipped)")
        return Result(runID: runID, mode: mode, removedCount: removed, freedBytes: freed,
                      removedURLs: removedURLs, errors: errors, skippedCount: skipped)
    }

    // MARK: - Helpers

    private static func makeRunID() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date()) + "-" + String(UUID().uuidString.prefix(6))
    }

    /// Flattened, collision-free name inside the run folder that still hints at
    /// the origin: `Users_me_Library_Caches_pip__a1b2c3`.
    private static func quarantineDestination(for url: URL, in root: URL) throws -> URL {
        let flat = url.path(percentEncoded: false)
            .split(separator: "/").joined(separator: "_")
            .prefix(180)
        let name = "\(flat)__\(String(UUID().uuidString.prefix(6)))"
        return root.appending(path: String(name))
    }

    private static func isBenignMissing(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) { return true }
        return false
    }

    nonisolated private func appendLog(_ body: String) {
        OperationLog.append(body)
    }
}

/// Append-only text log of every clean operation.
public enum OperationLog {
    public static func append(_ body: String) {
        let fm = FileManager.default
        let dir = CMConstants.operationLogDir
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(body)\n"
        guard let data = line.data(using: .utf8) else { return }
        let file = CMConstants.operationLogFile
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }

    public static func tail(lines: Int = 200) -> [String] {
        guard let text = try? String(contentsOf: CMConstants.operationLogFile, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n").suffix(lines).map(String.init))
    }
}
