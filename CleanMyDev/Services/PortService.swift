import Foundation
import CleanCore

struct OpenPort: Identifiable, Hashable, Sendable {
    var id: String { "\(pid):\(port)" }
    let pid: Int
    let process: String
    let port: Int
    let address: String
}

enum PortService {
    /// `lsof -iTCP -sTCP:LISTEN -P -n -Fpcn` → p<pid> c<cmd> n<addr:port> records.
    static func listListeningPorts() async -> [OpenPort] {
        let out = await Shell.run("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-Fpcn", "-w"]).stdout
        var pid = 0, cmd = ""
        var seen = Set<String>()
        var result: [OpenPort] = []
        for line in out.split(separator: "\n") {
            guard let first = line.first else { continue }
            let rest = String(line.dropFirst())
            switch first {
            case "p": pid = Int(rest) ?? 0
            case "c": cmd = rest
            case "n":
                guard let colon = rest.lastIndex(of: ":"), let port = Int(rest[rest.index(after: colon)...]) else { continue }
                let key = "\(pid):\(port)"
                guard seen.insert(key).inserted else { continue }
                result.append(OpenPort(pid: pid, process: cmd, port: port, address: String(rest[..<colon])))
            default: break
            }
        }
        return result.sorted { $0.port < $1.port }
    }

    static func kill(pid: Int) async {
        _ = await Shell.run("/bin/kill", ["-9", "\(pid)"])
    }
}
