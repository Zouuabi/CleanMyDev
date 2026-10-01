import Foundation
import CHIDSensors

/// Temperatures and fans. On Apple Silicon the SMC still exposes per-core
/// keys; the tables below come from Stats (MIT) and are tried generation by
/// generation until one yields readings. IOHID "PMU tdie" sensors are the
/// fallback when none match.
public struct ThermalSnapshot: Sendable, Equatable {
    public struct Reading: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let celsius: Double
    }
    public let cpuAverage: Double?
    public let cpuMax: Double?
    public let gpuAverage: Double?
    public let gpuMax: Double?
    public let memory: Double?
    public let readings: [Reading]
    public let fans: [SMC.Fan]
    public let date: Date

    public var hottest: Double? { [cpuMax, gpuMax, memory].compactMap { $0 }.max() }
    public static let empty = ThermalSnapshot(cpuAverage: nil, cpuMax: nil, gpuAverage: nil, gpuMax: nil, memory: nil, readings: [], fans: [], date: .distantPast)
}

public enum Sensors {
    struct KeySet { let cpu: [String]; let gpu: [String]; let memory: [String] }

    /// Newest generation first; the first set with ≥ 2 live CPU keys wins.
    static let keySets: [KeySet] = [
        // M4 family
        KeySet(cpu: ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e", "Tp00", "Tp04"],
               gpu: ["Tg0G", "Tg0H", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k", "Tg1U", "Tg1k"],
               memory: ["Tm0p", "Tm1p", "Tm2p"]),
        // M3 family
        KeySet(cpu: ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"],
               gpu: ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"],
               memory: []),
        // M2 family
        KeySet(cpu: ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"],
               gpu: ["Tg0f", "Tg0j"],
               memory: []),
        // M1 family
        KeySet(cpu: ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"],
               gpu: ["Tg05", "Tg0D", "Tg0L", "Tg0T"],
               memory: []),
        // Intel
        KeySet(cpu: ["TC0P", "TC0D", "TC0E", "TC0F", "TC1C", "TC2C", "TC3C", "TC4C"],
               gpu: ["TG0P", "TG0D"],
               memory: ["TM0P"]),
    ]

    static func readValid(_ keys: [String]) -> [Double] {
        keys.compactMap { k in
            guard let v = SMC.shared.double(k), v > 5, v < 125 else { return nil }
            return v
        }
    }

    static func hidTemperatures() -> [String: Double] {
        guard let raw = CHIDSensorsCopyValues(0xff00, 5, 15) else { return [:] }
        let dict = raw.takeRetainedValue() as NSDictionary
        var out: [String: Double] = [:]
        for (k, v) in dict {
            if let name = k as? String, let value = v as? Double, value > 0, value < 300 { out[name] = value }
        }
        return out
    }

    public static func snapshot() -> ThermalSnapshot {
        var cpu: [Double] = [], gpu: [Double] = [], mem: [Double] = []
        for set in keySets {
            let c = readValid(set.cpu)
            if c.count >= 2 {
                cpu = c; gpu = readValid(set.gpu); mem = readValid(set.memory)
                break
            }
        }
        var readings: [ThermalSnapshot.Reading] = []
        let hid = hidTemperatures()
        if cpu.isEmpty {
            let die = hid.filter { $0.key.hasPrefix("PMU tdie") || $0.key.hasPrefix("pACC") || $0.key.hasPrefix("eACC") }.map(\.value)
            cpu = die
            gpu = hid.filter { $0.key.hasPrefix("GPU MTR") }.map(\.value)
        }
        if let nand = hid.first(where: { $0.key.contains("NAND") }) { readings.append(.init(name: "Storage", celsius: nand.value)) }
        if let battery = hid.first(where: { $0.key.lowercased().contains("battery") }) { readings.append(.init(name: "Battery", celsius: battery.value)) }
        func avg(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        return ThermalSnapshot(
            cpuAverage: avg(cpu), cpuMax: cpu.max(), gpuAverage: avg(gpu), gpuMax: gpu.max(), memory: mem.max(),
            readings: readings, fans: SMC.shared.fans(), date: Date()
        )
    }
}
