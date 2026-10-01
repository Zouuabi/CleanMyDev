import SwiftUI
import CleanCore

/// One map language for the whole app: a root in the middle, first-level
/// bubbles on a ring sized by bytes, children fanning out of an opened one
/// (or listed in the side panel when the node asks for that), labels on
/// their own layer so nothing covers them, and a zoomable, pannable canvas
/// that centres on whatever you click.
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
    /// true: children become bubbles around this node. false: clicking the
    /// node opens the side panel, which lists the children.
    var fanOut = true
    var hasChildren: Bool { !children.isEmpty }
}

struct RadialMapView<Panel: View>: View {
    @Environment(AppModel.self) private var model
    let root: MapNode
    var selectedFraction: (MapNode) -> Double = { _ in 0 }
    var onToggle: ((MapNode) -> Void)? = nil
    /// Which nodes carry a selection checkbox (modules and categories in results).
    var isSelectable: (MapNode) -> Bool = { _ in false }
    @ViewBuilder var panel: (MapNode) -> Panel

    @State private var expanded: String? = nil
    @State private var picked: MapNode? = nil
    @State private var hovered: String? = nil
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var gestureZoom: CGFloat = 1
    @State private var gesturePan: CGSize = .zero
    private let maxFan = 12

    // MARK: Tree

    private var visible: [(MapNode, String?)] {
        var out: [(MapNode, String?)] = [(root, nil)]
        for c in root.children {
            out.append((c, root.id))
            if expanded == c.id, c.fanOut {
                let kids = c.children.sorted { $0.bytes > $1.bytes }
                let shown = kids.prefix(maxFan)
                for k in shown { out.append((k, c.id)) }
                if kids.count > shown.count {
                    let rest = Array(kids.dropFirst(shown.count))
                    out.append((MapNode(id: "\(c.id):more", title: "+\(rest.count) more", subtitle: ByteFormatter.string(rest.reduce(0) { $0 + $1.bytes }),
                                        bytes: rest.reduce(0) { $0 + $1.bytes }, symbol: "ellipsis", tint: c.tint, payload: .more(rest.count), children: rest, fanOut: false), c.id))
                }
            }
        }
        return out
    }

    struct Placed { var point: CGPoint; var radius: CGFloat }

    private func layout(_ items: [(MapNode, String?)], in size: CGSize) -> [String: Placed] {
        var out: [String: Placed] = [:]
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ring = min(size.width, size.height) * 0.33
        let first = items.filter { $0.1 == root.id }.map(\.0)
        let maxBytes = max(first.map(\.bytes).max() ?? 1, 1)
        out[root.id] = Placed(point: center, radius: 46)
        for (i, n) in first.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * (2 * .pi / CGFloat(max(first.count, 1)))
            let p = CGPoint(x: center.x + cos(angle) * ring, y: center.y + sin(angle) * ring)
            out[n.id] = Placed(point: p, radius: 26 + 28 * CGFloat(sqrt(Double(n.bytes) / Double(maxBytes))))
            let kids = items.filter { $0.1 == n.id }.map(\.0)
            guard !kids.isEmpty else { continue }
            let kidMax = max(kids.map(\.bytes).max() ?? 1, 1)
            // Children sit on an arc on the far side of the node, away from the root,
            // wide enough that labels don't touch; two rows when crowded.
            let spread = min(CGFloat.pi * 1.15, CGFloat(kids.count) * 0.46)
            for (j, k) in kids.enumerated() {
                let t = kids.count == 1 ? 0.5 : CGFloat(j) / CGFloat(kids.count - 1)
                let a = angle - spread / 2 + spread * t
                let dist: CGFloat = 150 + (kids.count > 6 ? CGFloat(j % 2) * 70 : 0)
                let r = 15 + 15 * CGFloat(sqrt(Double(k.bytes) / Double(kidMax)))
                out[k.id] = Placed(point: CGPoint(x: p.x + cos(a) * dist, y: p.y + sin(a) * dist), radius: r)
            }
        }
        return out
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 14) {
            GeometryReader { geo in
                let items = visible
                let placed = layout(items, in: geo.size)
                let effectiveZoom = zoom * gestureZoom
                let effectivePan = CGSize(width: pan.width + gesturePan.width, height: pan.height + gesturePan.height)
                ZStack {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { withAnimation(.spring(duration: 0.5)) { expanded = nil; picked = nil; zoom = 1; pan = .zero } }
                    ZStack {
                        links(items, placed)
                        ForEach(items, id: \.0.id) { n, parent in
                            if let p = placed[n.id] {
                                bubble(n, radius: p.radius, level: parent == nil ? 0 : parent == root.id ? 1 : 2)
                                    .position(p.point)
                                    .opacity(dimmed(n, parent) ? 0.38 : 1)
                                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                                    .zIndex(parent == nil ? 3 : parent == root.id ? 2 : 1)
                            }
                        }
                        ForEach(items, id: \.0.id) { n, parent in
                            if let p = placed[n.id] {
                                label(n, level: parent == nil ? 0 : parent == root.id ? 1 : 2, radius: p.radius)
                                    .position(x: p.point.x, y: p.point.y + p.radius + 16)
                                    .opacity(dimmed(n, parent) ? 0.38 : 1)
                                    .zIndex(hovered == n.id ? 20 : 10)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(effectiveZoom)
                    .offset(effectivePan)
                    .animation(.spring(duration: 0.6, bounce: 0.15), value: expanded)
                    .animation(.spring(duration: 0.55), value: zoom)
                    .animation(.spring(duration: 0.55), value: pan)
                    .animation(.spring(duration: 0.5), value: items.map(\.0.id))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .modifier(SizeReader { canvasSize = $0 })
                .modifier(ScrollWheelZoom { delta, point in zoomAround(point, in: geo.size, factor: exp(delta * 0.012)) })
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { gesturePan = $0.translation }
                        .onEnded { pan.width += $0.translation.width; pan.height += $0.translation.height; gesturePan = .zero }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { gestureZoom = $0.magnification }
                        .onEnded { zoom = min(max(zoom * $0.magnification, 0.5), 3); gestureZoom = 1 }
                )
                .overlay(alignment: .bottomTrailing) { zoomControls.padding(12) }
                .overlay(alignment: .topLeading) {
                    if let e = expanded, let n = root.children.first(where: { $0.id == e }) {
                        HStack(spacing: 6) {
                            Button { withAnimation(.spring(duration: 0.5)) { expanded = nil; picked = nil; zoom = 1; pan = .zero } } label: {
                                Label(root.title, systemImage: "chevron.left").font(.caption.weight(.semibold))
                            }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            Text(n.title).font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6).glassEffect(.regular, in: .capsule).padding(12)
                    }
                }
                .onChange(of: geo.size) { _, _ in if expanded == nil { pan = .zero } }
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
                .frame(width: 360)
                .glassCard(radius: 18)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45), value: picked?.id)
        .onChange(of: root.id) { _, _ in expanded = nil; picked = nil; zoom = 1; pan = .zero }
        .onChange(of: model.demoAction?.seq) { _, _ in
            guard let a = model.demoAction?.action else { return }
            let items = visible
            switch a {
            case .tap(let id):
                if let (n, parent) = items.first(where: { $0.0.id == id }) { tap(n, level: parent == nil ? 0 : parent == root.id ? 1 : 2) }
            case .toggle(let id):
                if let n = items.first(where: { $0.0.id == id })?.0 { onToggle?(n) }
            case .zoom(let f):
                zoomAround(CGPoint(x: lastSize.width / 2, y: lastSize.height / 2), in: lastSize, factor: f)
            case .reset:
                withAnimation(.spring(duration: 0.5)) { expanded = nil; picked = nil; zoom = 1; pan = .zero }
            case .panelFirst: break
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let h = hovered, let onToggle, let n = visible.first(where: { $0.0.id == h })?.0, isSelectable(n) else { return .ignored }
            onToggle(n); SoundFX.tap()
            return .handled
        }
    }

    private func dimmed(_ n: MapNode, _ parent: String?) -> Bool {
        guard let e = expanded else { return false }
        return parent == root.id && n.id != e
    }

    private func links(_ items: [(MapNode, String?)], _ placed: [String: Placed]) -> some View {
        Canvas { ctx, _ in
            for (n, parent) in items {
                guard let parent, let a = placed[parent], let b = placed[n.id] else { continue }
                var path = Path()
                path.move(to: a.point)
                let mid = CGPoint(x: (a.point.x + b.point.x) / 2, y: (a.point.y + b.point.y) / 2)
                path.addQuadCurve(to: b.point, control: CGPoint(x: mid.x + (a.point.y - b.point.y) * 0.08, y: mid.y + (b.point.x - a.point.x) * 0.08))
                let w = 1 + 4 * CGFloat(sqrt(Double(n.bytes) / Double(max(root.bytes, 1))))
                let dim = dimmed(n, parent)
                ctx.stroke(path, with: .color(n.tint.opacity(dim ? 0.12 : hovered == n.id ? 0.9 : 0.35)), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
        }
    }

    private var zoomControls: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button { withAnimation(.spring(duration: 0.4)) { zoom = max(0.5, zoom / 1.3) } } label: { Image(systemName: "minus.magnifyingglass") }
                Button { withAnimation(.spring(duration: 0.5)) { zoom = 1; pan = .zero } } label: { Image(systemName: "arrow.counterclockwise") }
                Button { withAnimation(.spring(duration: 0.4)) { zoom = min(3, zoom * 1.3) } } label: { Image(systemName: "plus.magnifyingglass") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(8)
            .glassEffect(.regular, in: .capsule)
        }
    }

    // MARK: Bubbles and labels

    private func bubble(_ n: MapNode, radius: CGFloat, level: Int) -> some View {
        let frac = selectedFraction(n)
        let isHover = hovered == n.id
        let isPicked = picked?.id == n.id
        return ZStack {
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
            if level > 0, isSelectable(n), let onToggle {
                let state: String = frac >= 0.999 ? "checkmark.circle.fill" : frac > 0 ? "minus.circle.fill" : "circle"
                Image(systemName: state)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(frac > 0 ? Color.black.opacity(0.8) : Color.white.opacity(0.9), frac > 0 ? n.tint : Color.black.opacity(0.45))
                    .background(Circle().fill(Color.black.opacity(0.35)).padding(-2))
                    .offset(x: -radius * 0.68, y: -radius * 0.68)
                    .contentShape(Circle().scale(1.6))
                    .onTapGesture { onToggle(n); SoundFX.tap() }
                    .help(frac >= 0.999 ? "Deselect" : "Select")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .glassEffect(.regular.tint(n.tint.opacity(0.35)).interactive(), in: .circle)
        .scaleEffect(isHover ? 1.08 : 1)
        .shadow(color: n.tint.opacity(isHover || isPicked ? 0.6 : 0.25), radius: isHover ? 20 : 10)
        .onHover { hovered = $0 ? n.id : (hovered == n.id ? nil : hovered) }
        .onTapGesture { tap(n, level: level) }
        .contextMenu {
            if let onToggle, level > 0, !(n.payload == .more(0)) { Button("Toggle selection") { onToggle(n) } }
        }
        .animation(.spring(duration: 0.3), value: isHover)
    }

    private func label(_ n: MapNode, level: Int, radius: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(n.title).font(.system(size: level == 0 ? 14 : level == 1 ? 12 : 11, weight: .semibold)).lineLimit(1)
            Text(n.subtitle).font(.system(size: 10, design: .rounded)).foregroundStyle(.white.opacity(0.78)).monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .frame(maxWidth: 190)
        .fixedSize()
        .background(Color(hex: 0x061A20).opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(n.tint.opacity(0.35), lineWidth: 0.5))
    }

    private func tap(_ n: MapNode, level: Int) {
        withAnimation(.spring(duration: 0.55, bounce: 0.15)) {
            switch level {
            case 0:
                expanded = nil; picked = nil; zoom = 1; pan = .zero
            case 1:
                if n.hasChildren && n.fanOut {
                    if expanded == n.id { expanded = nil; picked = nil; zoom = 1; pan = .zero }
                    else { expanded = n.id; picked = nil; focus(on: n.id) }
                } else {
                    picked = picked?.id == n.id ? nil : n
                    if picked != nil { focus(on: n.id, zoom: 1.25) }
                }
            default:
                picked = picked?.id == n.id ? nil : n
            }
        }
        SoundFX.tap()
    }

    /// Centre the canvas on a node at the given zoom. Positions depend on the
    /// canvas size, so recompute from the root layout at the current size.
    @State private var canvasSize: CGSize = .zero
    private func focus(on id: String, zoom target: CGFloat = 1.6) {
        // Use the ring geometry directly: the ring node angle is index based.
        guard let i = root.children.firstIndex(where: { $0.id == id }) else { return }
        let size = lastSize
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ring = min(size.width, size.height) * 0.33
        let angle = -CGFloat.pi / 2 + CGFloat(i) * (2 * .pi / CGFloat(max(root.children.count, 1)))
        // Aim a bit beyond the node, where its children fan out.
        let aim = CGPoint(x: center.x + cos(angle) * ring * 1.45, y: center.y + sin(angle) * ring * 1.45)
        zoom = target
        pan = CGSize(width: -(aim.x - center.x) * target, height: -(aim.y - center.y) * target)
    }

    private var lastSize: CGSize { canvasSize == .zero ? CGSize(width: 1000, height: 650) : canvasSize }

    /// Zoom by `factor` keeping the content under `cursor` (view coordinates) fixed.
    /// screen = center + (p − center)·zoom + pan, so solve for the content point
    /// under the cursor, then pick the pan that puts it back there at the new zoom.
    private func zoomAround(_ cursor: CGPoint, in size: CGSize, factor: CGFloat) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let newZoom = min(max(zoom * factor, 0.5), 4)
        let contentX = center.x + (cursor.x - center.x - pan.width) / zoom
        let contentY = center.y + (cursor.y - center.y - pan.height) / zoom
        withAnimation(.interactiveSpring(duration: 0.12)) {
            pan = CGSize(width: cursor.x - center.x - (contentX - center.x) * newZoom,
                         height: cursor.y - center.y - (contentY - center.y) * newZoom)
            zoom = newZoom
        }
    }
}

/// Reads the canvas size into the map so programmatic focus can do its maths.
private struct SizeReader: ViewModifier {
    let onChange: (CGSize) -> Void
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in Color.clear.onAppear { onChange(g.size) }.onChange(of: g.size) { _, s in onChange(s) } })
    }
}
