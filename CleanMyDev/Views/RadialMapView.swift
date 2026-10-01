import SwiftUI
import CleanCore

/// One map language for the whole app: a root in the middle, first-level
/// bubbles on a ring sized by bytes, second-level bubbles fanning out of the
/// opened one, and a side panel for whatever is picked. Smart Care, Projects
/// and Dev Stack all feed this with their own trees.
struct MapNode: Identifiable, Equatable {
    enum Payload: Equatable {
        case none
        case module(String), category(ScanCategory)
        case projectStatus(ProjectStatus), project(String)
        case devGroup(DevStackItem.Group), devItem(String)
        case link(SidebarItem)
        case more(Int)
    }
    let id: String
    let title: String
    let subtitle: String
    let bytes: UInt64
    let symbol: String
    let tint: Color
    var review = false
    var payload: Payload = .none
    var children: [MapNode] = []
    var hasChildren: Bool { !children.isEmpty }
}

struct RadialMapView<Panel: View>: View {
    let root: MapNode
    /// Fraction of a node that is currently selected (ring around the bubble).
    var selectedFraction: (MapNode) -> Double = { _ in 0 }
    /// Toggle selection (context menu) for nodes that support it.
    var onToggle: ((MapNode) -> Void)? = nil
    /// What to show in the side panel for a picked node.
    @ViewBuilder var panel: (MapNode) -> Panel

    @State private var expanded: String? = nil
    @State private var picked: MapNode? = nil
    @State private var hovered: String? = nil
    private let maxFan = 14

    private var visible: [(MapNode, String?)] {
        var out: [(MapNode, String?)] = [(root, nil)]
        for c in root.children {
            out.append((c, root.id))
            if expanded == c.id {
                let kids = c.children.sorted { $0.bytes > $1.bytes }
                let shown = kids.prefix(maxFan)
                for k in shown { out.append((k, c.id)) }
                if kids.count > shown.count {
                    let rest = kids.dropFirst(shown.count)
                    out.append((MapNode(id: "\(c.id):more", title: "+\(rest.count) more", subtitle: ByteFormatter.string(rest.reduce(0) { $0 + $1.bytes }),
                                        bytes: rest.reduce(0) { $0 + $1.bytes }, symbol: "ellipsis", tint: c.tint, payload: .more(rest.count), children: Array(rest)), c.id))
                }
            }
        }
        return out
    }

    struct Placed { var point: CGPoint; var radius: CGFloat }

    private func layout(_ items: [(MapNode, String?)], in size: CGSize) -> [String: Placed] {
        var out: [String: Placed] = [:]
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ring = min(size.width, size.height) * 0.31
        let first = items.filter { $0.1 == root.id }.map(\.0)
        let maxBytes = max(first.map(\.bytes).max() ?? 1, 1)
        out[root.id] = Placed(point: center, radius: 46)
        for (i, n) in first.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * (2 * .pi / CGFloat(max(first.count, 1)))
            let push: CGFloat = expanded == n.id ? 1.16 : 1
            let p = CGPoint(x: center.x + cos(angle) * ring * push, y: center.y + sin(angle) * ring * push)
            out[n.id] = Placed(point: p, radius: 28 + 30 * CGFloat(sqrt(Double(n.bytes) / Double(maxBytes))))
            let kids = items.filter { $0.1 == n.id }.map(\.0)
            guard !kids.isEmpty else { continue }
            let kidMax = max(kids.map(\.bytes).max() ?? 1, 1)
            let spread = min(CGFloat.pi * 1.1, CGFloat(kids.count) * 0.38)
            // Fan toward whichever side has room: outward by default, but when the
            // ring node sits near an edge the arc is rotated back toward the centre.
            let roomOut = min(size.width - p.x, p.x, size.height - p.y, p.y)
            let baseAngle = roomOut < 190 ? angle + .pi : angle
            for (j, k) in kids.enumerated() {
                let t = kids.count == 1 ? 0.5 : CGFloat(j) / CGFloat(kids.count - 1)
                let a = baseAngle - spread / 2 + spread * t
                let dist: CGFloat = 120 + (kids.count > 7 ? CGFloat(j % 2) * 58 : 0)
                let r = 16 + 16 * CGFloat(sqrt(Double(k.bytes) / Double(kidMax)))
                var x = p.x + cos(a) * dist, y = p.y + sin(a) * dist
                x = min(max(x, r + 10), size.width - r - 10)
                y = min(max(y, r + 10), size.height - r - 34)
                out[k.id] = Placed(point: CGPoint(x: x, y: y), radius: r)
            }
        }
        return out
    }

    var body: some View {
        HStack(spacing: 14) {
            GeometryReader { geo in
                let items = visible
                let placed = layout(items, in: geo.size)
                ZStack {
                    Canvas { ctx, _ in
                        for (n, parent) in items {
                            guard let parent, let a = placed[parent], let b = placed[n.id] else { continue }
                            var path = Path()
                            path.move(to: a.point)
                            let mid = CGPoint(x: (a.point.x + b.point.x) / 2, y: (a.point.y + b.point.y) / 2)
                            path.addQuadCurve(to: b.point, control: CGPoint(x: mid.x + (a.point.y - b.point.y) * 0.08, y: mid.y + (b.point.x - a.point.x) * 0.08))
                            let w = 1 + 4 * CGFloat(sqrt(Double(n.bytes) / Double(max(root.bytes, 1))))
                            ctx.stroke(path, with: .color(n.tint.opacity(hovered == n.id ? 0.9 : 0.35)), style: StrokeStyle(lineWidth: w, lineCap: .round))
                        }
                    }
                    ForEach(items, id: \.0.id) { n, parent in
                        if let p = placed[n.id] {
                            bubble(n, radius: p.radius, level: parent == nil ? 0 : parent == root.id ? 1 : 2)
                                .position(p.point)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                                .zIndex(parent == nil ? 3 : parent == root.id ? 2 : 1)
                        }
                    }
                }
                .animation(.spring(duration: 0.6, bounce: 0.18), value: expanded)
                .animation(.spring(duration: 0.5), value: items.map(\.0.id))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { expanded = nil; picked = nil } }
            }
            .glassCard(radius: 22)
            if let p = picked {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: p.symbol).foregroundStyle(p.tint)
                        Text(p.title).font(.headline).lineLimit(1)
                        Spacer()
                        Button { withAnimation { picked = nil } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                    Text(p.subtitle).font(.caption).foregroundStyle(.secondary)
                    panel(p)
                }
                .padding(14)
                .frame(width: 350)
                .glassCard(radius: 18)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45), value: picked?.id)
        .onChange(of: root.id) { _, _ in expanded = nil; picked = nil }
    }

    private func bubble(_ n: MapNode, radius: CGFloat, level: Int) -> some View {
        let frac = selectedFraction(n)
        let isHover = hovered == n.id
        let isPicked = picked?.id == n.id
        return VStack(spacing: 6) {
            ZStack {
                Circle().fill(n.tint.opacity(isPicked ? 0.55 : 0.28))
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                if frac > 0 {
                    Circle().trim(from: 0, to: frac).stroke(n.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: frac)
                }
                Image(systemName: n.symbol).font(.system(size: max(11, radius * 0.5), weight: .semibold)).foregroundStyle(.white)
                if n.review && frac == 0 && level > 0 && !n.hasChildren {
                    Image(systemName: "eye.fill").font(.system(size: 9)).foregroundStyle(.orange)
                        .padding(3).background(Color.black.opacity(0.5), in: Circle())
                        .offset(x: radius * 0.65, y: -radius * 0.65)
                }
                if level == 1 && n.hasChildren {
                    Text("\(n.children.count)").font(.system(size: 9, weight: .bold)).foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 5).padding(.vertical, 1).background(n.tint, in: Capsule())
                        .offset(x: radius * 0.6, y: radius * 0.6)
                }
            }
            .frame(width: radius * 2, height: radius * 2)
            .glassEffect(.regular.tint(n.tint.opacity(0.35)).interactive(), in: .circle)
            .scaleEffect(isHover ? 1.08 : 1)
            .shadow(color: n.tint.opacity(isHover || isPicked ? 0.6 : 0.25), radius: isHover ? 20 : 10)
            .onHover { hovered = $0 ? n.id : (hovered == n.id ? nil : hovered) }
            .onTapGesture { tap(n, level: level) }
            .contextMenu {
                if let onToggle, level > 0, case .more = n.payload {} else if let onToggle, level > 0 {
                    Button("Toggle selection") { onToggle(n) }
                }
            }
            if (level < 2 && radius >= 17) || radius >= 21 || isHover {
                VStack(spacing: 1) {
                    Text(n.title).font(.system(size: level == 0 ? 14 : 11, weight: .semibold)).lineLimit(1).frame(maxWidth: 150)
                    Text(n.subtitle).font(.system(size: 10, design: .rounded)).foregroundStyle(.white.opacity(0.75)).monospacedDigit().lineLimit(1).frame(maxWidth: 170)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.black.opacity(0.25), in: Capsule())
                .fixedSize()
            }
        }
        .animation(.spring(duration: 0.3), value: isHover)
    }

    private func tap(_ n: MapNode, level: Int) {
        withAnimation(.spring(duration: 0.55, bounce: 0.2)) {
            switch level {
            case 0: expanded = nil; picked = nil
            case 1:
                if n.hasChildren { expanded = expanded == n.id ? nil : n.id; picked = nil } else { picked = picked?.id == n.id ? nil : n }
            default: picked = picked?.id == n.id ? nil : n
            }
        }
        SoundFX.tap()
    }
}
