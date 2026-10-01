import Foundation
import IOKit

/// Minimal System Management Controller client: read keys (fans, some
/// temperatures) and write fan targets. Reads work as the user; writes need
/// root, so the app re-executes itself with administrator privileges for
/// those (see `FanControl`).
///
/// Adapted from Stats by Serhiy Mytrovtsiy (MIT).
public final class SMC: @unchecked Sendable {
    public static let shared = SMC()

    private var conn: io_connect_t = 0
    private let lock = NSLock()
    private var fanModeKeyIsLower: Bool?
    public private(set) var isOpen = false

    private enum Selector: UInt8 { case kernelIndex = 2, readBytes = 5, writeBytes = 6, readIndex = 8, readKeyInfo = 9 }

    private struct KeyData {
        struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
        struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0 }
        struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    public struct Value {
        public var key: String
        public var dataSize: UInt32 = 0
        public var dataType: String = ""
        public var bytes: [UInt8] = Array(repeating: 0, count: 32)
        init(_ key: String) { self.key = key }
    }

    private init() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) == kIOReturnSuccess else { return }
        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return }
        let r = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
        isOpen = r == kIOReturnSuccess
    }

    deinit { if isOpen { IOServiceClose(conn) } }

    // MARK: Reading

    public func double(_ key: String) -> Double? {
        var v = Value(key)
        guard read(&v) == kIOReturnSuccess, v.dataSize > 0 else { return nil }
        let b = v.bytes
        if b.first(where: { $0 != 0 }) == nil, !["FS! ", "F0Md", "F1Md", "F0md", "F1md"].contains(key) { return nil }
        func u16() -> Double { Double(UInt16(b[0]) << 8 | UInt16(b[1])) }
        func s16() -> Double { Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) }
        switch v.dataType {
        case "ui8 ": return Double(b[0])
        case "ui16": return u16()
        case "ui32": return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        case "sp1e": return u16() / 16384
        case "sp3c": return u16() / 4096
        case "sp4b": return u16() / 2048
        case "sp5a": return u16() / 1024
        case "sp69": return u16() / 512
        case "sp78": return s16() / 256
        case "sp87": return s16() / 128
        case "sp96": return s16() / 64
        case "spa5": return u16() / 32
        case "spb4": return s16() / 16
        case "spf0": return s16()
        case "flt ": return Double(b.withUnsafeBytes { $0.load(as: Float.self) })
        case "fpe2": return Double((Int(b[0]) << 6) + (Int(b[1]) >> 2))
        default: return nil
        }
    }

    public func fanCount() -> Int { Int(double("FNum") ?? 0) }

    public struct Fan: Sendable, Identifiable, Equatable {
        public let id: Int
        public let actual: Double
        public let minimum: Double
        public let maximum: Double
        public let target: Double
        public let isManual: Bool
        public var fraction: Double { maximum > minimum ? (actual - minimum) / (maximum - minimum) : 0 }
    }

    public func fans() -> [Fan] {
        (0..<fanCount()).map { i in
            let mode = double(fanModeKey(i)) ?? 0
            return Fan(id: i,
                       actual: double("F\(i)Ac") ?? 0,
                       minimum: double("F\(i)Mn") ?? 0,
                       maximum: double("F\(i)Mx") ?? 0,
                       target: double("F\(i)Tg") ?? 0,
                       isManual: mode == 1)
        }
    }

    public func fanModeKey(_ id: Int) -> String {
        if fanModeKeyIsLower == nil {
            var probe = Value("F0md")
            fanModeKeyIsLower = read(&probe) == kIOReturnSuccess && probe.dataSize > 0
        }
        return fanModeKeyIsLower == true ? "F\(id)md" : "F\(id)Md"
    }

    /// Every key the SMC exposes; useful for discovering temperature keys.
    public func allKeys() -> [String] {
        guard let n = double("#KEY") else { return [] }
        var out: [String] = []
        for i in 0..<Int(n) {
            var input = KeyData(), output = KeyData()
            input.data8 = Selector.readIndex.rawValue
            input.data32 = UInt32(i)
            guard call(&input, &output) == kIOReturnSuccess else { continue }
            out.append(Self.fourCC(output.key))
        }
        return out
    }

    // MARK: Writing (needs root)

    /// Returns true when the write landed. On Apple Silicon the fan mode must
    /// be unlocked first; the sequence follows Stats' tested approach.
    public func setFanSpeed(_ id: Int, rpm: Int) -> Bool {
        let clamped = min(rpm, Int(double("F\(id)Mx") ?? Double(rpm)))
        var mode = Value(fanModeKey(id))
        guard read(&mode) == kIOReturnSuccess else { return false }
        if mode.bytes[0] != 1, !unlockFanControl(id) { return false }
        var target = Value("F\(id)Tg")
        guard read(&target) == kIOReturnSuccess else { return false }
        if target.dataType == "flt " {
            let b = withUnsafeBytes(of: Float(clamped)) { Array($0) }
            target.bytes[0] = b[0]; target.bytes[1] = b[1]; target.bytes[2] = b[2]; target.bytes[3] = b[3]
        } else {
            target.bytes[0] = UInt8(clamped >> 6); target.bytes[1] = UInt8((clamped << 2) & 0xFF); target.bytes[2] = 0; target.bytes[3] = 0
        }
        return writeWithRetry(target)
    }

    public func setFanAutomatic(_ id: Int) -> Bool {
        var mode = Value(fanModeKey(id))
        if read(&mode) == kIOReturnSuccess, mode.bytes[0] != 0 {
            mode.bytes[0] = 0
            guard writeWithRetry(mode) else { return false }
        }
        var target = Value("F\(id)Tg")
        guard read(&target) == kIOReturnSuccess else { return false }
        target.bytes[0] = 0; target.bytes[1] = 0; target.bytes[2] = 0; target.bytes[3] = 0
        _ = writeWithRetry(target)
        var ftst = Value("Ftst")
        if read(&ftst) == kIOReturnSuccess, ftst.dataSize > 0, ftst.bytes[0] != 0 {
            ftst.bytes[0] = 0
            _ = writeWithRetry(ftst)
        }
        return true
    }

    private func unlockFanControl(_ id: Int) -> Bool {
        var mode = Value(fanModeKey(id))
        guard read(&mode) == kIOReturnSuccess else { return false }
        mode.bytes[0] = 1
        if write(mode) == kIOReturnSuccess { return true }
        var ftst = Value("Ftst")
        guard read(&ftst) == kIOReturnSuccess, ftst.dataSize > 0 else { return false }
        if ftst.bytes[0] != 1 {
            ftst.bytes[0] = 1
            guard writeWithRetry(ftst, attempts: 100) else { return false }
            usleep(3_000_000)
        }
        return writeWithRetry(mode, attempts: 300, delayMicros: 100_000)
    }

    private func writeWithRetry(_ v: Value, attempts: Int = 10, delayMicros: UInt32 = 50_000) -> Bool {
        for i in 0..<attempts {
            if write(v) == kIOReturnSuccess { return true }
            if i < attempts - 1 { usleep(delayMicros) }
        }
        return false
    }

    // MARK: Plumbing

    private func read(_ value: inout Value) -> kern_return_t {
        var input = KeyData(), output = KeyData()
        input.key = Self.fourCC(value.key)
        input.data8 = Selector.readKeyInfo.rawValue
        var r = call(&input, &output)
        guard r == kIOReturnSuccess else { return r }
        value.dataSize = output.keyInfo.dataSize
        value.dataType = Self.fourCC(output.keyInfo.dataType)
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = Selector.readBytes.rawValue
        r = call(&input, &output)
        guard r == kIOReturnSuccess else { return r }
        withUnsafeBytes(of: output.bytes) { src in
            for i in 0..<min(Int(value.dataSize), 32) { value.bytes[i] = src[i] }
        }
        return kIOReturnSuccess
    }

    private func write(_ value: Value) -> kern_return_t {
        var input = KeyData(), output = KeyData()
        input.key = Self.fourCC(value.key)
        input.data8 = Selector.writeBytes.rawValue
        input.keyInfo.dataSize = value.dataSize
        withUnsafeMutableBytes(of: &input.bytes) { dst in
            for i in 0..<32 { dst[i] = value.bytes[i] }
        }
        let r = call(&input, &output)
        guard r == kIOReturnSuccess else { return r }
        return output.result == 0 ? kIOReturnSuccess : kIOReturnError
    }

    private func call(_ input: inout KeyData, _ output: inout KeyData) -> kern_return_t {
        guard isOpen else { return kIOReturnNotOpen }
        lock.lock(); defer { lock.unlock() }
        let inSize = MemoryLayout<KeyData>.stride
        var outSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(conn, UInt32(Selector.kernelIndex.rawValue), &input, inSize, &output, &outSize)
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func fourCC(_ v: UInt32) -> String {
        String(UnicodeScalar(UInt8(v >> 24 & 0xFF))) + String(UnicodeScalar(UInt8(v >> 16 & 0xFF)))
            + String(UnicodeScalar(UInt8(v >> 8 & 0xFF))) + String(UnicodeScalar(UInt8(v & 0xFF)))
    }
}
