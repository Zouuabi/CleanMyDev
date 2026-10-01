import Foundation

/// Validates that a deletion is safe. Pure (no FileManager beyond symlink
/// resolution) so it can be unit-tested exhaustively.
///
/// Adapted from Mac Sai's SafetyGuard (BSD-3-Clause).
public struct SafetyGuard: Sendable {
    public enum SafetyError: Error, LocalizedError, Equatable {
        case protectedPath(String)
        case tooManyFiles(Int)
        case symlinkTarget(String)
        case sipProtected(String)
        case invalidPath(String)
        case userNeverTouch(String)
        case activeProject(String)

        public var errorDescription: String? {
            switch self {
            case .protectedPath(let p): "Protected system path: \(p)"
            case .tooManyFiles(let n): "Operation exceeds the \(CMConstants.maxFilesPerOperation)-file safety cap (attempted \(n))"
            case .symlinkTarget(let p): "Path resolves through a symlink to an unexpected location: \(p)"
            case .sipProtected(let p): "Path is protected by System Integrity Protection: \(p)"
            case .invalidPath(let p): "Invalid path: \(p)"
            case .userNeverTouch(let p): "Path is inside a folder you marked never-touch: \(p)"
            case .activeProject(let p): "Path belongs to an active or pinned project: \(p)"
            }
        }
    }

    public let neverTouch: [String]
    public let protectedProjectRoots: [String]

    public init(neverTouch: [String] = [], protectedProjectRoots: [String] = []) {
        self.neverTouch = neverTouch
        self.protectedProjectRoots = protectedProjectRoots
    }

    public func validateDeletion(paths: [URL]) throws {
        if paths.count > CMConstants.maxFilesPerOperation {
            throw SafetyError.tooManyFiles(paths.count)
        }
        for path in paths { try validatePath(path) }
    }

    public func validatePath(_ url: URL) throws {
        let original = url.path(percentEncoded: false)
        if original.isEmpty { throw SafetyError.invalidPath("(empty)") }
        if original.contains("\0") { throw SafetyError.invalidPath(original) }

        let resolved = url.resolvingSymlinksInPath().path(percentEncoded: false)
        let originalCanonical = Self.canonicalizeFirmlinks(original)
        let resolvedCanonical = Self.canonicalizeFirmlinks(resolved)

        if resolvedCanonical == "/System" || resolvedCanonical.hasPrefix("/System/") {
            throw SafetyError.sipProtected(resolved)
        }
        for protected in Self.canonicalProtectedPaths
        where resolvedCanonical == protected || resolvedCanonical.hasPrefix(protected + "/") {
            throw SafetyError.protectedPath(resolved)
        }
        if PathExclusion.isExcluded(path: resolvedCanonical, by: neverTouch)
            || PathExclusion.isExcluded(path: originalCanonical, by: neverTouch) {
            throw SafetyError.userNeverTouch(resolved)
        }
        if PathExclusion.isExcluded(path: resolvedCanonical, by: protectedProjectRoots)
            || PathExclusion.isExcluded(path: originalCanonical, by: protectedProjectRoots) {
            throw SafetyError.activeProject(resolved)
        }
        if originalCanonical != resolvedCanonical {
            let a = originalCanonical.components(separatedBy: "/").prefix(3)
            let b = resolvedCanonical.components(separatedBy: "/").prefix(3)
            if a != b { throw SafetyError.symlinkTarget(resolved) }
        }
    }

    private static let canonicalProtectedPaths: Set<String> =
        Set(CMConstants.protectedPaths.map(SafetyGuard.canonicalizeFirmlinks))

    /// `/private/var/x` and `/var/x` are the same place; compare them as one.
    public static func canonicalizeFirmlinks(_ path: String) -> String {
        for firmlink in ["var", "tmp", "etc"] {
            let privatePrefix = "/private/\(firmlink)"
            if path == privatePrefix { return "/\(firmlink)" }
            if path.hasPrefix(privatePrefix + "/") { return "/\(firmlink)" + path.dropFirst(privatePrefix.count) }
        }
        return path
    }

    public func isProtectedApp(_ bundleID: String) -> Bool {
        CMConstants.protectedApps.contains(bundleID)
    }
}

/// Path-prefix matching with a `/` boundary. Pure.
public enum PathExclusion {
    public static func isInside(_ path: String, root: String) -> Bool {
        let p = SafetyGuard.canonicalizeFirmlinks(path)
        let r = SafetyGuard.canonicalizeFirmlinks(root)
        if p == r { return true }
        let prefix = r.hasSuffix("/") ? r : r + "/"
        return p.hasPrefix(prefix)
    }

    public static func isExcluded(path: String, by roots: [String]) -> Bool {
        guard !roots.isEmpty else { return false }
        return roots.contains { isInside(path, root: $0) }
    }

    public static func isExcluded(_ url: URL, by roots: [String]) -> Bool {
        isExcluded(path: url.path(percentEncoded: false), by: roots)
    }

    /// Deduped, sorted, descendants dropped when an ancestor is present.
    public static func normalized(_ paths: [String]) -> [String] {
        let unique = Array(Set(paths.map {
            SafetyGuard.canonicalizeFirmlinks($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { !$0.isEmpty })).sorted()
        return unique.filter { path in
            !unique.contains { other in other != path && isInside(path, root: other) }
        }
    }
}
