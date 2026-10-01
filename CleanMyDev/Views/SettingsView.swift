import SwiftUI
import AppKit
import CleanCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newNever = ""

    var body: some View {
        @Bindable var model = model
        TabView {
            Form {
                Section("Project status") {
                    Stepper("Active if touched within \(model.settings.activeDays) days", value: $model.settings.activeDays, in: 1...90)
                    Stepper("Dormant after \(model.settings.dormantDays) days", value: $model.settings.dormantDays, in: 2...365)
                    Text("Between the two a project is Idle: listed, never auto-selected. Running containers, dev servers, and open terminals always make a project Active.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Cleaning") {
                    Picker("Default clean mode", selection: $model.settings.defaultCleanMode) {
                        Text("Quarantine (restorable)").tag(CleaningEngine.Mode.quarantine)
                        Text("Move to Trash").tag(CleaningEngine.Mode.trash)
                        Text("Delete permanently").tag(CleaningEngine.Mode.permanent)
                    }
                    Stepper("Keep quarantined items for \(model.settings.quarantineRetentionDays) days", value: $model.settings.quarantineRetentionDays, in: 1...60)
                    HStack {
                        Text("Large file threshold")
                        Spacer()
                        Picker("", selection: $model.settings.largeFileThreshold) {
                            ForEach([50, 100, 250, 500, 1000], id: \.self) { mb in Text("\(mb) MB").tag(UInt64(mb) * 1024 * 1024) }
                        }.labelsHidden().frame(width: 120)
                    }
                }
                Section("Menu bar") {
                    Toggle("Show CleanMyDev in the menu bar", isOn: $model.settings.menuBarEnabled)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Scan roots") {
                    ForEach(model.settings.scanRoots, id: \.self) { root in
                        HStack { Text(root).font(.caption.monospaced()); Spacer(); Button("Remove") { model.settings.scanRoots.removeAll { $0 == root } }.disabled(model.settings.scanRoots.count == 1) }
                    }
                    Button("Add folder…") { if let u = pick() { model.settings.scanRoots.append(u.path(percentEncoded: false)) } }
                }
                Section("Never touch") {
                    Text("Nothing under these folders is ever offered or deleted, whatever a scan finds.").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.settings.neverTouch, id: \.self) { p in
                        HStack { Text(p).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle); Spacer(); Button("Remove") { model.settings.neverTouch.removeAll { $0 == p } } }
                    }
                    Button("Add folder…") { if let u = pick() { model.settings.neverTouch = PathExclusion.normalized(model.settings.neverTouch + [u.path(percentEncoded: false)]) } }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Folders", systemImage: "folder") }

            Form {
                Section("Scheduled cleaning") {
                    Toggle("Run a daily background scan", isOn: $model.settings.scheduleEnabled)
                    Stepper("At \(model.settings.scheduleHour):00", value: $model.settings.scheduleHour, in: 0...23).disabled(!model.settings.scheduleEnabled)
                    Text("The background run quarantines only the categories below. Everything else waits for you in Smart Care.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Auto-clean without asking") {
                    ForEach(ScanCategory.allCases.filter(\.eligibleForAutoClean)) { cat in
                        Toggle(isOn: Binding(
                            get: { model.settings.autoCleanCategories.contains(cat) },
                            set: { on in if on { model.settings.autoCleanCategories.insert(cat) } else { model.settings.autoCleanCategories.remove(cat) } }
                        )) {
                            VStack(alignment: .leading) { Text(cat.displayName); Text(cat.subtitle).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Schedule", systemImage: "clock") }
            .onChange(of: model.settings.scheduleEnabled) { _, _ in Scheduler.apply(model.settings) }
            .onChange(of: model.settings.scheduleHour) { _, _ in Scheduler.apply(model.settings) }

            VStack(alignment: .leading, spacing: 10) {
                Text("Operations log").font(.headline)
                ScrollView {
                    Text(OperationLog.tail(lines: 300).joined(separator: "\n")).font(.caption2.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Reveal log file") { NSWorkspace.shared.activateFileViewerSelecting([CMConstants.operationLogFile]) }
            }
            .padding()
            .tabItem { Label("Log", systemImage: "doc.text") }
        }
    }

    private func pick() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = CMConstants.home
        return panel.runModal() == .OK ? panel.url : nil
    }
}
