import SwiftUI
import CleanCore

struct SmartCareView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleScreen(scope: .smartCare) {
            VStack(spacing: 12) {
                VitalsStrip()
                FlagshipStrip()
            }
            .padding(.horizontal, 40).padding(.top, 24)
        }
        .task {
            if model.projects.isEmpty { model.refreshProjects() }
            if model.devStack.isEmpty { model.loadDevStack() }
        }
    }
}

/// Projects and Dev Stack at a glance, on the Smart Care hero.
struct FlagshipStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Button { model.selection = .projects } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.gearshape").font(.title2).foregroundStyle(ModuleTheme.developer.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            SectionLabel(text: "Projects")
                            if model.projectsLoading && model.projects.isEmpty {
                                HStack(spacing: 6) { PulseDots(tint: ModuleTheme.developer.accent); Text("finding…").font(.caption).foregroundStyle(.secondary) }
                            } else {
                                let active = model.projects.filter { $0.decision.status == .active || $0.decision.status == .pinned }.count
                                let dormantBytes = model.projects.filter { $0.decision.status.allowsCleaning }.reduce(0) { $0 + $1.project.totalArtifactBytes }
                                Text("\(model.projects.count) projects · \(active) protected").font(.subheadline.weight(.semibold))
                                Text("\(ByteFormatter.string(dormantBytes)) reclaimable from dormant ones").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(14).frame(maxWidth: .infinity).glassCard()
                }
                .buttonStyle(.plain)
                Button { model.selection = .devStack } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cylinder.split.1x2").font(.title2).foregroundStyle(ModuleTheme.files.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            SectionLabel(text: "Dev Stack")
                            if model.devStackLoading && model.devStack.isEmpty {
                                HStack(spacing: 6) { PulseDots(tint: ModuleTheme.files.accent); Text("inventorying…").font(.caption).foregroundStyle(.secondary) }
                            } else {
                                let dbs = model.devStack.filter { $0.group == .databases }.count
                                let running = model.devStack.filter { $0.status == .running }.count
                                Text("\(model.devStack.count) items · \(ByteFormatter.string(model.devStack.reduce(0) { $0 + $1.bytes }))").font(.subheadline.weight(.semibold))
                                Text("\(dbs) databases · \(running) running").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(14).frame(maxWidth: .infinity).glassCard()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Shared "working" screen with motion: orbiting dots, live file counter.
struct LiveWorkView: View {
    let title: String
    let subtitle: String
    let tint: Color
    @State private var spin = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { _ in
            let t = ScanTelemetry.shared.snapshot
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().trim(from: 0, to: 0.3)
                            .stroke(tint.opacity(0.9 - Double(i) * 0.3), style: StrokeStyle(lineWidth: 6 - CGFloat(i), lineCap: .round))
                            .frame(width: 120 - CGFloat(i) * 28, height: 120 - CGFloat(i) * 28)
                            .rotationEffect(.degrees(spin ? 360 + Double(i) * 120 : Double(i) * 120))
                            .animation(.linear(duration: 1.4 + Double(i) * 0.5).repeatForever(autoreverses: false), value: spin)
                    }
                    Text(t.filesVisited.formatted()).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                }
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                Text(t.currentPath.replacingOccurrences(of: CMConstants.homePath, with: "~")).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 520).frame(height: 14)
                Spacer()
            }
        }
        .onAppear { spin = true }
    }
}

struct VitalsStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            if let s = model.stats {
                vital(title: "CPU", value: s.cpuUsage, center: "\(Int(s.cpuUsage * 100))%", sub: nil)
                vital(title: "Memory", value: s.memoryFraction, center: "\(Int(s.memoryFraction * 100))%", sub: ByteFormatter.string(s.memoryUsed))
                vital(title: "Disk", value: s.diskUsedFraction, center: "\(Int(s.diskUsedFraction * 100))%", sub: "\(ByteFormatter.string(s.diskFree)) free")
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Last clean")
                if let d = model.settings.lastCleanDate {
                    Text(d.relativeDescription).font(.title3.weight(.semibold))
                    Text("\(ByteFormatter.string(model.settings.lastCleanFreedBytes)) freed").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Never").font(.title3.weight(.semibold))
                    Text("Run a scan to get started").font(.caption).foregroundStyle(.secondary)
                }
                if !model.quarantineRuns.isEmpty {
                    Text("\(ByteFormatter.string(QuarantineStore.totalBytes())) in quarantine").font(.caption).foregroundStyle(.cyan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassCard()
        }
    }

    private func vital(title: String, value: Double, center: String, sub: String?) -> some View {
        HStack(spacing: 12) {
            RingGauge(value: value, tint: value > 0.85 ? .red : value > 0.65 ? .orange : ModuleTheme.smart.accent, center: center).frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let sub { Text(sub).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
        }
        .padding(14)
        .frame(width: 190, alignment: .leading)
        .glassCard()
    }
}

/// Compact review of project decisions shown above results so the user can
/// flip a status without leaving the results screen.
struct ProjectsStrip: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false

    private var affecting: [ProjectScanService.Entry] {
        model.projects.filter { !$0.project.artifacts.isEmpty }
            .sorted { ($0.decision.status.allowsCleaning ? 0 : 1, $1.project.totalArtifactBytes) < ($1.decision.status.allowsCleaning ? 0 : 1, $0.project.totalArtifactBytes) }
    }

    var body: some View {
        let list = showAll ? affecting : Array(affecting.prefix(6))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Projects")
                Text("\(affecting.filter { $0.decision.status.allowsCleaning }.count) cleanable · \(affecting.filter { !$0.decision.status.allowsCleaning }.count) protected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(showAll ? "Show fewer" : "Show all \(affecting.count)") { showAll.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(ModuleTheme.developer.accent)
                Button("Open Projects") { model.selection = .projects }.buttonStyle(.plain).font(.caption).foregroundStyle(ModuleTheme.developer.accent)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10)], spacing: 10) {
                ForEach(list) { entry in
                    ProjectChipCard(entry: entry)
                }
            }
        }
        .padding(16)
        .glassCard()
    }
}

struct ProjectChipCard: View {
    @Environment(AppModel.self) private var model
    let entry: ProjectScanService.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: entry.project.kinds.first?.symbol ?? "folder").foregroundStyle(ModuleTheme.developer.accent).frame(width: 18)
                Text(entry.project.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 6)
                Text(entry.project.formattedArtifactSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                StatusMenu(entry: entry)
            }
            Text(entry.decision.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct StatusMenu: View {
    @Environment(AppModel.self) private var model
    let entry: ProjectScanService.Entry
    @State private var showPinSheet = false

    var body: some View {
        Menu {
            Button { showPinSheet = true } label: { Label("Pin until a date…", systemImage: "pin") }
            Button { model.setStatus(entry, to: .pinned) } label: { Label("Pin forever", systemImage: "pin.fill") }
            Button { model.setStatus(entry, to: .cleanable) } label: { Label("Mark cleanable", systemImage: "checkmark.circle") }
            if entry.decision.isOverride {
                Divider()
                Button { model.setStatus(entry, to: nil) } label: { Label("Back to automatic", systemImage: "wand.and.stars") }
            }
            Divider()
            Button { NSWorkspace.shared.activateFileViewerSelecting([entry.project.root]) } label: { Label("Reveal in Finder", systemImage: "magnifyingglass") }
        } label: {
            StatusChip(text: entry.decision.status.displayName, systemImage: entry.decision.status.systemImage, tint: entry.decision.status.tint)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .sheet(isPresented: $showPinSheet) { PinSheet(entry: entry) }
    }
}

struct PinSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: ProjectScanService.Entry
    @State private var until = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pin \(entry.project.name)").font(.title2.weight(.semibold))
            Text("Nothing inside this project, including its Docker containers and volumes, will be offered for cleaning until the date you pick.")
                .foregroundStyle(.secondary)
            DatePicker("Protect until", selection: $until, in: Date()..., displayedComponents: .date)
            HStack {
                ForEach([("3 days", 3), ("1 week", 7), ("1 month", 30)], id: \.1) { label, days in
                    Button(label) { until = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? until }.buttonStyle(SecondaryButtonStyle())
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Pin") { model.setStatus(entry, to: .pinned, until: until); dismiss() }
                    .buttonStyle(PrimaryButtonStyle(tint: ModuleTheme.developer.accent)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 460)
    }
}
