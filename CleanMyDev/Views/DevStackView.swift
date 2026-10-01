import SwiftUI
import AppKit
import CleanCore

struct DevStackView: View {
    @Environment(AppModel.self) private var model
    @State private var group: DevStackItem.Group? = nil
    @State private var search = ""
    @State private var toQuarantine: DevStackItem?
    @State private var tab = 0
    @State private var showMap = true
    @State private var picked: String? = nil

    private var rows: [DevStackItem] {
        model.devStack
            .filter { group == nil || $0.group == group }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)
            if tab == 1 {
                PortsView()
            } else if model.devStackLoading && model.devStack.isEmpty {
                LiveWorkView(title: "Looking at what's installed", subtitle: "Homebrew, version managers, global packages, database engines, SDKs, VM disks.", tint: ModuleTheme.files.accent)
            } else if model.devStack.isEmpty {
                Spacer(); Text("Nothing found yet").foregroundStyle(.secondary); Spacer()
            } else if showMap {
                groupChips.padding(.horizontal, 28).padding(.bottom, 10)
                RadialMapView(root: DevStackMap.root(model, items: rows.filter { $0.bytes > 0 })) { n in DevStackMap.panel(model, n) }
                    .padding(.horizontal, 28).padding(.bottom, 24)
            } else {
                groupChips.padding(.horizontal, 28).padding(.bottom, 10)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(DevStackItem.Group.allCases, id: \.self) { g in
                            let items = rows.filter { $0.group == g }
                            if !items.isEmpty {
                                HStack {
                                    Image(systemName: g.systemImage).foregroundStyle(ModuleTheme.developer.accent)
                                    SectionLabel(text: g.displayName)
                                    Spacer()
                                    Text(ByteFormatter.string(items.reduce(0) { $0 + $1.bytes })).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                .padding(.top, 10)
                                ForEach(items) { row($0) }
                            }
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 30)
                }
            }
        }
        .task { if model.devStack.isEmpty { model.loadDevStack() } }
        .confirmationDialog("Move \(toQuarantine?.name ?? "") to quarantine?", isPresented: Binding(get: { toQuarantine != nil }, set: { if !$0 { toQuarantine = nil } })) {
            Button("Quarantine \(toQuarantine?.formattedSize ?? "")", role: .destructive) {
                if let t = toQuarantine { Task { _ = await model.quarantine(paths: [URL(filePath: t.path)], label: "Dev Stack · \(t.name)"); model.loadDevStack() } }
            }
        } message: { Text("It can be restored from Quarantine for \(model.settings.quarantineRetentionDays) days.") }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dev Stack").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Everything installed for development: databases and where their data is, runtimes, global tools, SDKs, VM disks. Discovered, not configured.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $tab) { Text("Stack").tag(0); Text("Ports").tag(1) }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
            Picker("", selection: $showMap) {
                Image(systemName: "circle.hexagongrid").tag(true)
                Image(systemName: "list.bullet").tag(false)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 90)
            TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 160)
            Button { model.loadDevStack() } label: {
                if model.devStackLoading { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
            }.buttonStyle(SecondaryButtonStyle()).disabled(model.devStackLoading)
        }
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "All", model.devStack.count)
                ForEach(DevStackItem.Group.allCases, id: \.self) { g in
                    let n = model.devStack.filter { $0.group == g }.count
                    if n > 0 { chip(g, g.displayName, n) }
                }
            }
        }
    }

    private func chip(_ g: DevStackItem.Group?, _ label: String, _ n: Int) -> some View {
        Button { group = g } label: {
            Text("\(label) \(n)").font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.white.opacity(group == g ? 0.22 : 0.08), in: Capsule())
                .foregroundStyle(group == g ? ModuleTheme.developer.accent : .white.opacity(0.8))
        }.buttonStyle(.plain)
    }

    private func row(_ item: DevStackItem) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name).font(.subheadline.weight(.semibold))
                    statusChip(item.status)
                }
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !item.path.hasPrefix("docker://") {
                    Text(item.path.replacingOccurrences(of: CMConstants.homePath, with: "~")).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
                if let h = item.hint { Text(h).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if item.bytes > 0 { SizeText(bytes: item.bytes) }
                if let m = item.modified { Text("modified \(m.relativeDescription)").font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(width: 130, alignment: .trailing)
            action(item)
        }
        .padding(12)
        .glassCard(radius: 12)
    }

    @ViewBuilder
    private func action(_ item: DevStackItem) -> some View {
        HStack(spacing: 6) {
            if !item.path.hasPrefix("docker://") && item.path != "?" {
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: item.path)]) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Reveal in Finder")
            }
            switch item.removal {
            case .quarantinePath:
                Button { toQuarantine = item } label: { Image(systemName: "archivebox") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Move to quarantine")
            case .command(let cmd):
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                } label: { Image(systemName: "doc.on.clipboard") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Copy: \(cmd)")
            case .never:
                Image(systemName: "lock").foregroundStyle(.tertiary).help("Data. CleanMyDev never deletes this.")
            }
        }
        .frame(width: 50)
    }

    static func tintFor(_ g: DevStackItem.Group) -> Color { DevStackMap.tint(g) }

    static func tint(_ g: DevStackItem.Group) -> Color {
        switch g {
        case .databases: Color(hex: 0x2DD4BF)
        case .services: Color(hex: 0x5EEAD4)
        case .toolchains: Color(hex: 0x22D3EE)
        case .globalTools: Color(hex: 0x67E8F9)
        case .sdks: Color(hex: 0x34D399)
        case .vms: Color(hex: 0xF59E0B)
        case .packageManagers: Color(hex: 0x94A3B8)
        }
    }

    private func statusChip(_ s: DevStackItem.Status) -> some View {
        let tint: Color = switch s {
        case .running: .green
        case .stopped: .secondary
        case .installed: .secondary
        case .current: .cyan
        case .notDefault: .orange
        }
        return Text(s.rawValue).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule()).foregroundStyle(tint)
    }
}


/// Side-panel card for one Dev Stack item: path, hint, and the same actions as the list row.
struct DevStackItemCard: View {
    @Environment(AppModel.self) private var model
    let item: DevStackItem
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.detail).font(.caption).foregroundStyle(.secondary)
            if !item.path.hasPrefix("docker://") {
                Text(item.path.replacingOccurrences(of: CMConstants.homePath, with: "~")).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(3)
            }
            HStack {
                if item.bytes > 0 { SizeText(bytes: item.bytes, font: .title3.weight(.bold)) }
                Spacer()
                if let m = item.modified { Text("modified \(m.relativeDescription)").font(.caption2).foregroundStyle(.secondary) }
            }
            if let h = item.hint { Text(h).font(.caption).foregroundStyle(.orange) }
            HStack(spacing: 8) {
                if !item.path.hasPrefix("docker://") && item.path != "?" {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: item.path)]) } label: { Label("Reveal", systemImage: "magnifyingglass") }.buttonStyle(SecondaryButtonStyle())
                }
                switch item.removal {
                case .quarantinePath:
                    Button { confirm = true } label: { Label("Quarantine", systemImage: "archivebox") }.buttonStyle(SecondaryButtonStyle())
                case .command(let cmd):
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cmd, forType: .string)
                    } label: { Label("Copy uninstall command", systemImage: "doc.on.clipboard") }.buttonStyle(SecondaryButtonStyle())
                case .never:
                    Label("Data, never deleted by CleanMyDev", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .confirmationDialog("Move \(item.name) to quarantine?", isPresented: $confirm) {
            Button("Quarantine \(item.formattedSize)", role: .destructive) {
                Task { _ = await model.quarantine(paths: [URL(filePath: item.path)], label: "Dev Stack · \(item.name)"); model.loadDevStack() }
            }
        }
    }
}
