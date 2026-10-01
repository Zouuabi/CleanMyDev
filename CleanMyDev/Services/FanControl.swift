import Foundation
import AppKit
import CleanCore

/// SMC writes need root. The app re-executes itself with administrator
/// privileges (one password prompt per change) and the root copy performs the
/// write via `--smc-fan <id> <rpm|auto>` then exits.
enum FanControl {
    static func handleLaunchArguments() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--smc-fan"), i + 2 < args.count else { return false }
        let id = Int(args[i + 1]) ?? 0
        let ok: Bool
        if args[i + 2] == "auto" {
            ok = SMC.shared.setFanAutomatic(id)
        } else {
            ok = SMC.shared.setFanSpeed(id, rpm: Int(args[i + 2]) ?? 0)
        }
        exit(ok ? 0 : 1)
    }

    static func set(fan id: Int, rpm: Int?) async -> Bool {
        guard let exe = Bundle.main.executableURL?.path(percentEncoded: false) else { return false }
        let arg = rpm.map(String.init) ?? "auto"
        let script = "do shell script \"\\\"\(exe)\\\" --smc-fan \(id) \(arg)\" with administrator privileges"
        let r = await Shell.run("/usr/bin/osascript", ["-e", script], timeout: 120)
        return r.ok
    }
}

/// System sounds for key moments. Off via Settings.
enum SoundFX {
    nonisolated(unsafe) static var enabled = true
    static func play(_ name: String) {
        guard enabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
    static func scanStart() { play("Tink") }
    static func scanDone() { play("Glass") }
    static func cleanDone() { play("Hero") }
    static func tap() { play("Pop") }
    static func warning() { play("Basso") }
}
