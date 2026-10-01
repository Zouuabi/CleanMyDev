import SwiftUI
import AppKit
import CleanCore

struct SpaceLensView: View {
    @Environment(AppModel.self) private var model
    @State private var current: DiskNode?
    @State private var hovered: DiskNode?
    @State private var items: [TreemapItem] = []
    @State private var lastSize: CGSize = .zero
    @State private var quarantineTarget: DiskNode?

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)
            if model.diskScanning {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView().controlSize(.large)
                    if let p = model.diskScanProgress {
                        Text("\(p.files.formatted()) files · \(ByteFormatter.string(p.bytes))").font(.title3.weight(.semibold)).monospacedDigit()
                        Text(p.current).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 600)
                    } else {
                        Text("Reading the file system…").font(.title3.weight(.semibold))
                    }
                    Spacer()
                }
            } else if let root = model.diskRoot {
                breadcrumb(root: root).padding(.horizontal, 28).padding(.bottom, 8)
                HStack(alignment: .top, spacing: 14) {
                    treemap(root: current ?? root)
                        .glassCard(radius: 16)
                    sidePanel(root: current ?? root).frame(width: 260)
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "chart.pie").font(.system(size: 72)).foregroundStyle(ModuleTheme.files.accent)
                    Text("Space Lens").font(.title2.weight(.semibold))
                    Text("Map your home folder to see where the space went.").foregroundStyle(.secondary)
                    HStack {
                        Button("Map home folder") { model.scanDisk(root: CMConstants.home) }.buttonStyle(PrimaryButtonStyle(tint: ModuleTheme.files.accent))
                        Button("Choose folder…") { pickFolder() }.buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer()
                }
            }
        }
        .onChange(of: model.diskRoot?.id) { _, _ in current = model.diskRoot; items = [] }
        .confirmationDialog("Move \(quarantineTarget?.name ?? "") to quarantine?", isPresented: Binding(get: { quarantineTarget != nil }, set: { if !$0 { quarantineTarget = nil } })) {
            Button("Quarantine \(quarantineTarget.map { ByteFormatter.string($0.totalSize) } ?? "")", role: .destructive) {
                if let t = quarantineTarget {
                    Task { _ = await model.quarantine(paths: [t.url], label: "Space Lens"); model.scanDisk(root: model.diskRoot.map { URL(filePath: $0.path) } ?? CMConstants.home) }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Space Lens").font(.system(size: 28, weight: .semibold, design: .rounded))
                if let r = model.diskRoot { Text("\(r.formattedSize) in \(r.fileCount.formatted()) files").foregroundStyle(.secondary) }
                else { Text(SidebarItem.spaceLens.subtitle).foregroundStyle(.secondary) }
            }
            Spacer()
            if model.diskRoot != nil {
                Button("Choose folder…") { pickFolder() }.buttonStyle(SecondaryButtonStyle())
                Button { model.scanDisk(root: URL(filePath: model.diskRoot!.path)) } label: { Label("Rescan", systemImage: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = CMConstants.home
        if panel.runModal() == .OK, let url = panel.url { model.scanDisk(root: url) }
    }

    private func breadcrumb(root: DiskNode) -> some View {
        var chain: [DiskNode] = []
        var n: DiskNode? = current ?? root
        while let node = n { chain.append(node); n = node.parent }
        chain.reverse()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(chain, id: \.id) { node in
                    Button(node === root ? "~" : node.name) { current = node; items = [] }
                        .buttonStyle(.plain).font(.subheadline.weight(node === (current ?? root) ? .bold : .regular))
                        .foregroundStyle(node === (current ?? root) ? .white : .white.opacity(0.65))
                    if node !== (current ?? root) { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                }
            }
        }
    }

    private func treemap(root: DiskNode) -> some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, _ in
                for item in items {
                    let r = CGRect(x: item.rect.x, y: item.rect.y, width: item.rect.width, height: item.rect.height)
                    let base = color(for: item.node.category)
                    let shade = 1.0 - Double(item.depth) * 0.09
                    var fill = base.opacity(item.node.isDirectory ? 0.35 * shade : 0.9 * shade)
                    if let h = hovered, h === item.node { fill = base.opacity(1) }
                    let path = Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3)
                    ctx.fill(path, with: .color(fill))
                    ctx.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 0.5)
                    let isLeaf = !item.node.isDirectory || item.node.children.isEmpty
                    if item.hasHeader {
                        let band = Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: 16), cornerRadius: 3)
                        ctx.fill(band, with: .color(.black.opacity(0.28)))
                        let label = Text("\(item.node.name)  \(item.node.formattedSize)").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.92))
                        ctx.draw(label, in: CGRect(x: r.minX + 5, y: r.minY + 1, width: r.width - 10, height: 14))
                    } else if isLeaf && r.width > 60 && r.height > 18 {
                        let label = Text(item.node.name).font(.system(size: 10)).foregroundColor(.white.opacity(0.85))
                        ctx.draw(label, in: CGRect(x: r.minX + 4, y: r.minY + 3, width: r.width - 8, height: 14))
                    }
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovered = items.reversed().first { $0.rect.contains(p) }?.node
                case .ended: hovered = nil
                }
            }
            .onTapGesture(count: 2) {
                if let h = hovered, h.isDirectory, h.children.count > 0 { current = h; items = [] }
            }
            .contextMenu {
                if let h = hovered {
                    Text(h.path).font(.caption)
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([h.url]) }
                    if h.isDirectory { Button("Zoom in") { current = h; items = [] } }
                    Divider()
                    Button("Move to quarantine…", role: .destructive) { quarantineTarget = h }
                }
            }
            .onChange(of: size) { _, new in relayout(root: root, size: new) }
            .onChange(of: current?.id) { _, _ in relayout(root: root, size: size) }
            .onAppear { relayout(root: root, size: size) }
        }
    }

    private func relayout(root: DiskNode, size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }
        lastSize = size
        items = TreemapLayout(maxDepth: 5, minPixelArea: 40, padding: 3, headerHeight: 16)
            .layout(root: root, in: TreemapRect(x: 0, y: 0, width: size.width, height: size.height))
    }

    private func sidePanel(root: DiskNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let h = hovered {
                Text(h.name).font(.headline).lineLimit(2)
                Text(h.path.replacingOccurrences(of: CMConstants.homePath, with: "~")).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                SizeText(bytes: UInt64(max(h.totalSize, 0)), font: .title2.weight(.bold))
                if h.isDirectory { Text("\(h.fileCount.formatted()) files").font(.caption).foregroundStyle(.secondary) }
                if let d = h.modificationDate { Text("Modified \(d.relativeDescription)").font(.caption).foregroundStyle(.secondary) }
                Divider().opacity(0.3)
            } else {
                Text(root.name == CMConstants.homePath ? "Home" : root.name).font(.headline)
                SizeText(bytes: UInt64(max(root.totalSize, 0)), font: .title2.weight(.bold))
                Text("Hover a block for details. Double-click a folder to zoom in.").font(.caption).foregroundStyle(.secondary)
                Divider().opacity(0.3)
            }
            SectionLabel(text: "By type")
            let total = Double(max(root.totalSize, 1))
            ForEach(root.categoryBreakdown().prefix(8), id: \.0) { cat, bytes in
                HStack(spacing: 8) {
                    Circle().fill(color(for: cat)).frame(width: 8, height: 8)
                    Text(cat.displayName).font(.caption)
                    Spacer()
                    Text("\(Int(Double(bytes) / total * 100))%").font(.caption2).foregroundStyle(.secondary)
                    Text(ByteFormatter.string(bytes)).font(.caption.monospacedDigit())
                }
            }
            Divider().opacity(0.3)
            SectionLabel(text: "Largest here")
            ForEach(root.children.prefix(8), id: \.id) { c in
                Button { if c.isDirectory { current = c; items = [] } else { NSWorkspace.shared.activateFileViewerSelecting([c.url]) } } label: {
                    HStack {
                        Image(systemName: c.isDirectory ? "folder.fill" : "doc.fill").font(.caption).foregroundStyle(color(for: c.category))
                        Text(c.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(c.formattedSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    private func color(for c: DiskCategory) -> Color {
        switch c {
        case .code: Color(hex: 0x38BDF8)
        case .dependencies: Color(hex: 0xF59E0B)
        case .build: Color(hex: 0xEF4444)
        case .media: Color(hex: 0xEC4899)
        case .image: Color(hex: 0xA78BFA)
        case .document: Color(hex: 0xE2E8F0)
        case .archive: Color(hex: 0xFB923C)
        case .app: Color(hex: 0x4ADE80)
        case .data: Color(hex: 0x2DD4BF)
        case .other: Color(hex: 0x64748B)
        }
    }
}
