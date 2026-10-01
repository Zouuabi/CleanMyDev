import Foundation

/// Marker-file to artifact-directory table. A folder is a project of a given
/// kind when it contains the marker; the artifact dirs are what becomes
/// deletable once the project is dormant.
///
/// Table ported from kondo (MIT, © Trent Billington) with additions for the
/// JS and Python ecosystems common on this machine.
public struct ProjectKind: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let symbol: String
    /// Any of these present in the folder makes it this kind of project.
    public let markers: [Marker]
    /// Relative paths that are downloaded dependencies (re-installable).
    public let dependencyDirs: [String]
    /// Relative paths that are build output (re-buildable).
    public let buildDirs: [String]

    public enum Marker: Sendable, Hashable {
        case file(String)
        case suffix(String)
        case directory(String)
    }

    public var artifactDirs: [String] { dependencyDirs + buildDirs }

    public static let all: [ProjectKind] = [
        ProjectKind(name: "Node", symbol: "hexagon.fill",
                    markers: [.file("package.json")],
                    dependencyDirs: ["node_modules"],
                    buildDirs: [".next", ".nuxt", ".svelte-kit", ".angular", ".turbo", ".parcel-cache", ".cache", "dist", "build", "out", "coverage", ".vite", ".expo", ".metro", "storybook-static"]),
        ProjectKind(name: "React Native", symbol: "iphone.and.arrow.forward",
                    markers: [.file("app.json"), .file("metro.config.js")],
                    dependencyDirs: ["node_modules", "ios/Pods"],
                    buildDirs: ["android/build", "android/.gradle", "android/app/build", "ios/build", "ios/DerivedData", ".expo", ".metro"]),
        ProjectKind(name: "Python", symbol: "chevron.left.forwardslash.chevron.right",
                    markers: [.file("pyproject.toml"), .file("requirements.txt"), .file("setup.py"), .file("Pipfile"), .file("manage.py")],
                    dependencyDirs: [".venv", "venv", "env", ".env", "__pypackages__", ".pixi", ".tox", ".nox"],
                    buildDirs: ["__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", "build", "dist", ".eggs", "htmlcov", ".ipynb_checkpoints"]),
        ProjectKind(name: "Rust", symbol: "gearshape.2.fill",
                    markers: [.file("Cargo.toml")],
                    dependencyDirs: [],
                    buildDirs: ["target", ".xwin-cache"]),
        ProjectKind(name: "Go", symbol: "arrow.right.circle",
                    markers: [.file("go.mod")],
                    dependencyDirs: ["vendor"],
                    buildDirs: ["bin", "dist"]),
        ProjectKind(name: "Swift Package", symbol: "swift",
                    markers: [.file("Package.swift")],
                    dependencyDirs: [],
                    buildDirs: [".build", ".swiftpm"]),
        ProjectKind(name: "Xcode", symbol: "hammer.fill",
                    markers: [.suffix(".xcodeproj"), .suffix(".xcworkspace")],
                    dependencyDirs: ["Pods", "Carthage/Build"],
                    buildDirs: ["build", "DerivedData"]),
        ProjectKind(name: "CocoaPods", symbol: "shippingbox",
                    markers: [.file("Podfile")],
                    dependencyDirs: ["Pods"],
                    buildDirs: []),
        ProjectKind(name: "Flutter", symbol: "paperplane.fill",
                    markers: [.file("pubspec.yaml")],
                    dependencyDirs: [".dart_tool", ".pub-cache"],
                    buildDirs: ["build", "linux/flutter/ephemeral", "windows/flutter/ephemeral", "macos/Flutter/ephemeral", "ios/Flutter/ephemeral"]),
        ProjectKind(name: "Gradle", symbol: "wrench.fill",
                    markers: [.file("build.gradle"), .file("build.gradle.kts"), .file("settings.gradle"), .file("settings.gradle.kts")],
                    dependencyDirs: [".gradle"],
                    buildDirs: ["build", "app/build", ".kotlin"]),
        ProjectKind(name: "Maven", symbol: "m.circle",
                    markers: [.file("pom.xml")],
                    dependencyDirs: [],
                    buildDirs: ["target"]),
        ProjectKind(name: ".NET", symbol: "number",
                    markers: [.suffix(".csproj"), .suffix(".fsproj"), .suffix(".sln")],
                    dependencyDirs: [],
                    buildDirs: ["bin", "obj"]),
        ProjectKind(name: "PHP", symbol: "p.circle",
                    markers: [.file("composer.json")],
                    dependencyDirs: ["vendor"],
                    buildDirs: []),
        ProjectKind(name: "Ruby", symbol: "diamond.fill",
                    markers: [.file("Gemfile")],
                    dependencyDirs: ["vendor/bundle", ".bundle"],
                    buildDirs: ["tmp/cache"]),
        ProjectKind(name: "Elixir", symbol: "drop.fill",
                    markers: [.file("mix.exs")],
                    dependencyDirs: ["deps"],
                    buildDirs: ["_build", ".elixir_ls"]),
        ProjectKind(name: "Haskell", symbol: "lambda",
                    markers: [.file("stack.yaml"), .file("cabal.project")],
                    dependencyDirs: [],
                    buildDirs: [".stack-work", "dist-newstyle"]),
        ProjectKind(name: "Zig", symbol: "z.circle",
                    markers: [.file("build.zig")],
                    dependencyDirs: [],
                    buildDirs: ["zig-cache", ".zig-cache", "zig-out"]),
        ProjectKind(name: "CMake", symbol: "c.circle",
                    markers: [.file("CMakeLists.txt")],
                    dependencyDirs: [],
                    buildDirs: ["build", "cmake-build-debug", "cmake-build-release"]),
        ProjectKind(name: "Terraform", symbol: "cloud.fill",
                    markers: [.file(".terraform.lock.hcl")],
                    dependencyDirs: [".terraform"],
                    buildDirs: []),
        ProjectKind(name: "Unity", symbol: "cube.fill",
                    markers: [.file("Assembly-CSharp.csproj"), .directory("ProjectSettings")],
                    dependencyDirs: [],
                    buildDirs: ["Library", "Temp", "Obj", "Logs", "MemoryCaptures", "Build", "Builds"]),
        ProjectKind(name: "Godot", symbol: "gamecontroller.fill",
                    markers: [.file("project.godot")],
                    dependencyDirs: [],
                    buildDirs: [".godot"]),
        ProjectKind(name: "Docker Compose", symbol: "shippingbox.fill",
                    markers: [.file("docker-compose.yml"), .file("docker-compose.yaml"), .file("compose.yml"), .file("compose.yaml")],
                    dependencyDirs: [],
                    buildDirs: []),
    ]

    /// Names that identify a folder as a project container even without a kind
    /// (git repo). Used so a bare repo still gets activity tracking.
    public static let repoMarker = ".git"
}
