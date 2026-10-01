import SwiftUI
import AppKit
import CleanCore

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @State private var fanTarget: Double = 0
    @State private var manual = false

    var body: some View {
        VStack(spacing: 10) {
            header
            if let s = model.stats {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 8) {
                        ring("CPU", s.cpuUsage, "\(Int(s.cpuUsage * 100))%")
                        ring("Memory", s.memoryFraction, "\(Int(s.memoryFraction * 100))%")
                        ring("Disk", s.diskUsedFraction, "\(Int(s.diskUsedFraction * 100))%")
                        tempTile
                    }
                }
            }
            fanCard
            networkCard
            securityCard
            HStack(spacing: 8) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    model.selection = .smartCare
                    model.scan(.smartCare)
                } label: { Label("Smart Care", systemImage: "sparkles").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle(tint: ModuleTheme.brand))
                Button { NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "macwindow") }.buttonStyle(SecondaryButtonStyle())
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(LinearGradient(colors: ModuleTheme.smart.gradient, startPoint: .top, endPoint: .bottom))
        .onAppear { syncFan() }
        .onChange(of: model.thermal.fans.first?.actual) { _, _ in if !manual { syncFan() } }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(ModuleTheme.brand)
            Text("CleanMyDev").font(.headline)
            Spacer()
            if let s = model.stats { Text("\(ByteFormatter.string(s.diskFree)) free").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func ring(_ label: String, _ v: Double, _ center: String) -> some View {
        VStack(spacing: 5) {
            RingGauge(value: v, tint: v > 0.85 ? .red : v > 0.65 ? .orange : ModuleTheme.brand, center: center, lineWidth: 5).frame(width: 48, height: 48)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).glassCard(radius: 12)
    }

    private var tempTile: some View {
        let t = model.thermal.cpuMax ?? 0
        let tint: Color = t > 90 ? .red : t > 75 ? .orange : ModuleTheme.brand
        return VStack(spacing: 5) {
            ZStack {
                RingGauge(value: min(t / 105, 1), tint: tint, center: t > 0 ? "\(Int(t))°" : "--", lineWidth: 5).frame(width: 48, height: 48)
            }
            Text("CPU temp").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).glassCard(radius: 12)
        .help("GPU \(Int(model.thermal.gpuMax ?? 0))° · Memory \(Int(model.thermal.memory ?? 0))°")
    }

    private var fanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fan.fill").foregroundStyle(ModuleTheme.brand)
                    .symbolEffect(.rotate.byLayer, options: .repeat(.continuous).speed(max(0.3, (model.thermal.fans.first?.fraction ?? 0) * 2)))
                if let fan = model.thermal.fans.first {
                    Text("\(Int(fan.actual)) rpm").font(.subheadline.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                    Text(fan.isManual ? "manual" : "auto").font(.caption2).foregroundStyle(fan.isManual ? .orange : .secondary)
                } else {
                    Text("No fan reported").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.fanBusy { ProgressView().controlSize(.small) }
                Toggle("Manual", isOn: $manual).toggleStyle(.switch).controlSize(.mini)
                    .onChange(of: manual) { _, on in if !on { model.setFan(0, rpm: nil) } }
            }
            if let fan = model.thermal.fans.first, manual {
                HStack(spacing: 8) {
                    Slider(value: $fanTarget, in: fan.minimum...max(fan.maximum, fan.minimum + 1), step: 100)
                    Text("\(Int(fanTarget))").font(.caption.monospacedDigit()).frame(width: 40)
                    Button("Apply") { model.setFan(0, rpm: Int(fanTarget)) }.buttonStyle(SecondaryButtonStyle()).controlSize(.small)
                }
                Text("Needs your password once per change. Auto hands control back to macOS.").font(.caption2).foregroundStyle(.secondary)
            }
            if let e = model.fanError { Text(e).font(.caption2).foregroundStyle(.orange) }
        }
        .padding(10).glassCard(radius: 12)
    }

    private func syncFan() {
        if let fan = model.thermal.fans.first {
            fanTarget = fan.target > 0 ? fan.target : fan.actual
            manual = fan.isManual
        }
    }

    private var networkCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "speedometer").foregroundStyle(ModuleTheme.brand)
            switch model.speedPhase {
            case .idle:
                if let r = model.lastSpeed {
                    Text("↓ \(Int(r.downloadMbps)) ↑ \(Int(r.uploadMbps)) Mbps · \(Int(r.latencyMs)) ms").font(.caption.monospacedDigit())
                } else {
                    Text("Network speed").font(.caption)
                }
            case .latency: HStack(spacing: 6) { PulseDots(tint: ModuleTheme.brand); Text("Pinging…").font(.caption) }
            case .download(let mbps): Text("↓ \(Int(mbps)) Mbps…").font(.caption.monospacedDigit()).contentTransition(.numericText())
            case .upload: HStack(spacing: 6) { PulseDots(tint: ModuleTheme.brand); Text("Uploading…").font(.caption) }
            case .done(let r): Text("↓ \(Int(r.downloadMbps)) ↑ \(Int(r.uploadMbps)) Mbps · \(Int(r.latencyMs)) ms").font(.caption.monospacedDigit())
            case .failed(let e): Text(e).font(.caption2).foregroundStyle(.orange).lineLimit(1)
            }
            Spacer()
            Button("Test") { model.runSpeedTest() }.buttonStyle(SecondaryButtonStyle()).controlSize(.small)
        }
        .padding(10).glassCard(radius: 12)
    }

    private var securityCard: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            model.selection = .security
            if case .idle = model.phase(.security) { model.scan(.security) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.securityFlags > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .foregroundStyle(model.securityFlags > 0 ? .orange : ModuleTheme.brand)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.securityFlags > 0 ? "\(model.securityFlags) items need a look" : "Nothing flagged").font(.caption.weight(.semibold))
                    Text(model.securityLastScan.map { "Checked \($0.relativeDescription)" } ?? "Run a security check").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10).glassCard(radius: 12)
        }
        .buttonStyle(.plain)
    }
}
