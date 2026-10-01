import SwiftUI
import AppKit
import CleanCore

struct QuarantineView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quarantine").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("\(ByteFormatter.string(QuarantineStore.totalBytes())) held · purged automatically after \(model.settings.quarantineRetentionDays) days").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open folder") { NSWorkspace.shared.activateFileViewerSelecting([CMConstants.quarantineDir]) }.buttonStyle(SecondaryButtonStyle())
                Button("Empty quarantine", role: .destructive) { model.quarantineRuns.forEach { model.purge($0) } }
                    .buttonStyle(SecondaryButtonStyle()).disabled(model.quarantineRuns.isEmpty)
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)

            if model.quarantineRuns.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "archivebox").font(.system(size: 64)).foregroundStyle(.secondary)
                    Text("Nothing in quarantine").font(.title2.weight(.semibold))
                    Text("Cleaned items land here first, so a mistake costs one click to undo.").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.quarantineRuns) { run in
                            runCard(run)
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 24)
                }
            }
        }
    }

    private func runCard(_ run: QuarantineManifest) -> some View {
        let isOpen = expanded.contains(run.runID)
        let expires = run.date.addingTimeInterval(model.settings.quarantineRetention)
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath").font(.title3).foregroundStyle(ModuleTheme.neutral.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.label).font(.headline)
                    Text("\(run.date.formatted(date: .abbreviated, time: .shortened)) · \(run.entries.count) items · expires \(expires.relativeDescription)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SizeText(bytes: run.totalBytes)
                Button("Restore all") { model.restore(run) }.buttonStyle(SecondaryButtonStyle())
                Button("Delete") { model.purge(run) }.buttonStyle(SecondaryButtonStyle())
                Button { if isOpen { expanded.remove(run.runID) } else { expanded.insert(run.runID) } } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(isOpen ? 90 : 0)).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 22)
                }.buttonStyle(.plain)
            }
            .padding(14)
            if isOpen {
                Divider().opacity(0.2)
                VStack(spacing: 0) {
                    ForEach(run.entries) { e in
                        HStack {
                            Text(e.original.replacingOccurrences(of: CMConstants.home.path(percentEncoded: false), with: "~"))
                                .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(ByteFormatter.string(e.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 5)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .glassCard(radius: 14)
    }
}

struct StartupItemsView: View {
    @Environment(AppModel.self) private var model
    @State private var onlySuspicious = false

    private var rows: [PersistenceItem] { model.persistence.filter { !onlySuspicious || $0.isSuspicious } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Startup Items").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("\(model.persistence.count) launch agents and daemons · \(model.persistence.filter(\.isSuspicious).count) need a look").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Only flagged", isOn: $onlySuspicious).toggleStyle(.switch).controlSize(.small)
                Button { model.loadPersistence() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { item in
                        HStack(spacing: 14) {
                            Image(systemName: item.isSuspicious ? "exclamationmark.shield.fill" : "checkmark.shield")
                                .foregroundStyle(item.isSuspicious ? .orange : ModuleTheme.protection.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(item.program ?? "no program").font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                if item.isSuspicious { Text(item.findings.joined(separator: " · ")).font(.caption).foregroundStyle(.orange) }
                            }
                            Spacer()
                            StatusChip(text: item.scope.rawValue, systemImage: "gearshape", tint: .secondary)
                            StatusChip(text: item.signature.rawValue, systemImage: sigSymbol(item.signature), tint: sigTint(item.signature))
                            Button { NSWorkspace.shared.activateFileViewerSelecting([item.plistURL]) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).foregroundStyle(.secondary)
                            if item.scope == .userAgent {
                                Button {
                                    Task { _ = await model.quarantine(paths: [item.plistURL], label: "Startup item \(item.label)"); model.loadPersistence() }
                                } label: { Image(systemName: "archivebox") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Move to quarantine (disables it at next login)")
                            }
                        }
                        .padding(12)
                        .glassCard(radius: 12, tint: item.isSuspicious ? .orange : nil)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
        .task { if model.persistence.isEmpty { model.loadPersistence() } }
    }

    private func sigSymbol(_ s: PersistenceItem.Signature) -> String {
        switch s {
        case .apple: "apple.logo"
        case .developerID: "checkmark.seal"
        case .adHoc, .unsigned: "xmark.seal"
        case .missing: "questionmark.folder"
        case .unknown: "questionmark"
        }
    }

    private func sigTint(_ s: PersistenceItem.Signature) -> Color {
        switch s {
        case .apple, .developerID: .green
        case .adHoc, .unsigned: .orange
        case .missing: .red
        case .unknown: .secondary
        }
    }
}

struct PortsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ports").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("\(model.ports.count) listening TCP ports").foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.loadPorts() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.ports) { p in
                        HStack(spacing: 14) {
                            Text(":\(p.port)").font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(ModuleTheme.developer.accent).frame(width: 80, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.process).font(.subheadline.weight(.semibold))
                                Text("pid \(p.pid) · \(p.address)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { model.kill(port: p) } label: { Label("Kill", systemImage: "xmark.octagon") }.buttonStyle(SecondaryButtonStyle())
                        }
                        .padding(12)
                        .glassCard(radius: 12)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
        .task { model.loadPorts() }
    }
}
