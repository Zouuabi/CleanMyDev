import Foundation
import Darwin

/// Drops items this process could not delete anyway (root-owned children of
/// writable parents, UF_DATAVAULT dirs under ~/Library/Caches/com.apple.*)
/// so they never reach the UI as rows that would just error at clean time.
///
/// Adapted from Mac Sai's CleanFilter (BSD-3-Clause).
public enum CleanFilter {
    public static func isCleanableByCurrentProcess(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let parent = (path as NSString).deletingLastPathComponent
        guard access(parent, W_OK) == 0 else { return false }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
        if isDir.boolValue { guard access(path, W_OK) == 0 else { return false } }
        return true
    }

    public static func isActionable(_ url: URL, neverTouch: [String]) -> Bool {
        isCleanableByCurrentProcess(url) && !PathExclusion.isExcluded(url, by: neverTouch)
    }
}
