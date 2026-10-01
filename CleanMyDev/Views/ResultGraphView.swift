import SwiftUI
import AppKit
import CleanCore

/// Smart Care / module results on the shared radial map.
struct ResultGraphView: View {
    @Environment(AppModel.self) private var model
    let scope: SidebarItem

    private var modules: [ModuleScanResult] { model.results(scope) }

    static func tint(forModule id: String) -> Color {
        switch id {
        case "system_junk", "trash": ModuleTheme.cleanup.accent
        case "dev_junk", "docker", "simulators": ModuleTheme.developer.accent
        case "privacy", "malware": ModuleTheme.protection.accent
        case "large_files": ModuleTheme.files.accent
        default: ModuleTheme.brand
        }
    }

    static func symbol(forModule id: String) -> String {
        switch id {
        case "system_junk": "trash.circle"
        case "trash": "trash"
        case "dev_junk": "shippingbox"
        case "docker": "cube.transparent"
        case "simulators": "iphone.gen3"
        case "privacy": "safari"
        case "malware": "shield.lefthalf.filled"
        case "large_files": "doc.richtext"
        default: "circle"
        }
    }

    private var root: MapNode {
        var children: [MapNode] = modules.map { m in
            let tint = Self.tint(forModule: m.moduleID)
            return MapNode(id: m.moduleID, title: m.moduleName, subtitle: m.formattedSize, bytes: m.totalSize, symbol: Self.symbol(forModule: m.moduleID), tint: tint,
                           review: m.categories.allSatisfy { !$0.autoSelect }, payload: .module(m.moduleID),
                           children: m.categories.map { c in
                               MapNode(id: "cat:\(c.category.rawValue)", title: c.category.displayName, subtitle: "\(c.items.count) · \(c.formattedSize)", bytes: c.totalSize,
                                       symbol: c.category.systemImage, tint: tint, review: !c.autoSelect, payload: .category(c.category))
                           })
        }
        if scope == .smartCare {
            children.append(ProjectsMap.node(model))
            children.append(DevStackMap.node(model))
        }
        return MapNode(id: "root:\(scope.rawValue)", title: scope.title, subtitle: ByteFormatter.string(model.totalBytes(scope)), bytes: model.totalBytes(scope),
                       symbol: scope.symbol, tint: scope.theme.accent, children: children)
    }

    private func category(_ c: ScanCategory) -> ScanResult? { modules.flatMap(\.categories).first { $0.category == c } }

    private func fraction(_ n: MapNode) -> Double {
        switch n.payload {
        case .category(let c):
            guard let cat = category(c), cat.totalSize > 0 else { return 0 }
            let sel = model.selection(scope)
            return Double(cat.items.filter { sel.contains($0.url) }.reduce(0) { $0 + $1.size }) / Double(cat.totalSize)
        case .module(let id):
            guard let m = modules.first(where: { $0.moduleID == id }), m.totalSize > 0 else { return 0 }
            return Double(m.categories.selectedSize(model.selection(scope))) / Double(m.totalSize)
        case .none where n.id.hasPrefix("root:"):
            return model.totalBytes(scope) > 0 ? Double(model.selectedBytes(scope)) / Double(model.totalBytes(scope)) : 0
        default: return 0
        }
    }

    private func toggle(_ n: MapNode) {
        switch n.payload {
        case .category(let c):
            if let cat = category(c) { model.setCategory(cat, selected: !model.isCategoryFullySelected(cat, in: scope), in: scope) }
        case .module(let id):
            if let m = modules.first(where: { $0.moduleID == id }) {
                let all = m.categories.allSatisfy { model.isCategoryFullySelected($0, in: scope) }
                m.categories.forEach { model.setCategory($0, selected: !all, in: scope) }
            }
        default: break
        }
    }

    var body: some View {
        RadialMapView(root: root, selectedFraction: fraction, onToggle: toggle, isSelectable: { n in
            switch n.payload { case .module, .category: true; default: false }
        }) { n in
            switch n.payload {
            case .category(let c):
                if let cat = category(c) {
                    Text(cat.category.subtitle).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(model.isCategoryFullySelected(cat, in: scope) ? "Deselect all" : "Select all") { toggle(n) }.buttonStyle(SecondaryButtonStyle()).controlSize(.small)
                        Spacer()
                        if !cat.autoSelect { StatusChip(text: "Review", systemImage: "eye", tint: .orange) }
                    }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(cat.items.prefix(300)) { item in
                                ItemRow(scope: scope, item: item)
                                Divider().opacity(0.12)
                            }
                            if cat.items.count > 300 { Text("…and \(cat.items.count - 300) more").font(.caption).foregroundStyle(.secondary).padding(8) }
                        }
                    }
                }
            case .projectStatus, .project:
                ProjectsMap.panel(model, n)
            case .devGroup, .devItem:
                DevStackMap.panel(model, n)
            case .more(let count):
                Text("\(count) smaller items. Switch to the list view to see them all.").font(.caption).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }
}

/// Projects as a map: statuses on the ring, projects fanning out of each.
enum ProjectsMap {
    static func node(_ model: AppModel) -> MapNode {
        let cleanable = model.projects.filter { $0.decision.status.allowsCleaning }.reduce(0) { $0 + $1.project.totalArtifactBytes }
        let protectedCount = model.projects.filter { !$0.decision.status.allowsCleaning && !$0.project.artifacts.isEmpty }.count
        return MapNode(id: "projects", title: "Projects", subtitle: model.projects.isEmpty ? "finding…" : "\(model.projects.count) · \(protectedCount) protected",
                       bytes: max(cleanable, 1), symbol: "folder.badge.gearshape", tint: ModuleTheme.developer.accent, review: true, payload: .link(.projects),
                       children: statusNodes(model))
    }

    static func statusNodes(_ model: AppModel) -> [MapNode] {
        ProjectStatus.allCases.compactMap { status in
            let group = model.projects.filter { $0.decision.status == status }
            guard !group.isEmpty else { return nil }
            let bytes = group.reduce(0) { $0 + $1.project.totalArtifactBytes }
            return MapNode(id: "ps:\(status.rawValue)", title: status.displayName, subtitle: "\(group.count) · \(ByteFormatter.string(bytes))", bytes: max(bytes, 1),
                           symbol: status.systemImage, tint: status.tint, review: false, payload: .projectStatus(status),
                           children: group.map { e in
                               MapNode(id: "p:\(e.id)", title: e.project.name, subtitle: e.project.formattedArtifactSize, bytes: max(e.project.totalArtifactBytes, 1),
                                       symbol: e.project.kinds.first?.symbol ?? "folder", tint: status.tint, review: !status.allowsCleaning, payload: .project(e.id))
                           }, fanOut: false)
        }
    }

    /// Root for the Projects screen itself: statuses on the ring, projects fanning out.
    static func root(_ model: AppModel, entries: [ProjectScanService.Entry]) -> MapNode {
        let total = entries.reduce(0) { $0 + $1.project.totalArtifactBytes }
        let groups = ProjectStatus.allCases.compactMap { status -> MapNode? in
            let group = entries.filter { $0.decision.status == status }
            guard !group.isEmpty else { return nil }
            let bytes = group.reduce(0) { $0 + $1.project.totalArtifactBytes }
            return MapNode(id: "ps:\(status.rawValue)", title: status.displayName, subtitle: "\(group.count) · \(ByteFormatter.string(bytes))", bytes: max(bytes, 1),
                           symbol: status.systemImage, tint: status.tint, review: false, payload: .projectStatus(status),
                           children: group.map { e in
                               MapNode(id: "p:\(e.id)", title: e.project.name, subtitle: e.project.formattedArtifactSize, bytes: max(e.project.totalArtifactBytes, 1),
                                       symbol: e.project.kinds.first?.symbol ?? "folder", tint: status.tint, review: !status.allowsCleaning, payload: .project(e.id))
                           }, fanOut: false)
        }
        return MapNode(id: "root:projects", title: "Projects", subtitle: "\(entries.count) · \(ByteFormatter.string(total))", bytes: total,
                       symbol: "folder.badge.gearshape", tint: ModuleTheme.developer.accent, children: groups)
    }

    @ViewBuilder
    static func panel(_ model: AppModel, _ n: MapNode) -> some View {
        switch n.payload {
        case .projectStatus(let status):
            ProjectGroupPanel(status: status)
        case .project(let id):
            if let e = model.projects.first(where: { $0.id == id }) {
                ProjectDetailCard(entry: e)
            }
        default: EmptyView()
        }
    }
}

/// Members of a status group as a list; click one to slide into its detail.
struct ProjectGroupPanel: View {
    @Environment(AppModel.self) private var model
    let status: ProjectStatus
    @State private var detail: String? = nil

    var body: some View {
        let entries = model.projects.filter { $0.decision.status == status }.sorted { $0.project.totalArtifactBytes > $1.project.totalArtifactBytes }
        ZStack {
            if let id = detail, let e = entries.first(where: { $0.id == id }) ?? model.projects.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { withAnimation(.spring(duration: 0.35)) { detail = nil } } label: { Label(status.displayName, systemImage: "chevron.left").font(.caption.weight(.semibold)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                    Text(e.project.name).font(.headline)
                    ProjectDetailCard(entry: e)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(entries) { e in
                            Button { withAnimation(.spring(duration: 0.35)) { detail = e.id }; SoundFX.tap() } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: e.project.kinds.first?.symbol ?? "folder").foregroundStyle(status.tint).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.project.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(e.decision.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(e.project.formattedArtifactSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onChange(of: status) { _, _ in detail = nil }
    }
}

/// Dev Stack as a map: groups on the ring, items fanning out.
enum DevStackMap {
    static func node(_ model: AppModel) -> MapNode {
        let bytes = model.devStack.reduce(0) { $0 + $1.bytes }
        return MapNode(id: "devstack", title: "Dev Stack", subtitle: model.devStack.isEmpty ? "inventorying…" : "\(model.devStack.count) items · \(ByteFormatter.string(bytes))",
                       bytes: max(bytes, 1), symbol: "cylinder.split.1x2", tint: ModuleTheme.files.accent, review: true, payload: .link(.devStack),
                       children: groupNodes(model, items: model.devStack))
    }

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

    static func groupNodes(_ model: AppModel, items: [DevStackItem]) -> [MapNode] {
        DevStackItem.Group.allCases.compactMap { g in
            let list = items.filter { $0.group == g }
            guard !list.isEmpty else { return nil }
            let b = list.reduce(0) { $0 + $1.bytes }
            return MapNode(id: "dg:\(g.rawValue)", title: g.displayName, subtitle: "\(list.count) · \(ByteFormatter.string(b))", bytes: max(b, 1), symbol: g.systemImage, tint: tint(g),
                           review: false, payload: .devGroup(g),
                           children: list.map { i in
                               MapNode(id: "di:\(i.id)", title: i.name, subtitle: i.formattedSize, bytes: max(i.bytes, 1), symbol: g.systemImage, tint: tint(g),
                                       review: i.removal == .never, payload: .devItem(i.id))
                           }, fanOut: false)
        }
    }

    static func root(_ model: AppModel, items: [DevStackItem]) -> MapNode {
        let bytes = items.reduce(0) { $0 + $1.bytes }
        return MapNode(id: "root:devstack", title: "Dev Stack", subtitle: "\(items.count) items · \(ByteFormatter.string(bytes))", bytes: bytes,
                       symbol: "cylinder.split.1x2", tint: ModuleTheme.files.accent, children: groupNodes(model, items: items))
    }

    @ViewBuilder
    static func panel(_ model: AppModel, _ n: MapNode) -> some View {
        switch n.payload {
        case .devGroup(let g):
            DevGroupPanel(group: g)
        case .devItem(let id):
            if let item = model.devStack.first(where: { $0.id == id }) {
                DevStackItemCard(item: item)
            }
        default: EmptyView()
        }
    }
}


/// Compact project detail for the map's side panel.
struct ProjectDetailCard: View {
    @Environment(AppModel.self) private var model
    let entry: ProjectScanService.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusMenu(entry: entry)
                Spacer()
                Button { NSWorkspace.shared.activateFileViewerSelecting([entry.project.root]) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text(entry.decision.reason).font(.caption).foregroundStyle(entry.decision.status.tint)
            Text(entry.project.kindSummary).font(.caption).foregroundStyle(.secondary)
            Text(entry.project.path.replacingOccurrences(of: CMConstants.homePath, with: "~")).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(3)
            HStack(spacing: 10) {
                if entry.project.signals.runningContainers > 0 { Label("\(entry.project.signals.runningContainers) containers", systemImage: "shippingbox").font(.caption2).foregroundStyle(.secondary) }
                if entry.project.signals.devServerRunning { Label("dev server", systemImage: "bolt.horizontal").font(.caption2).foregroundStyle(.secondary) }
                if entry.project.signals.openInEditor { Label("shell open here", systemImage: "terminal").font(.caption2).foregroundStyle(.secondary) }
            }
            Divider().opacity(0.3)
            SectionLabel(text: "Artifacts · \(entry.project.formattedArtifactSize)")
            if entry.project.artifacts.isEmpty {
                Text("No dependencies or build output on disk.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(entry.project.artifacts) { a in
                        HStack {
                            Image(systemName: a.isDependency ? "cube.box" : "wrench.and.screwdriver").foregroundStyle(.secondary).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.relativePath).font(.caption.monospaced()).lineLimit(1)
                                Text(a.isDependency ? "dependencies" : "build output").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(a.formattedSize).font(.caption.monospacedDigit())
                        }
                        .padding(8).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}


/// Members of a Dev Stack group as a list; click one to slide into its card.
struct DevGroupPanel: View {
    @Environment(AppModel.self) private var model
    let group: DevStackItem.Group
    @State private var detail: String? = nil
    @State private var filter = ""

    var body: some View {
        let items = model.devStack.filter { $0.group == group && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)) }.sorted { $0.bytes > $1.bytes }
        ZStack {
            if let id = detail, let item = model.devStack.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { withAnimation(.spring(duration: 0.35)) { detail = nil } } label: { Label(group.displayName, systemImage: "chevron.left").font(.caption.weight(.semibold)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                    Text(item.name).font(.headline)
                    DevStackItemCard(item: item)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 8) {
                    if model.devStack.filter({ $0.group == group }).count > 12 {
                        TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
                    }
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(items) { item in
                                Button { withAnimation(.spring(duration: 0.35)) { detail = item.id }; SoundFX.tap() } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: group.systemImage).foregroundStyle(DevStackMap.tint(group)).frame(width: 18)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Text(item.formattedSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onChange(of: group) { _, _ in detail = nil }
    }
}
