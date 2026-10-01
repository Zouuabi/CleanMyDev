import SwiftUI
import CleanCore

/// Live scan screen: real counters from `ScanTelemetry`, a spinning
/// gradient ring with an advancing progress arc, the path flashing by, and a
/// module rail that lights up as each module finishes.
struct ScanningView: View {
    @Environment(AppModel.self) private var model
    let scope: SidebarItem
    let progress: Double
    let module: String
    let found: UInt64
    @State private var spin = false

    private var moduleNames: [String] {
        let all: [(String, String)] = [("system_junk", "System Junk"), ("dev_junk", "Dev Junk"), ("docker", "Docker"), ("simulators", "Simulators"),
                                       ("privacy", "Browsers"), ("malware", "Security"), ("trash", "Trash"), ("large_files", "Large files")]
        let ids = scope.moduleIDs ?? []
        return all.filter { ids.contains($0.0) }.map(\.1)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let t = ScanTelemetry.shared.snapshot
            VStack(spacing: 26) {
                Spacer(minLength: 20)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 14).frame(width: 230, height: 230)
                    Circle()
                        .trim(from: 0, to: 0.35)
                        .stroke(AngularGradient(colors: [scope.theme.accent.opacity(0), scope.theme.accent.opacity(0.9)], center: .center),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 230, height: 230)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(scope.theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 230, height: 230)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.9), value: progress)
                        .shadow(color: scope.theme.accent.opacity(0.7), radius: 14)
                    VStack(spacing: 4) {
                        Text(ByteFormatter.string(t.bytesFound + found)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(countsDown: false))
                        Text("junk found").font(.caption).foregroundStyle(.secondary)
                        Text("\(t.filesVisited.formatted()) files looked at").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            .contentTransition(.numericText())
                    }
                    .animation(.easeOut(duration: 0.2), value: t.filesVisited)
                }
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        PulseDots(tint: scope.theme.accent)
                        Text(t.currentModule.isEmpty ? module : t.currentModule).font(.title3.weight(.semibold)).contentTransition(.opacity)
                    }
                    Text(t.currentPath.replacingOccurrences(of: CMConstants.homePath, with: "~"))
                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 560).frame(height: 16)
                }
                moduleRail(current: t.currentModule.isEmpty ? module : t.currentModule)
                Button { model.cancelScan(scope) } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
        }
        .onAppear { withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { spin = true } }
    }

    private func moduleRail(current: String) -> some View {
        let names = moduleNames
        let idx = names.firstIndex(of: current) ?? -1
        return HStack(spacing: 10) {
            ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                let done = i < idx
                let active = i == idx
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : active ? "circle.dotted" : "circle")
                        .foregroundStyle(done ? scope.theme.accent : active ? .white : .white.opacity(0.3))
                        .symbolEffect(.pulse, isActive: active)
                    Text(name).font(.caption.weight(active ? .bold : .regular)).foregroundStyle(done || active ? .white : .white.opacity(0.4))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassEffect(.regular.tint(active ? scope.theme.accent.opacity(0.35) : Color.black.opacity(0.1)), in: .capsule)
                .animation(.spring(duration: 0.4), value: idx)
            }
        }
    }
}
