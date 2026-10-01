import Foundation

/// `xcrun simctl` wrapper. Devices whose runtime is missing can never boot
/// again and are offered automatically; everything else is listed for the
/// user to pick.
public actor SimulatorService: VirtualCleaner {
    public static let shared = SimulatorService()
    public nonisolated let scheme = "simulator"

    public struct Device: Sendable, Identifiable, Hashable {
        public var id: String { udid }
        public let udid: String
        public let name: String
        public let state: String
        public let runtime: String
        public let isAvailable: Bool
        public let dataBytes: UInt64
        public let lastBooted: Date?
        public var isBooted: Bool { state == "Booted" }
    }

    public func listDevices() async -> [Device] {
        let out = await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"]).stdout
        guard let data = out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = root["devices"] as? [String: [[String: Any]]] else { return [] }
        var result: [Device] = []
        for (runtimeKey, list) in devices {
            let runtime = runtimeKey.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
            for d in list {
                guard let udid = d["udid"] as? String, let name = d["name"] as? String else { continue }
                let dataPath = (d["dataPath"] as? String).map { URL(filePath: $0) }
                    ?? CMConstants.coreSimulatorDevices.appending(path: udid).appending(path: "data")
                let bytes = DirectorySizer.size(of: dataPath).allocated
                let lastBooted = (d["lastBootedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                result.append(Device(
                    udid: udid, name: name, state: d["state"] as? String ?? "",
                    runtime: runtime, isAvailable: d["isAvailable"] as? Bool ?? false,
                    dataBytes: bytes, lastBooted: lastBooted
                ))
            }
        }
        return result.sorted { $0.dataBytes > $1.dataBytes }
    }

    public func boot(_ udid: String) async { _ = await Shell.run("/usr/bin/xcrun", ["simctl", "boot", udid]) }
    public func shutdown(_ udid: String) async { _ = await Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", udid]) }
    public func erase(_ udid: String) async {
        await shutdown(udid)
        _ = await Shell.run("/usr/bin/xcrun", ["simctl", "erase", udid])
    }

    public func remove(_ items: [FileItem]) async -> [(FileItem, Error?)] {
        var out: [(FileItem, Error?)] = []
        for item in items {
            let udid = item.url.host() ?? item.url.lastPathComponent
            await shutdown(udid)
            let r = await Shell.run("/usr/bin/xcrun", ["simctl", "delete", udid], timeout: 120)
            out.append((item, r.ok ? nil : SimError.failed(r.stderr)))
        }
        return out
    }

    public enum SimError: LocalizedError {
        case failed(String)
        public var errorDescription: String? { if case .failed(let s) = self { return s } ; return nil }
    }

    public static func item(for device: Device) -> FileItem {
        let reason: String
        if !device.isAvailable {
            reason = "Runtime \(device.runtime) is not installed; this device can't boot"
        } else if let last = device.lastBooted {
            reason = "Last booted \(Int(Date().timeIntervalSince(last) / 86_400)) days ago"
        } else {
            reason = "Never booted"
        }
        return FileItem(url: URL(string: "simulator://\(device.udid)")!, name: "\(device.name) · \(device.runtime)",
                        size: device.dataBytes, isDirectory: true, modificationDate: device.lastBooted, reason: reason)
    }
}

public struct SimulatorModule: ScanModule {
    public let id = "simulators"
    public let name = "Simulators"
    public let group = ModuleGroup.developer
    public init() {}

    public func scan(context: ScanContext) async -> [ScanResult] {
        let devices = await SimulatorService.shared.listDevices()
        let cutoff = context.now.addingTimeInterval(-Double(context.settings.dormantDays) * 86_400)
        let candidates = devices.filter { d in
            !d.isAvailable || (d.lastBooted ?? .distantPast) < cutoff
        }
        guard !candidates.isEmpty else { return [] }
        return [ScanResult(category: .simulators, items: candidates.map(SimulatorService.item(for:)))]
    }
}
