import SwiftUI

/// Packed-circle map: one bubble per item, area proportional to bytes,
/// colour from the caller. Hover lifts, click selects.
struct Bubble: Identifiable, Equatable {
    let id: String
    let label: String
    let sublabel: String
    let bytes: UInt64
    let tint: Color
    let symbol: String
}

struct BubbleMap: View {
    let bubbles: [Bubble]
    @Binding var selected: String?
    @State private var hovered: String? = nil
    @State private var cache: (key: String, size: CGSize, placed: [String: (CGPoint, CGFloat)])? = nil

    var body: some View {
        GeometryReader { geo in
            let placed = positions(in: geo.size)
            ZStack {
                ForEach(bubbles) { b in
                    if let (p, r) = placed[b.id] {
                        bubble(b, radius: r)
                            .position(p)
                            .zIndex(hovered == b.id || selected == b.id ? 2 : 1)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(duration: 0.6, bounce: 0.15), value: bubbles.map(\.id))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { selected = nil } }
        }
    }

    private func bubble(_ b: Bubble, radius: CGFloat) -> some View {
        let hover = hovered == b.id
        let sel = selected == b.id
        return ZStack {
            Circle().fill(b.tint.opacity(sel ? 0.6 : 0.3))
            Circle().stroke(sel ? Color.white.opacity(0.8) : Color.white.opacity(0.14), lineWidth: sel ? 2 : 1)
            VStack(spacing: 2) {
                Image(systemName: b.symbol).font(.system(size: max(10, radius * 0.42), weight: .semibold)).foregroundStyle(.white)
                if radius >= 26 {
                    Text(b.label).font(.system(size: max(9, min(12, radius * 0.22)), weight: .semibold)).lineLimit(1).frame(maxWidth: radius * 1.7)
                    Text(b.sublabel).font(.system(size: max(8, min(10, radius * 0.18)), design: .rounded)).foregroundStyle(.white.opacity(0.8)).lineLimit(1).frame(maxWidth: radius * 1.7)
                }
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .glassEffect(.regular.tint(b.tint.opacity(0.4)).interactive(), in: .circle)
        .scaleEffect(hover ? 1.08 : 1)
        .shadow(color: b.tint.opacity(hover || sel ? 0.65 : 0.25), radius: hover ? 22 : 10)
        .onHover { hovered = $0 ? b.id : (hovered == b.id ? nil : hovered) }
        .onTapGesture { withAnimation(.spring(duration: 0.35)) { selected = selected == b.id ? nil : b.id }; SoundFX.tap() }
        .help("\(b.label) · \(b.sublabel)")
        .animation(.spring(duration: 0.28), value: hover)
    }

    // MARK: Packing

    private func positions(in size: CGSize) -> [String: (CGPoint, CGFloat)] {
        let key = bubbles.map { "\($0.id):\($0.bytes)" }.joined(separator: ",")
        if let c = cache, c.key == key, c.size == size { return c.placed }
        let result = Self.pack(bubbles, in: size)
        DispatchQueue.main.async { cache = (key, size, result) }
        return result
    }

    static func pack(_ bubbles: [Bubble], in size: CGSize) -> [String: (CGPoint, CGFloat)] {
        guard !bubbles.isEmpty, size.width > 20, size.height > 20 else { return [:] }
        let sorted = bubbles.sorted { $0.bytes > $1.bytes }
        let maxB = Double(max(sorted.first?.bytes ?? 1, 1))
        // Radii: sqrt scale with floor, then normalised so total area ≈ 50% of the canvas.
        var radii = sorted.map { max(14.0, 14 + 70 * sqrt(Double($0.bytes) / maxB)) }
        let area = radii.reduce(0) { $0 + .pi * $1 * $1 }
        let target = Double(size.width * size.height) * 0.48
        let k = sqrt(target / max(area, 1))
        radii = radii.map { max(12, min(130, $0 * k)) }

        var placed: [(CGPoint, CGFloat)] = []
        for r in radii {
            if placed.isEmpty { placed.append((.zero, r)); continue }
            var theta = 0.0
            var found: CGPoint? = nil
            while found == nil && theta < 400 {
                let rho = theta * 1.6
                let p = CGPoint(x: cos(theta) * rho, y: sin(theta) * rho * (size.height / size.width))
                let ok = placed.allSatisfy { q, qr in hypot(p.x - q.x, p.y - q.y) >= r + qr + 5 }
                if ok { found = p }
                theta += 0.22
            }
            placed.append((found ?? .zero, r))
        }
        // Fit into the canvas.
        let minX = placed.map { $0.0.x - $0.1 }.min() ?? 0, maxX = placed.map { $0.0.x + $0.1 }.max() ?? 1
        let minY = placed.map { $0.0.y - $0.1 }.min() ?? 0, maxY = placed.map { $0.0.y + $0.1 }.max() ?? 1
        let w = maxX - minX, h = maxY - minY
        let scale = min((size.width - 24) / max(w, 1), (size.height - 24) / max(h, 1), 1.0)
        var out: [String: (CGPoint, CGFloat)] = [:]
        for (i, b) in sorted.enumerated() {
            let (p, r) = placed[i]
            let x = (p.x - (minX + w / 2)) * scale + size.width / 2
            let y = (p.y - (minY + h / 2)) * scale + size.height / 2
            out[b.id] = (CGPoint(x: x, y: y), r * scale)
        }
        return out
    }
}
