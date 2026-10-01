import Foundation
import Darwin

/// Walks the user's scan roots and finds project folders by marker files.
/// Never descends into artifact directories, hidden folders, `Library`, or
/// another project's subtree (nested projects inside a monorepo are still
/// found one level down, which is enough for workspaces).
public struct ProjectDetector: Sendable {
    public var maxDepth: Int
    public var skipNames: Set<String>

    public init(maxDepth: Int = 7, skipNames: Set<String> = ProjectDetector.defaultSkipNames) {
        self.maxDepth = maxDepth
        self.skipNames = skipNames
    }

    public static let defaultSkipNames: Set<String> = [
        "Library", "Applications", "Pictures", "Music", "Movies", "Public",
        "node_modules", "Pods", ".git", "venv", ".venv", "target", "vendor",
        "DerivedData", "build", "dist", ".build", "__pycache__", "site-packages",
    ]

    /// Bundle-style folders are never projects and never contain user projects.
    static let bundleSuffixes = [".xcodeproj", ".xcworkspace", ".app", ".framework", ".bundle", ".playground", ".xcassets", ".photoslibrary"]

    /// Tool-managed trees under the home folder that look like projects but aren't.
    static let skipPaths: [String] = {
        let home = CMConstants.homePath
        return ["\(home)/go/pkg", "\(home)/Library", "\(home)/.Trash"]
    }()

    static func shouldSkip(name: String, detector: ProjectDetector) -> Bool {
        name.hasPrefix(".") || detector.skipNames.contains(name) || bundleSuffixes.contains { name.hasSuffix($0) }
    }

    /// Pure: which kinds match a folder given its immediate entry names.
    public static func matchKinds(forEntries entries: Set<String>) -> [ProjectKind] {
        ProjectKind.all.filter { kind in
            kind.markers.contains { marker in
                switch marker {
                case .file(let f), .directory(let f): entries.contains(f)
                case .suffix(let s): entries.contains { $0.hasSuffix(s) }
                }
            }
        }
    }

    struct Candidate: Sendable {
        let root: URL; let kinds: [ProjectKind]; let entries: Set<String>
        var isRepo: Bool { entries.contains(ProjectKind.repoMarker) }
    }

    public func discover(roots: [URL], neverTouch: [String] = []) async -> [Project] {
        var candidates: [Candidate] = []
        var seen = Set<String>()
        for root in roots {
            for c in Self.walk(root, depth: 0, detector: self, neverTouch: neverTouch)
            where seen.insert(c.root.path(percentEncoded: false)).inserted {
                candidates.append(c)
            }
        }
        // Sizing artifact dirs is the slow part; do it with bounded parallelism.
        let projects: [Project] = await withTaskGroup(of: Project?.self) { group in
            var out: [Project] = []
            var iterator = candidates.makeIterator()
            let width = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
            for _ in 0..<width {
                if let c = iterator.next() { group.addTask { Self.makeProject(root: c.root, kinds: c.kinds, entries: c.entries) } }
            }
            for await p in group {
                if let p { out.append(p) }
                if let c = iterator.next() { group.addTask { Self.makeProject(root: c.root, kinds: c.kinds, entries: c.entries) } }
            }
            return out
        }
        // Workspace sub-packages with nothing of their own to clean and no
        // repo of their own are noise: a monorepo is one project.
        let repoRoots = Set(candidates.filter(\.isRepo).map { $0.root.path(percentEncoded: false) })
        let allRoots = candidates.map { $0.root.path(percentEncoded: false) }
        let kept = projects.filter { p in
            if p.totalArtifactBytes >= 1_000_000 || repoRoots.contains(p.path) { return true }
            let nested = allRoots.contains { $0 != p.path && PathExclusion.isInside(p.path, root: $0) }
            return !nested
        }
        return kept.sorted { $0.totalArtifactBytes > $1.totalArtifactBytes }
    }

    private static func walk(_ dir: URL, depth: Int, detector: ProjectDetector, neverTouch: [String]) -> [Candidate] {
        guard depth <= detector.maxDepth else { return [] }
        let path = dir.path(percentEncoded: false)
        if PathExclusion.isExcluded(path: path, by: neverTouch) || PathExclusion.isExcluded(path: path, by: skipPaths) { return [] }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        let entrySet = Set(entries)
        ScanTelemetry.shared.visited(path)

        let kinds = matchKinds(forEntries: entrySet)
        let isRepo = entrySet.contains(ProjectKind.repoMarker)

        var found: [Candidate] = []
        if !kinds.isEmpty || isRepo {
            found.append(Candidate(root: dir, kinds: kinds, entries: entrySet))
        }
        // Keep walking below a project too: workspaces and "misc" folders nest
        // real projects several levels down. Artifact dirs are never entered.
        let artifactNames = Set(kinds.flatMap(\.artifactDirs))
        for name in entries where !shouldSkip(name: name, detector: detector) && !artifactNames.contains(name) {
            let child = dir.appending(path: name)
            guard Self.isDirectory(child) else { continue }
            found.append(contentsOf: walk(child, depth: depth + 1, detector: detector, neverTouch: neverTouch))
        }
        return found
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var st = stat()
        guard lstat(url.path(percentEncoded: false), &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFDIR
    }

    static func makeProject(root: URL, kinds: [ProjectKind], entries: Set<String>) -> Project? {
        var artifacts: [Project.Artifact] = []
        var seenArtifacts = Set<String>()
        for kind in kinds {
            for rel in kind.dependencyDirs where seenArtifacts.insert(rel).inserted {
                let url = root.appending(path: rel)
                guard isDirectory(url) else { continue }
                let bytes = SizeCache.shared.size(of: url).allocated
                guard bytes > 0 else { continue }
                artifacts.append(.init(url: url, relativePath: rel, isDependency: true, bytes: bytes, kindName: kind.name))
            }
            for rel in kind.buildDirs where seenArtifacts.insert(rel).inserted {
                let url = root.appending(path: rel)
                guard isDirectory(url) else { continue }
                let bytes = SizeCache.shared.size(of: url).allocated
                guard bytes > 0 else { continue }
                artifacts.append(.init(url: url, relativePath: rel, isDependency: false, bytes: bytes, kindName: kind.name))
            }
        }

        let git = GitProbe.probe(root)
        let sourceMtime = newestSourceModification(root: root, entries: entries, skipping: Set(artifacts.map(\.relativePath)))
        let folderMtime = (try? root.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        var best: (Date, String)? = nil
        func consider(_ d: Date?, _ label: String) {
            guard let d else { return }
            if best == nil || d > best!.0 { best = (d, label) }
        }
        consider(git?.lastCommit, "Last commit")
        consider(sourceMtime, "Files changed")
        consider(folderMtime, "Folder modified")

        return Project(
            root: root,
            name: root.lastPathComponent,
            kinds: kinds,
            gitRemote: git?.remote,
            lastActivity: best?.0,
            lastCommit: git?.lastCommit,
            activitySource: best?.1 ?? "No activity",
            artifacts: artifacts.sorted { $0.bytes > $1.bytes }
        )
    }

    /// Newest mtime among top-level entries and one level of source dirs.
    /// Cheap and good enough: editing anything bumps a nearby directory.
    private static func newestSourceModification(root: URL, entries: Set<String>, skipping: Set<String>) -> Date? {
        var newest: Date? = nil
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        for name in entries where !skipping.contains(name) && name != ".git" {
            let url = root.appending(path: name)
            guard let v = try? url.resourceValues(forKeys: keys) else { continue }
            if let d = v.contentModificationDate, newest == nil || d > newest! { newest = d }
            if v.isDirectory == true, !name.hasPrefix("."),
               let sub = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for s in sub.prefix(200) {
                    if let d = try? s.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       newest == nil || d > newest! { newest = d }
                }
            }
        }
        return newest
    }
}

/// Reads git metadata without spawning git: HEAD's commit date comes from the
/// reflog / packed refs mtime, the remote from `.git/config`.
public enum GitProbe {
    public struct Info: Sendable {
        public let remote: String?
        public let lastCommit: Date?
    }

    public static func probe(_ root: URL) -> Info? {
        let gitDir = root.appending(path: ".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDir.path(percentEncoded: false), isDirectory: &isDir) else { return nil }
        let dir: URL
        if isDir.boolValue {
            dir = gitDir
        } else if let text = try? String(contentsOf: gitDir, encoding: .utf8),
                  let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) {
            // Worktree: "gitdir: /path/to/.git/worktrees/x"
            let rel = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            dir = URL(filePath: rel, relativeTo: root).standardizedFileURL
        } else {
            return nil
        }

        let remote = parseRemote(dir.appending(path: "config"))
            ?? parseRemote(dir.deletingLastPathComponent().deletingLastPathComponent().appending(path: "config"))
        let commit = newest([
            dir.appending(path: "logs/HEAD"),
            dir.appending(path: "HEAD"),
            dir.appending(path: "index"),
            dir.appending(path: "FETCH_HEAD"),
        ])
        return Info(remote: remote, lastCommit: commit)
    }

    static func parseRemote(_ configURL: URL) -> String? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        var inOrigin = false
        var firstRemoteURL: String? = nil
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[remote ") {
                inOrigin = line.contains("\"origin\"")
                continue
            }
            if line.hasPrefix("[") { inOrigin = false; continue }
            if line.hasPrefix("url ="), let eq = line.firstIndex(of: "=") {
                let url = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if inOrigin { return normalize(url) }
                if firstRemoteURL == nil { firstRemoteURL = normalize(url) }
            }
        }
        return firstRemoteURL
    }

    /// `git@github.com:a/b.git` and `https://github.com/a/b` become `github.com/a/b`.
    static func normalize(_ url: String) -> String {
        var s = url
        if s.hasPrefix("git@"), let colon = s.firstIndex(of: ":") {
            let host = s[s.index(s.startIndex, offsetBy: 4)..<colon]
            let path = s[s.index(after: colon)...]
            s = host + "/" + path
        }
        for prefix in ["https://", "http://", "ssh://git@", "ssh://", "git://"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        return s.lowercased()
    }

    private static func newest(_ urls: [URL]) -> Date? {
        urls.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }
}
