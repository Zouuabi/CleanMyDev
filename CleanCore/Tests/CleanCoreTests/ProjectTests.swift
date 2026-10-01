import XCTest
@testable import CleanCore

final class ProjectKindTests: XCTestCase {
    func testNodeProjectDetectedByPackageJSON() {
        let kinds = ProjectDetector.matchKinds(forEntries: ["package.json", "src", "node_modules"])
        XCTAssertEqual(kinds.map(\.name), ["Node"])
    }

    func testXcodeDetectedBySuffix() {
        let kinds = ProjectDetector.matchKinds(forEntries: ["CleanMyDev.xcodeproj", "CleanMyDev"])
        XCTAssertEqual(kinds.map(\.name), ["Xcode"])
    }

    func testMultipleKinds() {
        let kinds = ProjectDetector.matchKinds(forEntries: ["package.json", "pyproject.toml", "docker-compose.yml"])
        XCTAssertEqual(Set(kinds.map(\.name)), ["Node", "Python", "Docker Compose"])
    }

    func testPlainFolderIsNotAProject() {
        XCTAssertTrue(ProjectDetector.matchKinds(forEntries: ["notes.md", "photo.jpg"]).isEmpty)
    }
}

final class GitProbeTests: XCTestCase {
    func testNormalizeSSHAndHTTPSAgree() {
        XCTAssertEqual(GitProbe.normalize("git@github.com:Example/CleanMyDev.git"), "github.com/example/cleanmydev")
        XCTAssertEqual(GitProbe.normalize("https://github.com/Example/CleanMyDev"), "github.com/example/cleanmydev")
        XCTAssertEqual(GitProbe.normalize("ssh://git@github.com/a/b.git"), "github.com/a/b")
    }
}

final class ProjectClassifierTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func project(daysAgo: Int?, signals: Project.Signals = .init(), remote: String? = nil) -> Project {
        var p = Project(
            root: URL(filePath: "/tmp/p"), name: "p", kinds: [], gitRemote: remote,
            lastActivity: daysAgo.map { now.addingTimeInterval(-Double($0) * 86_400) },
            lastCommit: nil, activitySource: "Last commit", artifacts: []
        )
        p.signals = signals
        return p
    }

    func testRecentCommitIsActive() {
        let d = ProjectClassifier.decide(project(daysAgo: 3), registry: .init(), settings: .init(), now: now)
        XCTAssertEqual(d.status, .active)
        XCTAssertFalse(d.status.allowsCleaning)
    }

    func testBetweenThresholdsIsIdle() {
        let d = ProjectClassifier.decide(project(daysAgo: 20), registry: .init(), settings: .init(), now: now)
        XCTAssertEqual(d.status, .idle)
        XCTAssertFalse(d.status.allowsCleaning)
    }

    func testOldProjectIsDormant() {
        let d = ProjectClassifier.decide(project(daysAgo: 90), registry: .init(), settings: .init(), now: now)
        XCTAssertEqual(d.status, .dormant)
        XCTAssertTrue(d.status.allowsCleaning)
        XCTAssertEqual(d.reason, "Untouched for 90 days")
    }

    func testRunningContainerBeatsAge() {
        var s = Project.Signals(); s.runningContainers = 2
        let d = ProjectClassifier.decide(project(daysAgo: 400, signals: s), registry: .init(), settings: .init(), now: now)
        XCTAssertEqual(d.status, .active)
        XCTAssertEqual(d.reason, "2 Docker containers running")
    }

    func testPinBeatsEverything() {
        var s = Project.Signals(); s.runningContainers = 0
        let p = project(daysAgo: 400, signals: s)
        var reg = ProjectRegistry()
        reg.pin(p, until: now.addingTimeInterval(5 * 86_400))
        let d = ProjectClassifier.decide(p, registry: reg, settings: .init(), now: now)
        XCTAssertEqual(d.status, .pinned)
        XCTAssertTrue(d.isOverride)
        XCTAssertFalse(d.status.allowsCleaning)
    }

    func testExpiredPinFallsBackToAutomatic() {
        let p = project(daysAgo: 400)
        var reg = ProjectRegistry()
        reg.pin(p, until: now.addingTimeInterval(-1))
        let d = ProjectClassifier.decide(p, registry: reg, settings: .init(), now: now)
        XCTAssertEqual(d.status, .dormant)
    }

    func testCleanableOverrideBeatsRecentActivity() {
        let p = project(daysAgo: 1)
        var reg = ProjectRegistry()
        reg.markCleanable(p)
        let d = ProjectClassifier.decide(p, registry: reg, settings: .init(), now: now)
        XCTAssertEqual(d.status, .cleanable)
        XCTAssertTrue(d.status.allowsCleaning)
    }

    func testPinSurvivesRename() {
        let a = project(daysAgo: 400, remote: "github.com/me/app")
        var reg = ProjectRegistry()
        reg.pin(a)
        let moved = Project(root: URL(filePath: "/elsewhere/renamed"), name: "renamed", kinds: [],
                            gitRemote: "github.com/me/app", lastActivity: nil, lastCommit: nil,
                            activitySource: "", artifacts: [])
        XCTAssertEqual(ProjectClassifier.decide(moved, registry: reg, settings: .init(), now: now).status, .pinned)
    }

    func testThresholdsComeFromSettings() {
        var s = CleanSettings()
        s.activeDays = 2
        s.dormantDays = 5
        XCTAssertEqual(ProjectClassifier.decide(project(daysAgo: 3), registry: .init(), settings: s, now: now).status, .idle)
        XCTAssertEqual(ProjectClassifier.decide(project(daysAgo: 6), registry: .init(), settings: s, now: now).status, .dormant)
    }
}

final class SafetyGuardTests: XCTestCase {
    func testRefusesSystemPaths() {
        let g = SafetyGuard()
        XCTAssertThrowsError(try g.validatePath(URL(filePath: "/System/Library/Foo")))
        XCTAssertThrowsError(try g.validatePath(URL(filePath: "/usr/bin/ls")))
        XCTAssertThrowsError(try g.validatePath(URL(filePath: "/private/var/db/x")))
    }

    func testRefusesNeverTouchAndActiveProjects() {
        let g = SafetyGuard(neverTouch: ["/Users/x/.ssh"], protectedProjectRoots: ["/Users/x/dev/myapp"])
        XCTAssertThrowsError(try g.validatePath(URL(filePath: "/Users/x/.ssh/id_ed25519")))
        XCTAssertThrowsError(try g.validatePath(URL(filePath: "/Users/x/dev/myapp/node_modules")))
        XCTAssertNoThrow(try g.validatePath(URL(filePath: "/Users/x/dev/myapp-old/node_modules")))
    }

    func testFirmlinkCanonicalization() {
        XCTAssertEqual(SafetyGuard.canonicalizeFirmlinks("/private/var/log/x"), "/var/log/x")
        XCTAssertEqual(SafetyGuard.canonicalizeFirmlinks("/private/var/db"), "/var/db")
        XCTAssertEqual(SafetyGuard.canonicalizeFirmlinks("/private/etc"), "/etc")
    }

    func testPathExclusionBoundary() {
        XCTAssertTrue(PathExclusion.isInside("/a/b/c", root: "/a/b"))
        XCTAssertFalse(PathExclusion.isInside("/a/bc", root: "/a/b"))
        XCTAssertEqual(PathExclusion.normalized(["/a/b", "/a", "/a/b/c", "/z"]), ["/a", "/z"])
    }
}

final class SettingsTests: XCTestCase {
    func testAutoCleanNeverEscalatesBeyondEligible() {
        var s = CleanSettings()
        s.autoCleanCategories = [.userCaches, .largeFiles, .projectDependencies]
        XCTAssertEqual(s.effectiveAutoCleanCategories, [.userCaches])
    }

    func testRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cmd-settings-\(UUID().uuidString).json")
        var s = CleanSettings()
        s.activeDays = 3
        s.neverTouch = ["/x"]
        try s.save(to: url)
        XCTAssertEqual(CleanSettings.load(from: url), s)
    }
}

final class QuarantineTests: XCTestCase {
    func testQuarantineRoundTrip() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "cmd-q-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let victim = base.appending(path: "cache-dir")
        try fm.createDirectory(at: victim, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4096).write(to: victim.appending(path: "blob"))

        let engine = CleaningEngine(guardRails: SafetyGuard())
        let item = FileItem(url: victim, size: 4096, isDirectory: true)
        let result = await engine.clean(items: [item], mode: .quarantine, label: "test")
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertFalse(fm.fileExists(atPath: victim.path(percentEncoded: false)))

        let run = QuarantineStore.runs().first { $0.runID == result.runID }
        XCTAssertNotNil(run)
        XCTAssertEqual(run?.entries.count, 1)

        let failed = QuarantineStore.restore(run: run!)
        XCTAssertTrue(failed.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: victim.appending(path: "blob").path(percentEncoded: false)))
        XCTAssertNil(QuarantineStore.runs().first { $0.runID == result.runID })
        try? fm.removeItem(at: base)
    }

    func testDryRunTouchesNothing() async throws {
        let fm = FileManager.default
        let f = fm.temporaryDirectory.appending(path: "cmd-dry-\(UUID().uuidString)")
        try Data([1, 2, 3]).write(to: f)
        let engine = CleaningEngine(guardRails: SafetyGuard())
        let r = await engine.clean(items: [FileItem(url: f, size: 3, isDirectory: false)], mode: .dryRun)
        XCTAssertEqual(r.removedCount, 1)
        XCTAssertTrue(fm.fileExists(atPath: f.path(percentEncoded: false)))
        try? fm.removeItem(at: f)
    }
}
