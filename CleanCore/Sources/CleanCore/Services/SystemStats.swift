import Foundation
import Darwin

/// CPU, memory, and disk readings from Mach and statfs. No subprocesses.
public struct SystemStats: Sendable, Equatable {
    public let cpuUsage: Double        // 0...1
    public let memoryUsed: UInt64
    public let memoryTotal: UInt64
    public let memoryPressure: Double  // 0...1
    public let diskTotal: UInt64
    public let diskFree: UInt64
    public let uptime: TimeInterval

    public var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    public var diskUsedFraction: Double { diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0 }
}

public actor SystemStatsCollector {
    public static let shared = SystemStatsCollector()
    private var lastCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    public func sample() -> SystemStats {
        SystemStats(
            cpuUsage: cpu(), memoryUsed: memory().used, memoryTotal: memory().total, memoryPressure: memory().pressure,
            diskTotal: disk().total, diskFree: disk().free, uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func cpu() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let ticks = (UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3))
        defer { lastCPUTicks = ticks }
        guard let last = lastCPUTicks else { return 0 }
        let user = ticks.0 - last.user, system = ticks.1 - last.system, idle = ticks.2 - last.idle, nice = ticks.3 - last.nice
        let total = user + system + idle + nice
        return total > 0 ? Double(user + system + nice) / Double(total) : 0
    }

    private func memory() -> (used: UInt64, total: UInt64, pressure: Double) {
        let total = ProcessInfo.processInfo.physicalMemory
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total, 0) }
        let page = UInt64(getpagesize())
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let pressure = Double(min(used, total)) / Double(total)
        return (used, total, pressure)
    }

    private func disk() -> (total: UInt64, free: UInt64) {
        var fs = statfs()
        guard statfs("/System/Volumes/Data", &fs) == 0 || statfs("/", &fs) == 0 else { return (0, 0) }
        let block = UInt64(fs.f_bsize)
        return (UInt64(fs.f_blocks) * block, UInt64(fs.f_bavail) * block)
    }
}
