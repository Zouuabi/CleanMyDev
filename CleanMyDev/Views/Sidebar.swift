import SwiftUI
import CleanCore

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case smartCare
    case systemJunk, browsers, trash
    case projects, devStack, devJunk, docker, simulators, ports
    case protection, startupItems
    case uninstaller
    case spaceLens, largeFiles
    case quarantine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartCare: "Smart Care"
        case .systemJunk: "System Junk"
        case .browsers: "Browsers"
        case .trash: "Trash"
        case .projects: "Projects"
        case .devStack: "Dev Stack"
        case .devJunk: "Dev Junk"
        case .docker: "Docker"
        case .simulators: "Simulators"
        case .ports: "Ports"
        case .protection: "Malware Scan"
        case .startupItems: "Startup Items"
        case .uninstaller: "Uninstaller"
        case .spaceLens: "Space Lens"
        case .largeFiles: "Large & Old Files"
        case .quarantine: "Quarantine"
        }
    }

    var subtitle: String {
        switch self {
        case .smartCare: "One pass over caches, dev junk, Docker, browsers and startup items. Review, then clean."
        case .systemJunk: "Caches, logs, crash reports, leftovers from deleted apps, editor and AI tool caches."
        case .browsers: "Page caches and history for Chrome, Edge, Brave, Arc, Firefox and Safari. Logins stay."
        case .trash: "Everything sitting in the Trash, on every volume."
        case .projects: "Every project on this Mac with its status. Pin what you're working on."
        case .devStack: "Databases, runtimes, global tools, SDKs and VM disks, discovered from where tools keep them."
        case .devJunk: "Package manager caches, Xcode junk, and dependencies of dormant projects."
        case .docker: "Unused images, orphan volumes, stopped containers and build cache. Running projects are untouched."
        case .simulators: "Simulator devices that can't boot or haven't been used in a while."
        case .ports: "Who is listening on which port, and a kill switch."
        case .protection: "Known adware families plus an audit of every launch agent and daemon."
        case .startupItems: "Everything that runs at login, with its code signature."
        case .uninstaller: "Installed apps with their leftovers across ~/Library."
        case .spaceLens: "Treemap of your home folder. Click to drill in."
        case .largeFiles: "The biggest and oldest files in your home folder."
        case .quarantine: "Cleaned items wait here before they're gone for good."
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "sparkles"
        case .systemJunk: "trash.circle"
        case .browsers: "safari"
        case .trash: "trash"
        case .projects: "folder.badge.gearshape"
        case .devStack: "cylinder.split.1x2"
        case .devJunk: "shippingbox"
        case .docker: "cube.transparent"
        case .simulators: "iphone.gen3"
        case .ports: "network"
        case .protection: "shield.lefthalf.filled"
        case .startupItems: "power.circle"
        case .uninstaller: "xmark.app"
        case .spaceLens: "chart.pie"
        case .largeFiles: "doc.richtext"
        case .quarantine: "archivebox"
        }
    }

    var theme: ModuleTheme {
        switch self {
        case .smartCare: .smart
        case .systemJunk, .browsers, .trash: .cleanup
        case .projects, .devStack, .devJunk, .docker, .simulators, .ports: .developer
        case .protection, .startupItems: .protection
        case .uninstaller: .applications
        case .spaceLens, .largeFiles: .files
        case .quarantine: .neutral
        }
    }

    /// Module ids this scope runs. nil means the screen is not a scan screen.
    var moduleIDs: Set<String>? {
        switch self {
        case .smartCare: ["system_junk", "dev_junk", "docker", "simulators", "privacy", "malware", "trash"]
        case .systemJunk: ["system_junk"]
        case .browsers: ["privacy"]
        case .trash: ["trash"]
        case .devJunk: ["dev_junk"]
        case .docker: ["docker"]
        case .simulators: ["simulators"]
        case .protection: ["malware"]
        case .largeFiles: ["large_files"]
        default: nil
        }
    }

    var scanTitle: String {
        switch self {
        case .smartCare: "Scan"
        case .browsers, .protection: "Check"
        default: "Scan"
        }
    }

    static let groups: [(String, [SidebarItem])] = [
        ("", [.smartCare]),
        ("Cleanup", [.systemJunk, .browsers, .trash]),
        ("Developer", [.projects, .devStack, .devJunk, .docker, .simulators, .ports]),
        ("Protection", [.protection, .startupItems]),
        ("Applications", [.uninstaller]),
        ("Files", [.spaceLens, .largeFiles]),
        ("", [.quarantine]),
    ]
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                ForEach(Array(SidebarItem.groups.enumerated()), id: \.offset) { _, group in
                    if group.0.isEmpty {
                        ForEach(group.1) { row($0) }
                    } else {
                        Section(group.0) { ForEach(group.1) { row($0) } }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider().opacity(0.3)
            diskFooter.padding(12)
        }
        .frame(minWidth: 250)
    }

    @ViewBuilder
    private func row(_ item: SidebarItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.theme.accent)
                .frame(width: 22)
            Text(item.title).lineLimit(1)
            Spacer(minLength: 4)
            badge(item)
        }
        .tag(item)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func badge(_ item: SidebarItem) -> some View {
        if case .results = model.phase(item), model.totalBytes(item) > 0 {
            Text(ByteFormatter.string(model.totalBytes(item)))
                .font(.caption2.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(item.theme.accent.opacity(0.22), in: Capsule())
                .foregroundStyle(item.theme.accent)
        } else if case .scanning = model.phase(item) {
            ProgressView().controlSize(.mini)
        } else if item == .quarantine, !model.quarantineRuns.isEmpty {
            Text("\(model.quarantineRuns.count)").font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
    }

    private var diskFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = model.stats {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive").foregroundStyle(.secondary)
                    Text("\(ByteFormatter.string(s.diskFree)) free of \(ByteFormatter.string(s.diskTotal))")
                        .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule().fill(s.diskUsedFraction > 0.9 ? Color.red : s.diskUsedFraction > 0.75 ? Color.orange : Color.green)
                            .frame(width: g.size.width * s.diskUsedFraction)
                    }
                }
                .frame(height: 6)
                if let last = model.settings.lastCleanDate {
                    Text("Last clean \(last.relativeDescription) · \(ByteFormatter.string(model.settings.lastCleanFreedBytes))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
