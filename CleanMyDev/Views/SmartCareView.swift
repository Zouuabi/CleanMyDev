import SwiftUI
import CleanCore

struct SmartCareView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleScreen(scope: .smartCare) {
            VitalsStrip().padding(.horizontal, 40).padding(.top, 24)
        }
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10)], spacing: 10) {
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
        HStack(spacing: 10) {
            Image(systemName: entry.project.kinds.first?.symbol ?? "folder").foregroundStyle(ModuleTheme.developer.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.project.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(entry.decision.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(entry.project.formattedArtifactSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            StatusMenu(entry: entry)
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
