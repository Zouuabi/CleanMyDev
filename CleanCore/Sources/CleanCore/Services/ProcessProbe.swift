import Foundation

/// Live signals that a project is in use: processes whose working directory
/// is inside it, and Docker containers started from it.
public struct ProcessProbe: Sendable {
    public struct Snapshot: Sendable {
        /// (command name, cwd) for every process we could read.
        public let processes: [(command: String, cwd: String)]
        /// compose working_dir → running container count.
        public let containersByWorkingDir: [String: Int]

        public func signals(for root: URL) -> Project.Signals {
            var s = Project.Signals()
            let rootPath = root.path(percentEncoded: false)
            for p in processes where PathExclusion.isInside(p.cwd, root: rootPath) {
                if ProcessProbe.devServerCommands.contains(p.command.lowercased()) {
                    s.devServerRunning = true
                } else if ProcessProbe.shellCommands.contains(p.command.lowercased()) {
                    s.openInEditor = true
                }
            }
            for (dir, count) in containersByWorkingDir where PathExclusion.isInside(dir, root: rootPath) {
                s.runningContainers += count
            }
            return s
        }
    }

    static let devServerCommands: Set<String> = [
        "node", "bun", "deno", "python", "python3", "uvicorn", "gunicorn", "flask", "django", "cargo", "go",
        "swift", "ruby", "rails", "php", "java", "gradle", "next-server", "vite", "webpack", "tsc", "nodemon",
        "dotnet", "mix", "elixir", "beam.smp", "flutter", "dart", "ng", "expo",
    ]
    static let shellCommands: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "code", "cursor", "vim", "nvim", "emacs", "claude"]

    public static func gather() async -> Snapshot {
        async let procs = listProcessCwds()
        async let containers = DockerService.shared.runningContainersByWorkingDir()
        return Snapshot(processes: await procs, containersByWorkingDir: await containers)
    }

    /// `lsof -d cwd -Fpcn` prints p<pid>, c<command>, f<fd>, n<path> records.
    static func listProcessCwds() async -> [(command: String, cwd: String)] {
        let out = await Shell.run("/usr/sbin/lsof", ["-d", "cwd", "-Fpcn", "-w"]).stdout
        var result: [(String, String)] = []
        var cmd = ""
        for line in out.split(separator: "\n") {
            guard let first = line.first else { continue }
            let rest = String(line.dropFirst())
            switch first {
            case "c": cmd = rest
            case "n": if rest.hasPrefix("/") { result.append((cmd, rest)) }
            default: break
            }
        }
        return result
    }
}

/// Minimal async process runner.
public enum Shell {
    public struct Output: Sendable {
        public let stdout: String
        public let stderr: String
        public let status: Int32
        public var ok: Bool { status == 0 }
    }

    public static func run(_ executable: String, _ args: [String], timeout: TimeInterval = 60) async -> Output {
        await withCheckedContinuation { cont in
            let task = Process()
            task.executableURL = URL(filePath: executable)
            task.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
            task.environment = env
            let outPipe = Pipe(), errPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = errPipe
            do {
                try task.run()
            } catch {
                cont.resume(returning: Output(stdout: "", stderr: error.localizedDescription, status: -1))
                return
            }
            let timer = DispatchWorkItem { if task.isRunning { task.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            timer.cancel()
            cont.resume(returning: Output(
                stdout: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData, as: UTF8.self),
                status: task.terminationStatus
            ))
        }
    }

    public static func which(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin"] {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}
