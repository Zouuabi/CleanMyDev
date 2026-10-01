import Foundation

struct SystemStats {
    var cpuUsage: Double
    var ramUsage: Double
    var totalDisk: Int64
    var usedDisk: Int64
}

class SystemStatsService {
    static let shared = SystemStatsService()
    
    func getSystemStats() async -> SystemStats {
        async let cpu = getCPUUsage()
        async let ram = getRAMUsage()
        // Disk stats are usually static enough or can be fetched from DiskService
        // But for "Live" total, we can sum them up here or just pass what we have.
        // Let's re-use DiskService for accuracy if we want, or do a quick check.
        // For efficiency, we might just rely on the existing DiskService for disk data 
        // and only do CPU/RAM here.
        // But to satisfy the struct, let's grab them.
        let disks = DiskService.shared.getMountedDisks()
        let totalVal = disks.reduce(0) { $0 + $1.totalCapacity }
        let usedVal = disks.reduce(0) { $0 + $1.usedCapacity }
        
        return await SystemStats(cpuUsage: cpu, ramUsage: ram, totalDisk: totalVal, usedDisk: usedVal)
    }
    
    private func getCPUUsage() async -> Double {
        // top -l 1 | grep "CPU usage"
        // Output: CPU usage: 5.59% user, 12.94% sys, 81.46% idle
        // Usage = user + sys
        
        let output = await runCommand(executable: "/usr/bin/top", args: ["-l", "1", "-n", "0"])
        let lines = output.components(separatedBy: .newlines)
        
        if let cpuLine = lines.first(where: { $0.contains("CPU usage") }) {
            // Example: CPU usage: 10.5% user, 5.0% sys, 84.5% idle
            // We want (10.5 + 5.0)
            
            let parts = cpuLine.split(separator: " ")
            var totalUsage: Double = 0
            
            for (index, part) in parts.enumerated() {
                if part == "user," || part == "sys," {
                    // Previous element is the number like "10.5%"
                    if index > 0 {
                        let numStr = parts[index - 1].replacingOccurrences(of: "%", with: "")
                        totalUsage += Double(numStr) ?? 0
                    }
                }
            }
            return totalUsage / 100.0 // Normalize to 0.0 - 1.0
        }
        
        return 0.0
    }
    
    private func getRAMUsage() async -> Double {
        // sysctl -n hw.memsize (Total)
        // vm_stat (Pages free / active / etc)
        // This is complex to parse perfectly.
        // Simpler approach: top -l 1 | grep PhysMem
        // PhysMem: 16G used (2345M wired), 123M unused.
        
        let output = await runCommand(executable: "/usr/bin/top", args: ["-l", "1", "-n", "0"])
        let lines = output.components(separatedBy: .newlines)
        
        if let memLine = lines.first(where: { $0.contains("PhysMem:") }) {
            // PhysMem: 15G used (2289M wired), 735M unused.
            // We want used / (used + unused) roughly.
            
            // Parse "15G used" and "735M unused"
            let parts = memLine.split(separator: " ")
            var usedBytes: Double = 0
            var unusedBytes: Double = 0
            
            // Iterate to find "used" and "unused"
            for (index, part) in parts.enumerated() {
                if part.hasPrefix("used") && index > 0 {
                    let valStr = parts[index - 1]
                    usedBytes = parseBytes(valStr)
                }
                if part.hasPrefix("unused") && index > 0 {
                    let valStr = parts[index - 1]
                    unusedBytes = parseBytes(valStr)
                }
            }
            
            let total = usedBytes + unusedBytes
            if total > 0 {
                return usedBytes / total
            }
        }
        
        return 0.0
    }
    
    private func parseBytes(_ str: String.SubSequence) -> Double {
        // 15G, 735M, etc.
        let s = String(str).uppercased()
        if s.hasSuffix("G") {
            let num = Double(s.dropLast()) ?? 0
            return num * 1_073_741_824
        } else if s.hasSuffix("M") {
            let num = Double(s.dropLast()) ?? 0
            return num * 1_048_576
        } else if s.hasSuffix("K") {
            let num = Double(s.dropLast()) ?? 0
            return num * 1024
        }
        return Double(s) ?? 0
    }
    
    private func runCommand(executable: String, args: [String]) async -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = Pipe() // Ignore stderr
        
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
