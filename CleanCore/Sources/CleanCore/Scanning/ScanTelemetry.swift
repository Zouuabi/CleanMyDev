import Foundation
import os

/// Live counters every scanner bumps so the UI can show real motion while a
/// scan runs: files visited, bytes measured, the path being looked at.
public final class ScanTelemetry: Sendable {
    public static let shared = ScanTelemetry()

    public struct Snapshot: Sendable, Equatable {
        public var filesVisited: Int
        public var bytesMeasured: UInt64
        public var currentPath: String
        public var currentModule: String
        public var itemsFound: Int
        public var bytesFound: UInt64
        public var startedAt: Date?
    }

    private let state = OSAllocatedUnfairLock(initialState: Snapshot(filesVisited: 0, bytesMeasured: 0, currentPath: "", currentModule: "", itemsFound: 0, bytesFound: 0, startedAt: nil))

    public func reset(module: String = "") {
        state.withLock { $0 = Snapshot(filesVisited: 0, bytesMeasured: 0, currentPath: "", currentModule: module, itemsFound: 0, bytesFound: 0, startedAt: Date()) }
    }

    public func setModule(_ name: String) { state.withLock { $0.currentModule = name } }

    /// Called from hot loops; keep it cheap. The path is only recorded every
    /// 64th call so the lock isn't contended on string copies.
    @inline(__always)
    public func visited(_ path: String? = nil, bytes: UInt64 = 0) {
        state.withLock {
            $0.filesVisited += 1
            $0.bytesMeasured += bytes
            if let path, $0.filesVisited & 63 == 0 { $0.currentPath = path }
        }
    }

    public func found(items: Int, bytes: UInt64) {
        state.withLock { $0.itemsFound += items; $0.bytesFound += bytes }
    }

    public var snapshot: Snapshot { state.withLock { $0 } }
}
