import SwiftUI
import AppKit
import CleanCore

struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: ProjectStatus? = nil
    @State private var search = ""
    @State private var onlyWithArtifacts = true

    private var rows: [ProjectScanService.Entry] {
        model.projects
            .filter { !onlyWithArtifacts || !$0.project.artifacts.isEmpty }
            .filter { filter == nil || $0.decision.status == filter }
            .filter { search.isEmpty || $0.project.name.localizedCaseInsensitiveContains(search) || $0.project.path.localizedCaseInsensitiveContains(search) }
            .sorted { $0.project.totalArtifactBytes > $1.project.totalArtifactBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)
            if model.projectsLoading && model.projects.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView().controlSize(.large)
                    Text("Finding projects…").font(.title3.weight(.semibold))
                    Text("Walking your scan roots and sizing dependencies and build output.").foregroundStyle(.secondary)
                    Spacer()
                }
            } else if model.projects.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "folder.badge.gearshape").font(.system(size: 72)).foregroundStyle(ModuleTheme.developer.accent)
                    Text("No projects scanned yet").font(.title2.weight(.semibold))
                    Text("CleanMyDev looks for package.json, pyproject.toml, Cargo.toml, Podfile, .xcodeproj and 20 other markers under your scan roots.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
                    Button("Find projects") { model.refreshProjects() }.buttonStyle(PrimaryButtonStyle(tint: ModuleTheme.developer.accent))
                    Spacer()
                }
            } else {
                summaryChips.padding(.horizontal, 28).padding(.bottom, 10)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(rows) { ProjectRow(entry: $0) }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 30)
                }
            }
        }
        .task { if model.projects.isEmpty { model.refreshProjects() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Projects").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Active and pinned projects are never touched. Dormant ones give up their dependencies and build output.").foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Only with deps or build output", isOn: $onlyWithArtifacts).toggleStyle(.switch).controlSize(.small)
            TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
            Button { model.refreshProjects() } label: {
                if model.projectsLoading { ProgressView().controlSize(.small) } else { Label("Rescan", systemImage: "arrow.clockwise") }
            }
            .buttonStyle(SecondaryButtonStyle()).disabled(model.projectsLoading)
        }
    }

    private var summaryChips: some View {
        HStack(spacing: 8) {
            chip(nil, "All", model.projects.count)
            ForEach(ProjectStatus.allCases, id: \.self) { s in
                let n = model.projects.filter { $0.decision.status == s }.count
                if n > 0 { chip(s, s.displayName, n) }
            }
            Spacer()
            let cleanable = model.projects.filter { $0.decision.status.allowsCleaning }.reduce(0) { $0 + $1.project.totalArtifactBytes }
            Text("\(ByteFormatter.string(cleanable)) reclaimable from dormant projects").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chip(_ s: ProjectStatus?, _ label: String, _ n: Int) -> some View {
        Button { filter = s } label: {
            HStack(spacing: 6) {
                if let s { Image(systemName: s.systemImage) }
                Text("\(label) \(n)")
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((filter == s ? (s?.tint ?? .white) : Color.white).opacity(filter == s ? 0.25 : 0.08), in: Capsule())
            .foregroundStyle(filter == s ? (s?.tint ?? .white) : .white.opacity(0.8))
        }
        .buttonStyle(.plain)
    }
}

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let entry: ProjectScanService.Entry
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: entry.project.kinds.first?.symbol ?? "folder")
                    .font(.title3).foregroundStyle(ModuleTheme.developer.accent).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(entry.project.name).font(.headline)
                        Text(entry.project.kindSummary).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(entry.project.path.replacingOccurrences(of: CMConstants.homePath, with: "~"))
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 10) {
                        Text(entry.decision.reason).font(.caption).foregroundStyle(entry.decision.status.tint)
                        if entry.project.signals.runningContainers > 0 {
                            Label("\(entry.project.signals.runningContainers) containers", systemImage: "shippingbox").font(.caption2).foregroundStyle(.secondary)
                        }
                        if entry.project.signals.devServerRunning {
                            Label("dev server", systemImage: "bolt.horizontal").font(.caption2).foregroundStyle(.secondary)
                        }
                        if entry.project.signals.openInEditor {
                            Label("shell open here", systemImage: "terminal").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    SizeText(bytes: entry.project.totalArtifactBytes)
                    Text("\(entry.project.artifacts.count) artifact\(entry.project.artifacts.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 110, alignment: .trailing)
                StatusMenu(entry: entry)
                Button { expanded.toggle() } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 22)
                }.buttonStyle(.plain)
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }

            if expanded {
                Divider().opacity(0.2)
                VStack(spacing: 0) {
                    ForEach(entry.project.artifacts) { a in
                        HStack {
                            Image(systemName: a.isDependency ? "cube.box" : "wrench.and.screwdriver").foregroundStyle(.secondary).frame(width: 20)
                            Text(a.relativePath).font(.subheadline.monospaced())
                            Text(a.isDependency ? "dependencies" : "build output").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(a.formattedSize).font(.subheadline.monospacedDigit())
                        }
                        .padding(.horizontal, 18).padding(.vertical, 7)
                    }
                    if entry.project.artifacts.isEmpty {
                        Text("No dependencies or build output on disk.").font(.caption).foregroundStyle(.secondary).padding(10)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .glassCard(radius: 14, tint: entry.decision.status.allowsCleaning ? nil : entry.decision.status.tint)
        .animation(.spring(duration: 0.25), value: expanded)
    }
}
