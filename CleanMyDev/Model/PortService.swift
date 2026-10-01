import Foundation

struct OpenPort: Identifiable, Hashable {
    let id = UUID()
    let pid: Int
    let process: String
    let port: Int
    
    var iconName: String {
        if process.contains("node") { return "hexagon.fill" }
        if process.contains("python") { return "mustache.fill" } // Python logo approx
        if process.contains("java") { return "cup.and.saucer.fill" }
        if process.contains("postgres") { return "database.fill" }
        return "gearshape.fill"
    }
}

class PortService {
    static let shared = PortService()
    
    func findProcess(on port: Int) async -> OpenPort? {
        let output = await runCommand(executable: "/usr/sbin/lsof", args: ["-i", ":\(port)"])
        let lines = output.components(separatedBy: .newlines)
        if lines.count > 1 {
            let content = lines[1]
            let parts = content.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, let pid = Int(parts[1]) {
                let command = String(parts[0])
                return OpenPort(pid: pid, process: command, port: port)
            }
        }
        return nil
    }
    
    func listListeningPorts() async -> [OpenPort] {
        // -iTCP: TCP only
        // -sTCP:LISTEN : Listening state only
        // -P : No port names (use numbers)
        // -n : No host names
        // +c 0: Show full command name
        let output = await runCommand(executable: "/usr/sbin/lsof", args: ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "+c", "0"])
        
        // Output format:
        // COMMAND     PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        // launchd       1     root   19u  IPv6 0x...      0t0  TCP *:445 (LISTEN)
        // node      12345  macmini   22u  IPv6 0x...      0t0  TCP *:8080 (LISTEN)
        
        var results: [OpenPort] = []
        let lines = output.components(separatedBy: .newlines)
        
        // Skip header (index 0)
        guard lines.count > 1 else { return [] }
        
        for line in lines.dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }
            
            // COMMAND (0) ... PID (1) ... NAME (last)
            let command = String(parts[0])
            
            // PID is reliable at index 1 usually, but if command has spaces it breaks.
            // lsof output is tricky. "launchd" is safe. "Google Chrome" is not safe with simple split.
            // But we used "+c 0" which might help or make it worse if spaces exist.
            // Safest bet for simple CLI parsing: Process usually is first column(s).
            // Actually, lsof columnar output is standard.
            
            // Let's assume standard simple process names for now or try to parse from end.
            // NAME field is roughly last. "TCP *:8080 (LISTEN)"
            // The port is inside the NAME column, e.g. "*:8080"
            
            guard let pid = Int(parts[1]) else { continue }
            
            // Find port in the last part matching "*:1234" or "127.0.0.1:1234"
            // The format is typically IP:PORT
            
            // Find the part that contains ":" and looks like an address
            // It is usually the 9th column (index 8) or 10th
            // Example:
            // node 123 u 22 ... TCP *:3000 (LISTEN)
            // parts: [node, 123, u, ...]
            
            // Let's look for the part that has the port
            // It usually appears before "(LISTEN)"
            
            for part in parts {
                let s = String(part)
                if s.contains(":") && !s.contains("IPv") && !s.contains("TCP") {
                    // Start from last colon
                     if let lastColon = s.lastIndex(of: ":") {
                         let portStr = s[s.index(after: lastColon)...]
                         if let port = Int(portStr) {
                             // Deduplicate: lsof lists IPv4 and IPv6 separately often
                             if !results.contains(where: { $0.port == port && $0.process == command }) {
                                 results.append(OpenPort(pid: pid, process: command, port: port))
                             }
                         }
                     }
                }
            }
        }
        
        return results.sorted { $0.port < $1.port }
    }
    
    func getTopOpenPorts(limit: Int) async -> [OpenPort] {
        let all = await listListeningPorts()
        return Array(all.prefix(limit))
    }
    
    func kill(pid: Int) async -> Bool {
        let output = await runCommand(executable: "/bin/kill", args: ["-9", "\(pid)"])
        return output.isEmpty // kill usually returns nothing on success
    }
    
    private func runCommand(executable: String, args: [String]) async -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
