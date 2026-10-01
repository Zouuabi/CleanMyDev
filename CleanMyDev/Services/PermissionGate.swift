import Foundation
import AppKit
import SwiftUI
import CleanCore

/// Full Disk Access check. macOS has no API for it, so we probe a TCC-protected
/// file that every account has: without FDA the read fails with EPERM even
/// though the file is owned by the user.
@Observable
@MainActor
final class PermissionGate {
    private(set) var hasFullDiskAccess: Bool
    private var timer: Timer?

    init() {
        hasFullDiskAccess = Self.probe()
        startPolling()
    }

    static func probe() -> Bool {
        let home = CMConstants.homePath
        let probes = [
            "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Safari/Bookmarks.plist",
            "\(home)/Library/Mail",
            "\(home)/Library/Containers/com.apple.Safari",
        ]
        for p in probes {
            let fd = open(p, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            if errno == ENOENT { continue }        // file missing on this account, try the next
            if errno == EPERM || errno == EACCES { return false }
        }
        // Nothing to probe against (no Safari, no Mail): assume granted.
        return true
    }

    func recheck() { hasFullDiskAccess = Self.probe() }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.hasFullDiskAccess else { return }
                self.recheck()
                if self.hasFullDiskAccess { self.timer?.invalidate(); NSApp.activate(ignoringOtherApps: true) }
            }
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func relaunch() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/open")
        task.arguments = ["-n", url.path(percentEncoded: false)]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

struct PermissionGateView: View {
    @Environment(PermissionGate.self) private var gate
    @State private var opened = false

    var body: some View {
        ZStack {
            ThemeBackground(theme: .smart)
            VStack(spacing: 26) {
                ZStack {
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .fill(LinearGradient(colors: [ModuleTheme.smart.accent.opacity(0.55), ModuleTheme.smart.accent.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 160, height: 160)
                        .shadow(color: ModuleTheme.smart.accent.opacity(0.45), radius: 36, y: 14)
                    Image(systemName: "lock.shield").font(.system(size: 70, weight: .medium)).foregroundStyle(.white)
                }
                VStack(spacing: 10) {
                    Text("CleanMyDev needs Full Disk Access").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Without it macOS hides Mail, Safari, Containers and parts of ~/Library, so scans would miss junk and the uninstaller would leave files behind. CleanMyDev never sends anything off this Mac.")
                        .foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center).frame(maxWidth: 520)
                }
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Click **Open System Settings** below. The Full Disk Access list opens.")
                    step(2, "Click **+**, pick **CleanMyDev** (use *Reveal app* if you're not sure where it is), then turn its switch on.")
                    step(3, "Come back here. This screen closes by itself as soon as access is granted.")
                }
                .padding(20).frame(maxWidth: 560).glassCard()
                HStack(spacing: 12) {
                    Button { PermissionGate.openSystemSettings(); opened = true } label: { Label("Open System Settings", systemImage: "gearshape") }
                        .buttonStyle(PrimaryButtonStyle(tint: ModuleTheme.smart.accent))
                    Button { PermissionGate.revealAppInFinder() } label: { Label("Reveal app", systemImage: "magnifyingglass") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { gate.recheck() } label: { Label("Check again", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { PermissionGate.relaunch() } label: { Label("Relaunch", systemImage: "arrow.counterclockwise.circle") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Text("Granted it but still here? macOS sometimes applies the change only to a fresh process. Click Relaunch.")
                    .font(.caption).foregroundStyle(.secondary)
                if opened {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Waiting for access…").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .padding(40)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.caption.weight(.bold)).frame(width: 22, height: 22)
                .background(ModuleTheme.smart.accent.opacity(0.25), in: Circle()).foregroundStyle(ModuleTheme.smart.accent)
            Text(.init(text)).foregroundStyle(.white.opacity(0.9))
        }
    }
}
