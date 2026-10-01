import SwiftUI
import AppKit
import CleanCore

/// Scan results as a radial map: the scope in the middle, one bubble per
/// module sized by what it found, categories fanning out when a module is
/// opened, and the item list in a side panel when a category is picked.
/// Smart Care also gets Projects and Dev Stack bubbles.
struct ResultGraphView: View {
    @Environment(AppModel.self) private var model
    let scope: SidebarItem
    @State private var expanded: String? = nil
    @State private var picked: GNode? = nil
    @State private var hovered: String? = nil

    struct GNode: Identifiable, Equatable {
        enum Kind: Equatable { case root, module(String), category(ScanCategory), projects, projectStatus(ProjectStatus), devStack, devGroup(DevStackItem.Group) }
        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let bytes: UInt64
        let parent: String?
        let symbol: String
        let tint: Color
        let review: Bool
    }

    // MARK: Nodes

    private var modules: [ModuleScanResult] { model.results(scope) }

    private var nodes: [GNode] {
        var out: [GNode] = []
        let total = model.totalBytes(scope)
        out.append(GNode(id: "root", kind: .root, title: scope.title, subtitle: ByteFormatter.string(total), bytes: total, parent: nil, symbol: scope.symbol, tint: scope.theme.accent, review: false))
        for m in modules {
            let tint = Self.tint(forModule: m.moduleID)
            out.append(GNode(id: m.moduleID, kind: .module(m.moduleID), title: m.moduleName, subtitle: m.formattedSize, bytes: m.totalSize, parent: "root",
                             symbol: Self.symbol(forModule: m.moduleID), tint: tint, review: m.categories.allSatisfy { !$0.autoSelect }))
            if expanded == m.moduleID {
                for c in m.categories {
                    out.append(GNode(id: "cat:\(c.category.rawValue)", kind: .category(c.category), title: c.category.displayName, subtitle: "\(c.items.count) · \(c.formattedSize)",
                                     bytes: c.totalSize, parent: m.moduleID, symbol: c.category.systemImage, tint: tint, review: !c.autoSelect))
                }
            }
        }
        if scope == .smartCare {
            let cleanable = model.projects.filter { $0.decision.status.allowsCleaning }.reduce(0) { $0 + $1.project.totalArtifactBytes }
            let protectedCount = model.projects.filter { !$0.decision.status.allowsCleaning && !$0.project.artifacts.isEmpty }.count
            out.append(GNode(id: "projects", kind: .projects, title: "Projects", subtitle: "\(model.projects.count) found · \(protectedCount) protected", bytes: cleanable, parent: "root",
                             symbol: "folder.badge.gearshape", tint: ModuleTheme.developer.accent, review: true))
            if expanded == "projects" {
                for status in ProjectStatus.allCases {
                    let group = model.projects.filter { $0.decision.status == status }
                    guard !group.isEmpty else { continue }
                    out.append(GNode(id: "ps:\(status.rawValue)", kind: .projectStatus(status), title: status.displayName, subtitle: "\(group.count) · \(ByteFormatter.string(group.reduce(0) { $0 + $1.project.totalArtifactBytes }))",
                                     bytes: group.reduce(0) { $0 + $1.project.totalArtifactBytes }, parent: "projects", symbol: status.systemImage, tint: status.tint, review: true))
                }
            }
            let stackBytes = model.devStack.reduce(0) { $0 + $1.bytes }
            out.append(GNode(id: "devstack", kind: .devStack, title: "Dev Stack", subtitle: model.devStack.isEmpty ? "tap to inventory" : "\(model.devStack.count) items · \(ByteFormatter.string(stackBytes))",
                             bytes: stackBytes, parent: "root", symbol: "cylinder.split.1x2", tint: ModuleTheme.files.accent, review: true))
            if expanded == "devstack" {
                for g in DevStackItem.Group.allCases {
                    let items = model.devStack.filter { $0.group == g }
                    guard !items.isEmpty else { continue }
                    let b = items.reduce(0) { $0 + $1.bytes }
                    out.append(GNode(id: "dg:\(g.rawValue)", kind: .devGroup(g), title: g.displayName, subtitle: "\(items.count) · \(ByteFormatter.string(b))", bytes: b, parent: "devstack",
                                     symbol: g.systemImage, tint: ModuleTheme.files.accent, review: true))
                }
            }
        }
        return out
    }

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

    // MARK: Layout

    struct Placed { var point: CGPoint; var radius: CGFloat }

    private func layout(_ nodes: [GNode], in size: CGSize) -> [String: Placed] {
        var out: [String: Placed] = [:]
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ring1 = min(size.width, size.height) * 0.30
        let maxBytes = max(nodes.filter { $0.parent == "root" }.map(\.bytes).max() ?? 1, 1)
        func radius(_ b: UInt64, base: CGFloat, span: CGFloat) -> CGFloat { base + span * CGFloat(sqrt(Double(b) / Double(maxBytes))) }
        out["root"] = Placed(point: center, radius: 48)
        let first = nodes.filter { $0.parent == "root" }
        for (i, n) in first.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * (2 * .pi / CGFloat(max(first.count, 1)))
            let push: CGFloat = expanded == n.id ? 1.18 : 1
            let p = CGPoint(x: center.x + cos(angle) * ring1 * push, y: center.y + sin(angle) * ring1 * push)
            out[n.id] = Placed(point: p, radius: radius(n.bytes, base: 30, span: 30))
            let kids = nodes.filter { $0.parent == n.id }
            guard !kids.isEmpty else { continue }
            let spread = min(CGFloat.pi * 0.9, CGFloat(kids.count) * 0.42)
            let kidMax = max(kids.map(\.bytes).max() ?? 1, 1)
            for (j, k) in kids.enumerated() {
                let t = kids.count == 1 ? 0.5 : CGFloat(j) / CGFloat(kids.count - 1)
                let a = angle - spread / 2 + spread * t
                let dist: CGFloat = 118 + (kids.count > 6 ? CGFloat(j % 2) * 34 : 0)
                let p2 = CGPoint(x: p.x + cos(a) * dist, y: p.y + sin(a) * dist)
                let r = 18 + 14 * CGFloat(sqrt(Double(k.bytes) / Double(kidMax)))
                out[k.id] = Placed(point: p2, radius: r)
            }
        }
        return out
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 14) {
            GeometryReader { geo in
                let ns = nodes
                let placed = layout(ns, in: geo.size)
                ZStack {
                    Canvas { ctx, _ in
                        for n in ns {
                            guard let parent = n.parent, let a = placed[parent], let b = placed[n.id] else { continue }
                            var path = Path()
                            path.move(to: a.point)
                            let mid = CGPoint(x: (a.point.x + b.point.x) / 2, y: (a.point.y + b.point.y) / 2)
                            path.addQuadCurve(to: b.point, control: CGPoint(x: mid.x + (a.point.y - b.point.y) * 0.08, y: mid.y + (b.point.x - a.point.x) * 0.08))
                            let w = 1 + 4 * CGFloat(sqrt(Double(n.bytes) / Double(max(ns.first(where: { $0.id == "root" })?.bytes ?? 1, 1))))
                            ctx.stroke(path, with: .color(n.tint.opacity(hovered == n.id ? 0.9 : 0.35)), style: StrokeStyle(lineWidth: w, lineCap: .round))
                        }
                    }
                    ForEach(ns) { n in
                        if let p = placed[n.id] {
                            nodeView(n, radius: p.radius)
                                .position(p.point)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                                .zIndex(n.parent == nil ? 3 : n.parent == "root" ? 2 : 1)
                        }
                    }
                }
                .animation(.spring(duration: 0.6, bounce: 0.18), value: expanded)
                .animation(.spring(duration: 0.5), value: ns.map(\.id))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { expanded = nil; picked = nil } }
            }
            .glassCard(radius: 22)
            if let p = picked { sidePanel(p).frame(width: 340).transition(.move(edge: .trailing).combined(with: .opacity)) }
        }
        .animation(.spring(duration: 0.45), value: picked?.id)
    }

    private func selectedFraction(_ n: GNode) -> Double {
        switch n.kind {
        case .category(let c):
            guard let cat = modules.flatMap(\.categories).first(where: { $0.category == c }), cat.totalSize > 0 else { return 0 }
            let sel = model.selection(scope)
            return Double(cat.items.filter { sel.contains($0.url) }.reduce(0) { $0 + $1.size }) / Double(cat.totalSize)
        case .module(let id):
            guard let m = modules.first(where: { $0.moduleID == id }), m.totalSize > 0 else { return 0 }
            return Double(m.categories.selectedSize(model.selection(scope))) / Double(m.totalSize)
        case .root:
            return model.totalBytes(scope) > 0 ? Double(model.selectedBytes(scope)) / Double(model.totalBytes(scope)) : 0
        default: return 0
        }
    }

    private func toggle(_ n: GNode) {
        switch n.kind {
        case .category(let c):
            if let cat = modules.flatMap(\.categories).first(where: { $0.category == c }) {
                model.setCategory(cat, selected: !model.isCategoryFullySelected(cat, in: scope), in: scope)
            }
        case .module(let id):
            if let m = modules.first(where: { $0.moduleID == id }) {
                let all = m.categories.allSatisfy { model.isCategoryFullySelected($0, in: scope) }
                m.categories.forEach { model.setCategory($0, selected: !all, in: scope) }
            }
        default: break
        }
        SoundFX.tap()
    }

    @ViewBuilder
    private func nodeView(_ n: GNode, radius: CGFloat) -> some View {
        let frac = selectedFraction(n)
        let isHover = hovered == n.id
        let isPicked = picked?.id == n.id
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(n.tint.opacity(isPicked ? 0.55 : 0.28))
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                if frac > 0 {
                    Circle().trim(from: 0, to: frac).stroke(n.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: frac)
                }
                Image(systemName: n.symbol).font(.system(size: max(12, radius * 0.5), weight: .semibold)).foregroundStyle(.white)
                if n.review && frac == 0 {
                    Image(systemName: "eye.fill").font(.system(size: 9)).foregroundStyle(.orange)
                        .padding(3).background(Color.black.opacity(0.5), in: Circle())
                        .offset(x: radius * 0.65, y: -radius * 0.65)
                }
            }
            .frame(width: radius * 2, height: radius * 2)
            .glassEffect(.regular.tint(n.tint.opacity(0.35)).interactive(), in: .circle)
            .scaleEffect(isHover ? 1.08 : 1)
            .shadow(color: n.tint.opacity(isHover || isPicked ? 0.6 : 0.25), radius: isHover ? 20 : 10)
            .onHover { hovered = $0 ? n.id : (hovered == n.id ? nil : hovered) }
            .onTapGesture { tap(n) }
            .contextMenu {
                if case .category = n.kind { Button("Toggle selection") { toggle(n) } }
                if case .module = n.kind { Button("Toggle selection") { toggle(n) } }
            }
            if radius >= 18 || isHover {
                VStack(spacing: 1) {
                    Text(n.title).font(.system(size: n.parent == nil ? 14 : 11, weight: .semibold)).lineLimit(1)
                    Text(n.subtitle).font(.system(size: 10, design: .rounded)).foregroundStyle(.white.opacity(0.75)).monospacedDigit().lineLimit(1)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.black.opacity(0.25), in: Capsule())
                .fixedSize()
            }
        }
        .animation(.spring(duration: 0.3), value: isHover)
    }

    private func tap(_ n: GNode) {
        withAnimation(.spring(duration: 0.55, bounce: 0.2)) {
            switch n.kind {
            case .root: expanded = nil; picked = nil
            case .module(let id): expanded = expanded == id ? nil : id; picked = nil
            case .category: picked = picked?.id == n.id ? nil : n
            case .projects: expanded = expanded == "projects" ? nil : "projects"; picked = nil; if model.projects.isEmpty { model.refreshProjects() }
            case .projectStatus: picked = n
            case .devStack: expanded = expanded == "devstack" ? nil : "devstack"; picked = nil; if model.devStack.isEmpty { model.loadDevStack() }
            case .devGroup: picked = n
            }
        }
        SoundFX.tap()
    }

    // MARK: Side panel

    @ViewBuilder
    private func sidePanel(_ n: GNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: n.symbol).foregroundStyle(n.tint)
                Text(n.title).font(.headline)
                Spacer()
                Button { withAnimation { picked = nil } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            Text(n.subtitle).font(.caption).foregroundStyle(.secondary)
            switch n.kind {
            case .category(let c):
                if let cat = modules.flatMap(\.categories).first(where: { $0.category == c }) {
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
            case .projectStatus(let status):
                let entries = model.projects.filter { $0.decision.status == status }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(entries) { ProjectChipCard(entry: $0) }
                    }
                }
                Button("Open Projects") { model.selection = .projects }.buttonStyle(PrimaryButtonStyle(tint: ModuleTheme.developer.accent))
            case .devGroup(let g):
                let items = model.devStack.filter { $0.group == g }.sorted { $0.bytes > $1.bytes }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items.prefix(40)) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).font(.caption.weight(.semibold)).lineLimit(1)
                                    Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(item.formattedSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(8).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Button("Open Dev Stack") { model.selection = .devStack }.buttonStyle(PrimaryButtonStyle(tint: ModuleTheme.files.accent))
            default: EmptyView()
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }
}
