import Foundation

struct SimulatorDevice: Identifiable, Hashable {
    let id = UUID()
    let udid: String
    let name: String
    let state: String // "Booted" or "Shutdown"
    let runtime: String
    
    var isBooted: Bool { state == "Booted" }
}

class SimulatorService {
    static let shared = SimulatorService()
    
    func listDevices() async -> [SimulatorDevice] {
        // Runs: xcrun simctl list devices -j
        let output = await runCommand(executable: "/usr/bin/xcrun", args: ["simctl", "list", "devices", "-j"])
        return parseDevices(json: output)
    }
    
    func boot(udid: String) async {
        _ = await runCommand(executable: "/usr/bin/xcrun", args: ["simctl", "boot", udid])
    }
    
    func shutdown(udid: String) async {
        _ = await runCommand(executable: "/usr/bin/xcrun", args: ["simctl", "shutdown", udid])
    }
    
    func erase(udid: String) async {
        // Ensure shutdown first
        await shutdown(udid: udid)
        _ = await runCommand(executable: "/usr/bin/xcrun", args: ["simctl", "erase", udid])
    }
    
    func delete(udid: String) async {
        _ = await runCommand(executable: "/usr/bin/xcrun", args: ["simctl", "delete", udid])
    }
    
    private func parseDevices(json: String) -> [SimulatorDevice] {
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesMap = jsonObject["devices"] as? [String: [[String: Any]]] else {
            return []
        }
        
        var results: [SimulatorDevice] = []
        
        for (runtimeKey, devices) in devicesMap {
            // runtimeKey is like "com.apple.CoreSimulator.SimRuntime.iOS-17-0"
            // Let's make it readable: "iOS 17.0"
            let niceRuntime = runtimeKey.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                                        .replacingOccurrences(of: "-", with: " ")
            
            for dev in devices {
                if let name = dev["name"] as? String,
                   let udid = dev["udid"] as? String,
                   let state = dev["state"] as? String,
                   let isAvailable = dev["isAvailable"] as? Bool,
                   isAvailable { // Only show available
                    
                    results.append(SimulatorDevice(udid: udid, name: name, state: state, runtime: niceRuntime))
                }
            }
        }
        return results.sorted { $0.name < $1.name }
    }
    
    private func runCommand(executable: String, args: [String]) async -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = pipe // Capture error too
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error: \(error)"
        }
    }
}
