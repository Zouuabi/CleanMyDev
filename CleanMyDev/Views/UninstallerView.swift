import SwiftUI
import AppKit
import CleanCore

struct UninstallerView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var selectedApp: AppInfo?
    @State private var leftovers: [FileItem] = []
    @State private var leftoverSelection: Set<URL> = []
    @State private var loadingLeftovers = false
    @State private var showApple = false
    @State private var sort: Sort = .size
    @State private var lastResult: CleaningEngine.Result?

    enum Sort: String, CaseIterable { case size = "Size", name = "Name", lastUsed = "Last used" }

    private var apps: [AppInfo] {
        model.apps
            .filter { showApple || !$0.isAppleApp }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleIdentifier.localizedCaseInsensitiveContains(search) }
            .sorted {
                switch sort {
                case .size: $0.size > $1.size
                case .name: $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                case .lastUsed: ($0.lastOpened ?? .distantPast) < ($1.lastOpened ?? .distantPast)
                }
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 10)
                if model.appsLoading && model.apps.isEmpty {
                    Spacer(); ProgressView("Reading applications…"); Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(apps) { app in
                                AppRow(app: app, isSelected: selectedApp == app) { select(app) }
                            }
                        }
                        .padding(.horizontal, 24).padding(.bottom, 24)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if let app = selectedApp {
                Divider().opacity(0.2)
                inspector(app).frame(width: 380)
            }
        }
        .task { model.loadApps() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uninstaller").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("\(apps.count) apps · \(ByteFormatter.string(apps.reduce(0) { $0 + $1.size }))").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented).frame(width: 240)
            }
            HStack {
                TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
                Toggle("Show Apple apps", isOn: $showApple).toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    private func select(_ app: AppInfo) {
        selectedApp = app
        leftovers = []
        leftoverSelection = []
        lastResult = nil
        loadingLeftovers = true
        Task.detached {
            let found = AppPathFinder().findAssociatedFiles(for: app)
            await MainActor.run {
                guard selectedApp == app else { return }
                leftovers = found
                leftoverSelection = Set(found.map(\.url))
                loadingLeftovers = false
            }
        }
    }

    @ViewBuilder
    private func inspector(_ app: AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path(percentEncoded: false))).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.title3.weight(.semibold))
                    Text(app.version ?? "").font(.caption).foregroundStyle(.secondary)
                    Text(app.bundleIdentifier).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                StatusChip(text: app.source.rawValue.capitalized, systemImage: sourceSymbol(app.source), tint: ModuleTheme.applications.accent)
                if let last = app.lastOpened { StatusChip(text: "Used \(last.relativeDescription)", systemImage: "clock", tint: app.isUnused ? .orange : .secondary) }
                else { StatusChip(text: "Never opened", systemImage: "clock", tint: .orange) }
            }
            HStack {
                VStack(alignment: .leading) { SectionLabel(text: "App"); SizeText(bytes: app.size) }
                Spacer()
                VStack(alignment: .trailing) { SectionLabel(text: "Leftovers"); SizeText(bytes: leftovers.filter { leftoverSelection.contains($0.url) }.reduce(0) { $0 + $1.size }) }
            }
            .padding(12).glassCard(radius: 12)

            SectionLabel(text: "Related files")
            if loadingLeftovers {
                ProgressView().controlSize(.small)
            } else if leftovers.isEmpty {
                Text("No leftovers found outside the app bundle.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(leftovers) { f in
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(get: { leftoverSelection.contains(f.url) }, set: { on in if on { leftoverSelection.insert(f.url) } else { leftoverSelection.remove(f.url) } }))
                                    .toggleStyle(CheckToggleStyle(tint: ModuleTheme.applications.accent, mixed: false)).labelsHidden()
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.name).font(.caption).lineLimit(1)
                                    Text(f.url.deletingLastPathComponent().lastPathComponent).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(f.formattedSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Button { NSWorkspace.shared.activateFileViewerSelecting([f.url]) } label: { Image(systemName: "magnifyingglass").font(.caption) }.buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            Spacer()
            if let r = lastResult {
                Text("Moved \(r.removedCount) items (\(r.formattedFreed)) to quarantine.").font(.caption).foregroundStyle(.green)
            }
            if app.isAppleApp || SafetyGuard().isProtectedApp(app.bundleIdentifier) {
                Text("System apps can't be uninstalled.").font(.caption).foregroundStyle(.orange)
            } else {
                HStack {
                    Button("Remove leftovers only") { run(app, includeApp: false) }.buttonStyle(SecondaryButtonStyle()).disabled(leftoverSelection.isEmpty)
                    Spacer()
                    Button { run(app, includeApp: true) } label: { Label("Uninstall", systemImage: "trash") }
                        .buttonStyle(PrimaryButtonStyle(tint: ModuleTheme.applications.accent))
                }
            }
        }
        .padding(22)
        .background(Color.black.opacity(0.18))
    }

    private func run(_ app: AppInfo, includeApp: Bool) {
        let files = leftovers.filter { leftoverSelection.contains($0.url) }
        Task {
            let r = await model.uninstall(app, leftovers: files, includeApp: includeApp, mode: .quarantine)
            lastResult = r
            if includeApp, r.removedURLs.contains(app.path) { selectedApp = nil }
            else { select(app) }
        }
    }

    private func sourceSymbol(_ s: AppInfo.Source) -> String {
        switch s {
        case .appStore: "storefront"
        case .homebrew: "mug"
        case .direct: "arrow.down.circle"
        case .system: "apple.logo"
        }
    }
}

struct AppRow: View {
    let app: AppInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path(percentEncoded: false))).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(app.version ?? "").font(.caption2).foregroundStyle(.secondary)
                        if app.isUnused { Text("· unused 6+ months").font(.caption2).foregroundStyle(.orange) }
                    }
                }
                Spacer()
                Text(app.lastOpened?.relativeDescription ?? "never").font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                Text(app.formattedSize).font(.subheadline.monospacedDigit()).frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isSelected ? ModuleTheme.applications.accent.opacity(0.22) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? ModuleTheme.applications.accent.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
