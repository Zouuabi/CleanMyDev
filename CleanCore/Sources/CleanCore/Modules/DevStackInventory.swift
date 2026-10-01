import Foundation
import AppKit

/// What's installed on this Mac for development, discovered from the places
/// package managers, version managers, and database engines put things. No
/// user path is hardcoded; only the tools' own conventions are.
public struct DevStackItem: Identifiable, Sendable, Hashable {
    public var id: String { "\(group.rawValue):\(path)" }
    public let group: Group
    public let name: String
    public let detail: String
    public let path: String
    public let bytes: UInt64
    public let modified: Date?
    public let status: Status
    public let removal: Removal
    public let hint: String?

    public enum Group: String, CaseIterable, Sendable {
        case databases, services, toolchains, globalTools, sdks, vms, packageManagers
        public var displayName: String {
            switch self {
            case .databases: "Databases"
            case .services: "Background services"
            case .toolchains: "Language runtimes"
            case .globalTools: "Globally installed tools"
            case .sdks: "SDKs & IDE toolchains"
            case .vms: "VM & container disks"
            case .packageManagers: "Package managers"
            }
        }
        public var systemImage: String {
            switch self {
            case .databases: "cylinder.split.1x2"
            case .services: "gearshape.2"
            case .toolchains: "chevron.left.forwardslash.chevron.right"
            case .globalTools: "terminal"
            case .sdks: "hammer"
            case .vms: "server.rack"
            case .packageManagers: "shippingbox"
            }
        }
    }

    public enum Status: String, Sendable { case running, stopped, installed, current, notDefault = "not default" }

    public enum Removal: Sendable, Hashable {
        /// Folder can go to quarantine like any other item.
        case quarantinePath
        /// Show this command; we never run it ourselves.
        case command(String)
        /// Data. Shown for awareness only.
        case never
    }

    public var formattedSize: String { ByteFormatter.string(bytes) }
}

public enum DevStackInventory {
    public static func collect() async -> [DevStackItem] {
        async let brew = brewItems()
        async let dbs = databaseItems()
        async let runtimes = runtimeItems()
        async let globals = globalToolItems()
        async let sdks = sdkItems()
        async let vms = vmItems()
        var all = await brew + dbs + runtimes + globals + sdks + vms
        SizeCache.shared.flush()
        var seen = Set<String>()
        all = all.filter { seen.insert($0.id).inserted }
        return all.sorted { ($0.group.rawValue, $1.bytes) < ($1.group.rawValue, $0.bytes) }
    }

    static let home = CMConstants.homePath
    static let brewPrefixes = ["/opt/homebrew", "/usr/local"]

    static func size(_ path: String) -> UInt64 { SizeCache.shared.size(of: URL(filePath: path)).allocated }
    static func mtime(_ path: String) -> Date? { try? URL(filePath: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    static func entries(_ path: String) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { !$0.hasPrefix(".") }.sorted() }

    // MARK: Homebrew: formulas, services, and the data dirs under var/

    static func brewItems() async -> [DevStackItem] {
        var items: [DevStackItem] = []
        let services = await brewServices()
        for prefix in brewPrefixes {
            let cellar = "\(prefix)/Cellar"
            for formula in entries(cellar) {
                let path = "\(cellar)/\(formula)"
                let versions = entries(path)
                let bytes = size(path)
                let isRuntime = ["node", "python@", "openjdk", "ruby", "go", "rust", "php", "perl", "deno", "bun", "dotnet", "swift"].contains { formula.hasPrefix($0) }
                let isDB = ["postgresql", "mongodb", "mysql", "mariadb", "redis", "sqlite", "memcached", "clickhouse", "cassandra"].contains { formula.hasPrefix($0) }
                let group: DevStackItem.Group = isDB ? .databases : isRuntime ? .toolchains : .packageManagers
                let svc = services[formula]
                items.append(DevStackItem(
                    group: group, name: formula,
                    detail: "Homebrew formula · \(versions.joined(separator: ", "))" + (svc.map { " · service \($0)" } ?? ""),
                    path: path, bytes: bytes, modified: mtime(path),
                    status: svc == "started" ? .running : (svc != nil ? .stopped : .installed),
                    removal: .command("brew uninstall \(formula)"),
                    hint: isDB && !formula.hasPrefix("sqlite") ? "Engine only. Its data lives under \(prefix)/var." : nil
                ))
            }
            // Data directories kept by brew-installed engines.
            let varDir = "\(prefix)/var"
            for entry in entries(varDir) {
                let lower = entry.lowercased()
                guard ["postgres", "mongodb", "mysql", "mariadb", "redis", "clickhouse", "neo4j", "elasticsearch", "opensearch", "influxdb", "rabbitmq", "kafka", "zookeeper"].contains(where: { lower.hasPrefix($0) }) else { continue }
                let path = "\(varDir)/\(entry)"
                let svcName = services.keys.first { entry.hasPrefix($0) }
                let state = svcName.flatMap { services[$0] }
                items.append(DevStackItem(
                    group: .databases, name: "\(entry) data",
                    detail: "Database files for the Homebrew \(entry) engine",
                    path: path, bytes: size(path), modified: mtime(path),
                    status: state == "started" ? .running : .stopped,
                    removal: .never,
                    hint: "Your actual databases. Dump before touching: pg_dumpall / mongodump."
                ))
            }
            for (name, state) in services where !items.contains(where: { $0.name == name }) {
                items.append(DevStackItem(group: .services, name: name, detail: "brew service", path: "\(prefix)/opt/\(name)", bytes: 0, modified: nil,
                                          status: state == "started" ? .running : .stopped, removal: .command("brew services stop \(name)"), hint: nil))
            }
        }
        return items
    }

    static func brewServices() async -> [String: String] {
        guard let brew = Shell.which("brew") else { return [:] }
        let out = await Shell.run(brew, ["services", "list"], timeout: 20).stdout
        var map: [String: String] = [:]
        for line in out.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2 { map[String(parts[0])] = String(parts[1]) }
        }
        return map
    }

    // MARK: Databases: apps, running engines, Docker containers

    static func databaseItems() async -> [DevStackItem] {
        var items: [DevStackItem] = []
        let apps: [(String, String, String)] = [
            ("Postgres.app", "/Applications/Postgres.app", "\(home)/Library/Application Support/Postgres"),
            ("MongoDB Compass", "/Applications/MongoDB Compass.app", "\(home)/.mongodb"),
            ("DBeaver", "/Applications/DBeaver.app", "\(home)/Library/DBeaverData"),
            ("TablePlus", "/Applications/TablePlus.app", "\(home)/Library/Application Support/com.tinyapp.TablePlus"),
            ("pgAdmin", "/Applications/pgAdmin 4.app", "\(home)/.pgadmin"),
            ("Redis Insight", "/Applications/Redis Insight.app", "\(home)/.redis-insight"),
        ]
        for (name, app, data) in apps where exists(app) {
            let dataExists = exists(data)
            items.append(DevStackItem(group: .databases, name: name, detail: dataExists ? "App · data in \(data.replacingOccurrences(of: home, with: "~"))" : "App",
                                      path: dataExists ? data : app, bytes: size(app) + (dataExists ? size(data) : 0), modified: mtime(app),
                                      status: .installed, removal: .never, hint: name == "Postgres.app" ? "Databases live in Application Support/Postgres." : nil))
        }
        // Running engines, wherever they were installed from.
        let ps = await Shell.run("/bin/ps", ["-axo", "pid=,comm=,args="]).stdout
        for line in ps.split(separator: "\n") {
            let text = String(line)
            let lower = text.lowercased()
            guard let engine = ["mongod", "postgres", "redis-server", "mysqld", "mariadbd", "clickhouse", "elasticsearch", "neo4j"].first(where: { lower.contains($0) }),
                  !lower.contains("grep"), !lower.contains("docker"), !lower.contains("com.docker") else { continue }
            let dataDir = Self.argValue(in: text, flags: ["-D", "--dbpath", "--datadir", "--dir"]) ?? "?"
            items.append(DevStackItem(group: .databases, name: "\(engine) (running)", detail: "pid \(text.split(separator: " ").first ?? "") · data \(dataDir)",
                                      path: dataDir, bytes: dataDir == "?" ? 0 : size(dataDir), modified: nil, status: .running, removal: .never, hint: nil))
        }
        // Docker containers that are database engines.
        let snap = await DockerService.shared.snapshot()
        if snap.available {
            let volSizes = Dictionary(uniqueKeysWithValues: snap.volumes.map { ($0.name, $0.sizeBytes) })
            for c in snap.containers {
                let img = c.image.lowercased()
                guard ["postgres", "mongo", "mysql", "mariadb", "redis", "clickhouse", "elasticsearch", "supabase/postgres", "neo4j"].contains(where: { img.contains($0) }) else { continue }
                let projectVolumes = snap.volumes.filter { $0.composeProject != nil && $0.composeProject == c.composeProject }
                let bytes = projectVolumes.reduce(0) { $0 + (volSizes[$1.name] ?? 0) }
                items.append(DevStackItem(group: .databases, name: c.name, detail: "Docker · \(c.image)" + (c.composeProject.map { " · compose \($0) · \(ByteFormatter.string(bytes)) in project volumes" } ?? ""),
                                          path: "docker://container/\(c.containerID)", bytes: bytes, modified: nil,
                                          status: c.isRunning ? .running : .stopped, removal: .never,
                                          hint: c.workingDir.map { "Belongs to \($0.replacingOccurrences(of: home, with: "~"))" }))
            }
        }
        return items
    }

    static func argValue(in text: String, flags: [String]) -> String? {
        let parts = text.split(separator: " ").map(String.init)
        for (i, p) in parts.enumerated() {
            for f in flags {
                if p == f, i + 1 < parts.count { return parts[i + 1] }
                if p.hasPrefix(f + "=") { return String(p.dropFirst(f.count + 1)) }
            }
        }
        return nil
    }

    // MARK: Version managers

    static func runtimeItems() async -> [DevStackItem] {
        var items: [DevStackItem] = []
        func versions(_ root: String, manager: String, defaultFile: String?, group: DevStackItem.Group = .toolchains) {
            guard exists(root) else { return }
            let def = defaultFile.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let list = entries(root)
            for v in list {
                let path = "\(root)/\(v)"
                let isDefault = def.map { v == $0 || v == "v\($0)" || $0.hasPrefix(v) } ?? (list.count == 1)
                items.append(DevStackItem(group: group, name: "\(manager) \(v)", detail: "\(manager) version",
                                          path: path, bytes: size(path), modified: mtime(path),
                                          status: isDefault ? .current : .notDefault,
                                          removal: .quarantinePath,
                                          hint: isDefault ? nil : "Not the default version. Old versions re-install in one command."))
            }
        }
        versions("\(home)/.nvm/versions/node", manager: "node", defaultFile: "\(home)/.nvm/alias/default")
        versions("\(home)/.pyenv/versions", manager: "python", defaultFile: "\(home)/.pyenv/version")
        versions("\(home)/.rustup/toolchains", manager: "rust", defaultFile: nil)
        versions("\(home)/sdk", manager: "go", defaultFile: nil)
        versions("\(home)/.rbenv/versions", manager: "ruby", defaultFile: "\(home)/.rbenv/version")
        versions("\(home)/.jenv/versions", manager: "java", defaultFile: nil)
        versions("\(home)/.sdkman/candidates/java", manager: "java", defaultFile: nil)
        versions("\(home)/.asdf/installs", manager: "asdf", defaultFile: nil)
        versions("\(home)/Library/Application Support/fnm/node-versions", manager: "node", defaultFile: nil)
        versions("\(home)/.volta/tools/image/node", manager: "node", defaultFile: nil)
        versions("\(home)/.local/share/mise/installs", manager: "mise", defaultFile: nil)
        for (name, path) in [("bun", "\(home)/.bun"), ("deno", "\(home)/.deno"), ("dotnet", "\(home)/.dotnet"), ("conda", "\(home)/miniconda3"), ("conda", "\(home)/anaconda3"), ("conda", "\(home)/miniforge3"), ("flutter", "\(home)/development/flutter"), ("flutter", "\(home)/flutter")] where exists(path) {
            items.append(DevStackItem(group: .toolchains, name: name, detail: path.replacingOccurrences(of: home, with: "~"), path: path, bytes: size(path), modified: mtime(path), status: .installed, removal: .quarantinePath, hint: nil))
        }
        return items
    }

    // MARK: Global tools

    static func globalToolItems() async -> [DevStackItem] {
        var items: [DevStackItem] = []
        var nodeRoots = entries("\(home)/.nvm/versions/node").map { "\(home)/.nvm/versions/node/\($0)/lib/node_modules" }
        for prefix in brewPrefixes { nodeRoots.append("\(prefix)/lib/node_modules") }
        nodeRoots.append("\(home)/.npm-global/lib/node_modules")
        for root in nodeRoots where exists(root) {
            for pkg in entries(root) where !["npm", "corepack"].contains(pkg) {
                if pkg.hasPrefix("@") {
                    for scoped in entries("\(root)/\(pkg)") { add(&items, "\(pkg)/\(scoped)", "\(root)/\(pkg)/\(scoped)", "npm global", "npm uninstall -g \(pkg)/\(scoped)") }
                } else {
                    add(&items, pkg, "\(root)/\(pkg)", "npm global", "npm uninstall -g \(pkg)")
                }
            }
        }
        for v in entries("\(home)/.local/pipx/venvs") { add(&items, v, "\(home)/.local/pipx/venvs/\(v)", "pipx", "pipx uninstall \(v)") }
        for v in entries("\(home)/.local/share/uv/tools") { add(&items, v, "\(home)/.local/share/uv/tools/\(v)", "uv tool", "uv tool uninstall \(v)") }
        for v in entries("\(home)/.bun/install/global/node_modules") where v != ".bin" { add(&items, v, "\(home)/.bun/install/global/node_modules/\(v)", "bun global", "bun remove -g \(v)") }
        for v in entries("\(home)/.cargo/bin") where !["cargo", "rustc", "rustup", "rustfmt", "clippy-driver", "cargo-clippy", "cargo-fmt", "rust-analyzer", "rust-gdb", "rust-lldb", "rustdoc", "cargo-miri", "rls"].contains(v) {
            add(&items, v, "\(home)/.cargo/bin/\(v)", "cargo install", "cargo uninstall \(v)")
        }
        for v in entries("\(home)/go/bin") { add(&items, v, "\(home)/go/bin/\(v)", "go install", nil) }
        for v in entries("\(home)/.local/bin") { add(&items, v, "\(home)/.local/bin/\(v)", "~/.local/bin", nil, sizeIt: false) }
        return items
    }

    static func add(_ items: inout [DevStackItem], _ name: String, _ path: String, _ source: String, _ cmd: String?, sizeIt: Bool = true) {
        let bytes = sizeIt ? size(path) : 0
        let m = mtime(path)
        let old = m.map { Date().timeIntervalSince($0) > 180 * 86_400 } ?? false
        items.append(DevStackItem(group: .globalTools, name: name, detail: source, path: path, bytes: bytes, modified: m,
                                  status: .installed, removal: cmd.map { .command($0) } ?? .quarantinePath,
                                  hint: old ? "Not updated for 6+ months" : nil))
    }

    // MARK: SDKs and VMs

    static func sdkItems() async -> [DevStackItem] {
        var items: [DevStackItem] = []
        for app in entries("/Applications") where app.hasPrefix("Xcode") && app.hasSuffix(".app") {
            let p = "/Applications/\(app)"
            items.append(DevStackItem(group: .sdks, name: app.replacingOccurrences(of: ".app", with: ""), detail: "Xcode", path: p, bytes: size(p), modified: mtime(p), status: .installed, removal: .never, hint: nil))
        }
        let known: [(String, String)] = [
            ("Android SDK", "\(home)/Library/Android/sdk"), ("Android Studio data", "\(home)/Library/Application Support/Google/AndroidStudio"),
            ("iOS DeviceSupport", "\(home)/Library/Developer/Xcode/iOS DeviceSupport"), ("Xcode Archives", "\(home)/Library/Developer/Xcode/Archives"),
            ("Simulator runtimes", "/Library/Developer/CoreSimulator/Volumes"), ("Simulator devices", "\(home)/Library/Developer/CoreSimulator/Devices"),
            ("Unity", "\(home)/Library/Unity"), ("JetBrains", "\(home)/Library/Application Support/JetBrains"), ("Google Cloud SDK", "\(home)/google-cloud-sdk"),
            ("AWS CLI data", "\(home)/.aws"), ("Firebase tools cache", "\(home)/.cache/firebase"), ("Gradle", "\(home)/.gradle"), ("Maven", "\(home)/.m2"),
            ("CocoaPods repos", "\(home)/.cocoapods"), ("Playwright browsers", "\(home)/Library/Caches/ms-playwright"), ("Hugging Face cache", "\(home)/.cache/huggingface"),
            ("Ollama models", "\(home)/.ollama"), ("LM Studio models", "\(home)/.lmstudio"),
        ]
        for (name, p) in known where exists(p) {
            let bytes = size(p)
            guard bytes > 1_000_000 else { continue }
            items.append(DevStackItem(group: .sdks, name: name, detail: p.replacingOccurrences(of: home, with: "~"), path: p, bytes: bytes, modified: mtime(p), status: .installed,
                                      removal: name.contains("AWS") ? .never : .quarantinePath, hint: nil))
        }
        return items
    }

    static func vmItems() async -> [DevStackItem] {
        var items: [DevStackItem] = []
        let known: [(String, String, String?)] = [
            ("colima VM disk", "\(home)/.colima/_lima/_disks", "Docker images and volumes live inside this disk. Prune with the Docker module; the file shrinks only when colima recreates it."),
            ("lima VMs", "\(home)/.lima", nil),
            ("Docker Desktop VM", "\(home)/Library/Containers/com.docker.docker/Data/vms", nil),
            ("OrbStack", "\(home)/.orbstack", nil),
            ("UTM VMs", "\(home)/Library/Containers/com.utmapp.UTM/Data/Documents", nil),
            ("Parallels VMs", "\(home)/Parallels", nil),
            ("VirtualBox VMs", "\(home)/VirtualBox VMs", nil),
            ("Claude Code VM bundles", "\(home)/Library/Application Support/Claude/vm_bundles", "Used by Claude desktop's sandboxed sessions."),
            ("BlueStacks data", "/Users/Shared/Library/Application Support/BlueStacks", "Android emulator images."),
            ("Multipass", "\(home)/Library/Application Support/multipassd", nil),
        ]
        for (name, p, hint) in known where exists(p) {
            items.append(DevStackItem(group: .vms, name: name, detail: p.replacingOccurrences(of: home, with: "~"), path: p, bytes: size(p), modified: mtime(p), status: .installed, removal: .never, hint: hint))
        }
        return items
    }
}
