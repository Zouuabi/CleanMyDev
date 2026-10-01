import SwiftUI
import AppKit
import CleanCore

/// The shared scan → review → clean → done flow every module uses.
struct ModuleScreen<Header: View>: View {
    @Environment(AppModel.self) private var model
    let scope: SidebarItem
    var header: Header

    init(scope: SidebarItem, @ViewBuilder header: () -> Header = { EmptyView() }) {
        self.scope = scope
        self.header = header()
    }

    var body: some View {
        switch model.phase(scope) {
        case .idle:
            HeroView(scope: scope) { header }
        case .scanning(let progress, let module, let found):
            ScanningView(scope: scope, progress: progress, module: module, found: found)
        case .results:
            ResultsView(scope: scope)
        case .cleaning(let progress):
            CleaningView(scope: scope, progress: progress)
        case .done(let removed, let freed, let errors, let mode):
            DoneView(scope: scope, removed: removed, freed: freed, errors: errors, mode: mode)
        }
    }
}

struct HeroView<Header: View>: View {
    @Environment(AppModel.self) private var model
    let scope: SidebarItem
    @ViewBuilder var header: () -> Header

    var body: some View {
        VStack(spacing: 0) {
            header()
            Spacer()
            HStack(spacing: 60) {
                ZStack {
                    RoundedRectangle(cornerRadius: 48, style: .continuous)
                        .fill(LinearGradient(colors: [scope.theme.accent.opacity(0.55), scope.theme.accent.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 220, height: 220)
                        .shadow(color: scope.theme.accent.opacity(0.45), radius: 40, y: 16)
                    Image(systemName: scope.symbol)
                        .font(.system(size: 92, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(scope.title).font(.system(size: 40, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Text(scope.subtitle).font(.title3).foregroundStyle(.white.opacity(0.75)).frame(maxWidth: 440, alignment: .leading)
                    categoryBullets
                }
            }
            Spacer()
            BigScanButton(title: scope.scanTitle, tint: scope.theme.accent, isBusy: false) { model.scan(scope) }
                .keyboardShortcut("r")
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
    }

    private var categoryBullets: some View {
        let cats = Self.categories(for: scope)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(cats.prefix(5), id: \.self) { c in
                HStack(spacing: 10) {
                    Image(systemName: c.systemImage).foregroundStyle(scope.theme.accent).frame(width: 18)
                    Text(c.displayName).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(.top, 8)
    }

    static func categories(for scope: SidebarItem) -> [ScanCategory] {
        switch scope {
        case .smartCare: [.userCaches, .packageManagerCaches, .projectDependencies, .dockerImages, .browserCache]
        case .systemJunk: [.userCaches, .userLogs, .crashReports, .trashBins, .appLeftovers]
        case .browsers: [.browserCache, .browserHistory, .systemPrivacy]
        case .devJunk: [.packageManagerCaches, .xcodeJunk, .simulators, .projectDependencies, .projectBuildOutput]
        case .docker: [.dockerImages, .dockerVolumes, .dockerContainers, .dockerBuildCache]
        case .security: [.malware, .suspiciousPersistence]
        case .largeFiles: [.largeFiles, .oldFiles]
        default: []
        }
    }
}

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    let scope: SidebarItem
    @State private var expanded: Set<ScanCategory> = []
    @State private var confirmPermanent = false
    @State private var showMap = true

    private var results: [ModuleScanResult] { model.results(scope) }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)
            if results.isEmpty {
                emptyState
            } else if showMap {
                ResultGraphView(scope: scope).padding(.horizontal, 28).padding(.bottom, 100)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if scope == .smartCare || scope == .devJunk { ProjectsStrip() }
                        ForEach(results) { m in
                            if scope == .smartCare {
                                SectionLabel(text: m.moduleName).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }
                            ForEach(m.categories) { cat in
                                CategoryCard(scope: scope, result: cat, isExpanded: expanded.contains(cat.category)) {
                                    if expanded.contains(cat.category) { expanded.remove(cat.category) } else { expanded.insert(cat.category) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 110)
                }
            }
        }
        .overlay(alignment: .bottom) { if !results.isEmpty { actionBar } }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scope.title).font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("\(model.allItems(scope).count) items · \(ByteFormatter.string(model.totalBytes(scope))) found")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button { model.selectRecommended(scope) } label: { Label("Recommended (safe categories)", systemImage: "sparkles") }
                Button { model.selectAll(scope) } label: { Label("Everything", systemImage: "checkmark.circle") }
                Button { model.selectNone(scope) } label: { Label("Nothing", systemImage: "circle") }
            } label: {
                Label("Select", systemImage: "checklist")
            }
            .menuStyle(.borderlessButton).fixedSize().foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7).glassEffect(.regular.interactive(), in: .capsule)
            Picker("", selection: $showMap) {
                Image(systemName: "circle.hexagongrid").tag(true)
                Image(systemName: "list.bullet").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 90)
            Button { model.scan(scope) } label: { Label("Rescan", systemImage: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(scope.theme.accent)
            Text("Nothing to clean").font(.title2.weight(.semibold))
            Text("This area is already tidy.").foregroundStyle(.secondary)
            Button("Back") { model.reset(scope) }.buttonStyle(SecondaryButtonStyle()).padding(.top, 8)
            Spacer()
        }
    }

    private var actionBar: some View {
        let selectedBytes = model.selectedBytes(scope)
        let count = model.selectedItems(scope).count
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) selected").font(.caption).foregroundStyle(.secondary)
                SizeText(bytes: selectedBytes, font: .title2.weight(.bold))
            }
            Spacer()
            Menu {
                Button("Quarantine (restorable for \(model.settings.quarantineRetentionDays) days)") { model.clean(scope, mode: .quarantine) }
                Button("Move to Trash") { model.clean(scope, mode: .trash) }
                Button("Dry run (log only)") { model.clean(scope, mode: .dryRun) }
                Divider()
                Button("Delete permanently…", role: .destructive) { confirmPermanent = true }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .foregroundStyle(.white)
            Button {
                model.clean(scope)
            } label: {
                Label("Clean \(ByteFormatter.string(selectedBytes))", systemImage: "sparkles")
            }
            .buttonStyle(PrimaryButtonStyle(tint: scope.theme.accent))
            .disabled(count == 0)
            .keyboardShortcut("k")
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(Color(hex: 0x0B0B14).opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glassCard(radius: 22)
        .padding(.horizontal, 28).padding(.bottom, 20)
        .confirmationDialog("Delete \(count) items permanently?", isPresented: $confirmPermanent) {
            Button("Delete permanently", role: .destructive) { model.clean(scope, mode: .permanent) }
        } message: {
            Text("This skips quarantine and the Trash. There is no undo.")
        }
    }
}

struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let scope: SidebarItem
    let result: ScanResult
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    private var selectedCount: Int { result.items.filter { model.selection(scope).contains($0.url) }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Toggle("", isOn: Binding(
                    get: { model.isCategoryFullySelected(result, in: scope) },
                    set: { model.setCategory(result, selected: $0, in: scope) }
                ))
                .toggleStyle(CheckToggleStyle(tint: scope.theme.accent, mixed: selectedCount > 0 && selectedCount < result.items.count))
                .labelsHidden()
                Image(systemName: result.category.systemImage)
                    .font(.title3).foregroundStyle(scope.theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.category.displayName).font(.headline)
                    Text(result.category.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !result.autoSelect {
                    StatusChip(text: "Review", systemImage: "eye", tint: .orange)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    SizeText(bytes: result.totalSize)
                    Text("\(result.items.count) items").font(.caption).foregroundStyle(.secondary)
                }
                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleExpanded)

            if isExpanded {
                Divider().opacity(0.25)
                LazyVStack(spacing: 0) {
                    ForEach(result.items.prefix(400)) { item in
                        ItemRow(scope: scope, item: item)
                        Divider().opacity(0.12).padding(.leading, 58)
                    }
                    if result.items.count > 400 {
                        Text("…and \(result.items.count - 400) more").font(.caption).foregroundStyle(.secondary).padding(10)
                    }
                }
            }
        }
        .glassCard(tint: result.autoSelect ? nil : .orange)
        .animation(.spring(duration: 0.3), value: isExpanded)
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let scope: SidebarItem
    let item: FileItem

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { model.selection(scope).contains(item.url) }, set: { _ in model.toggle(item, in: scope) }))
                .toggleStyle(CheckToggleStyle(tint: scope.theme.accent, mixed: false)).labelsHidden()
            Image(systemName: item.url.isFileURL ? (item.isDirectory ? "folder.fill" : "doc.fill") : "shippingbox.fill")
                .foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline).lineLimit(1)
                if let reason = item.reason {
                    Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if item.url.isFileURL {
                    Text(item.path.replacingOccurrences(of: CMConstants.homePath, with: "~"))
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if item.url.isFileURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Reveal in Finder")
            }
            Text(item.formattedSize).font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.9)).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct CheckToggleStyle: ToggleStyle {
    let tint: Color
    let mixed: Bool
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : mixed ? "minus.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(configuration.isOn || mixed ? tint : Color.white.opacity(0.35))
        }
        .buttonStyle(.plain)
    }
}

struct CleaningView: View {
    let scope: SidebarItem
    let progress: Double
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            RingGauge(value: max(progress, 0.03), tint: scope.theme.accent, center: "\(Int(progress * 100))%", lineWidth: 10).frame(width: 160, height: 160)
            Text("Cleaning…").font(.title3.weight(.semibold))
            Spacer()
        }
    }
}

struct DoneView: View {
    @Environment(AppModel.self) private var model
    let scope: SidebarItem
    let removed: Int
    let freed: UInt64
    let errors: Int
    let mode: CleaningEngine.Mode

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: mode == .dryRun ? "eye.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 80)).foregroundStyle(scope.theme.accent)
                .shadow(color: scope.theme.accent.opacity(0.6), radius: 30)
            Text(mode == .dryRun ? "Dry run complete" : "Cleaned").font(.system(size: 34, weight: .bold, design: .rounded))
            Text(ByteFormatter.string(freed)).font(.system(size: 54, weight: .bold, design: .rounded)).foregroundStyle(scope.theme.accent).monospacedDigit()
            Text(summary).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if errors > 0 {
                Button { NSWorkspace.shared.activateFileViewerSelecting([CMConstants.operationLogFile]) } label: {
                    Label("\(errors) items were skipped · open log", systemImage: "exclamationmark.triangle")
                }.buttonStyle(SecondaryButtonStyle())
            }
            HStack(spacing: 12) {
                Button("Done") { model.reset(scope) }.buttonStyle(PrimaryButtonStyle(tint: scope.theme.accent))
                if mode == .quarantine, removed > 0 {
                    Button("Open Quarantine") { model.selection = .quarantine; model.reset(scope) }.buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.top, 10)
            Spacer()
        }
    }

    private var summary: String {
        switch mode {
        case .dryRun: "\(removed) items would be removed. Nothing was touched; see the log for the full list."
        case .quarantine: "\(removed) items moved to quarantine. Restore any of them within \(model.settings.quarantineRetentionDays) days."
        case .trash: "\(removed) items moved to the Trash."
        case .permanent: "\(removed) items deleted."
        }
    }
}
