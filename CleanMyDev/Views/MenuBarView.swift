import SwiftUI
import AppKit
import CleanCore

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(ModuleTheme.smart.accent)
                Text("CleanMyDev").font(.headline)
                Spacer()
                if let d = model.settings.lastCleanDate { Text("cleaned \(d.relativeDescription)").font(.caption).foregroundStyle(.secondary) }
            }
            if let s = model.stats {
                HStack(spacing: 10) {
                    ring("CPU", s.cpuUsage, "\(Int(s.cpuUsage * 100))%")
                    ring("Memory", s.memoryFraction, "\(Int(s.memoryFraction * 100))%")
                    ring("Disk", s.diskUsedFraction, "\(Int(s.diskUsedFraction * 100))%")
                }
                HStack {
                    Image(systemName: "internaldrive")
                    Text("\(ByteFormatter.string(s.diskFree)) free of \(ByteFormatter.string(s.diskTotal))").font(.caption)
                    Spacer()
                    if !model.quarantineRuns.isEmpty { Text("\(ByteFormatter.string(QuarantineStore.totalBytes())) quarantined").font(.caption).foregroundStyle(.cyan) }
                }
                .padding(10).glassCard(radius: 10)
            }
            if case .results = model.phase(.smartCare) {
                Text("\(ByteFormatter.string(model.totalBytes(.smartCare))) ready to clean").font(.subheadline.weight(.semibold)).foregroundStyle(ModuleTheme.cleanup.accent)
            }
            HStack(spacing: 8) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    model.selection = .smartCare
                    model.scan(.smartCare)
                } label: { Label("Smart Care", systemImage: "sparkles").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle(tint: ModuleTheme.smart.accent))
                Button { NSApp.activate(ignoringOtherApps: true) } label: { Label("Open", systemImage: "macwindow") }.buttonStyle(SecondaryButtonStyle())
            }
            HStack {
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 330)
        .background(LinearGradient(colors: ModuleTheme.smart.gradient, startPoint: .top, endPoint: .bottom))
    }

    private func ring(_ label: String, _ v: Double, _ center: String) -> some View {
        VStack(spacing: 6) {
            RingGauge(value: v, tint: v > 0.85 ? .red : v > 0.65 ? .orange : ModuleTheme.smart.accent, center: center, lineWidth: 5).frame(width: 52, height: 52)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(8).glassCard(radius: 10)
    }
}
