import SwiftUI
import CleanCore

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case smartCare, projects, devStack
    case systemJunk, devJunk, docker, browsers
    case security, uninstaller
    case spaceLens, quarantine
    // Scopes that live inside another screen (tabs), never in the sidebar.
    case largeFiles, startupItems, ports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartCare: "Smart Care"
        case .projects: "Projects"
        case .devStack: "Dev Stack"
        case .systemJunk: "System Junk"
        case .devJunk: "Dev Junk"
        case .docker: "Docker"
        case .browsers: "Browsers"
        case .security: "Security"
        case .uninstaller: "Apps"
        case .spaceLens: "Space Lens"
        case .quarantine: "Quarantine"
        case .largeFiles: "Large & Old Files"
        case .startupItems: "Startup Items"
        case .ports: "Ports"
        }
    }

    var subtitle: String {
        switch self {
        case .smartCare: "One pass over everything: junk, dev stack, projects, Docker, browsers, security. Review on the map, then clean."
        case .projects: "Every project on this Mac with its status. Pin what you're working on; dormant ones give up their deps."
        case .devStack: "Databases and their data, runtimes, global tools, SDKs and VM disks. Discovered, not configured."
        case .systemJunk: "Caches, logs, crash reports, trash, leftovers of deleted apps, editor and AI tool caches."
        case .devJunk: "Package manager caches, Xcode junk, dead simulators, and dependencies of dormant projects."
        case .docker: "Unused images, orphan volumes, stopped containers, build cache. Running projects untouched."
        case .browsers: "Page caches and history for Chrome, Edge, Brave, Arc, Firefox, Safari. Logins stay."
        case .security: "Known adware families, and every launch agent and daemon with its code signature."
        case .uninstaller: "Installed apps with their leftovers across ~/Library."
        case .spaceLens: "Treemap of your disk, plus the biggest and oldest files."
        case .quarantine: "Cleaned items wait here before they're gone for good."
        case .largeFiles: "The biggest and oldest files in your home folder."
        case .startupItems: "Everything that runs at login, with its code signature."
        case .ports: "Who is listening on which port, and a kill switch."
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "sparkles"
        case .projects: "folder.fill.badge.gearshape"
        case .devStack: "cylinder.split.1x2.fill"
        case .systemJunk: "trash.circle.fill"
        case .devJunk: "shippingbox.fill"
        case .docker: "cube.transparent.fill"
        case .browsers: "safari.fill"
        case .security: "shield.lefthalf.filled"
        case .uninstaller: "square.grid.2x2.fill"
        case .spaceLens: "chart.pie.fill"
        case .quarantine: "archivebox.fill"
        case .largeFiles: "doc.richtext.fill"
        case .startupItems: "power.circle.fill"
        case .ports: "network"
        }
    }

    var theme: ModuleTheme {
        switch self {
        case .smartCare, .projects, .devStack: .smart
        case .systemJunk, .browsers: .cleanup
        case .devJunk, .docker, .ports: .developer
        case .security, .startupItems: .protection
        case .uninstaller: .applications
        case .spaceLens, .largeFiles: .files
        case .quarantine: .neutral
        }
    }

    var moduleIDs: Set<String>? {
        switch self {
        case .smartCare: ["system_junk", "dev_junk", "docker", "simulators", "privacy", "malware", "trash"]
        case .systemJunk: ["system_junk", "trash"]
        case .devJunk: ["dev_junk", "simulators"]
        case .docker: ["docker"]
        case .browsers: ["privacy"]
        case .security: ["malware"]
        case .largeFiles: ["large_files"]
        default: nil
        }
    }

    var scanTitle: String { self == .security ? "Check" : "Scan" }

    static let groups: [(String, [SidebarItem])] = [
        ("", [.smartCare, .projects, .devStack]),
        ("Clean", [.systemJunk, .devJunk, .docker, .browsers]),
        ("Protect", [.security, .uninstaller]),
        ("Disk", [.spaceLens, .quarantine]),
    ]
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(SidebarItem.groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 4) {
                        if !group.0.isEmpty {
                            Text(group.0.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.2)
                                .foregroundStyle(.white.opacity(0.45)).padding(.leading, 14).padding(.bottom, 2)
                        }
                        ForEach(group.1) { row($0) }
                    }
                }
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 24)
            Divider().opacity(0.25)
            diskFooter.padding(12)
        }
        .frame(minWidth: 236)
    }

    private func row(_ item: SidebarItem) -> some View {
        let selected = model.selection == item
        return Button { withAnimation(.spring(duration: 0.3)) { model.selection = item } } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color.black.opacity(0.8) : item.theme.accent)
                    .frame(width: 32, height: 32)
                    .background(selected ? item.theme.accent : item.theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(item.title).font(.system(size: 14, weight: selected ? .semibold : .medium)).lineLimit(1)
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.85))
                Spacer(minLength: 4)
                badge(item)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(selected ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            PulseDots(tint: item.theme.accent)
        } else if item == .quarantine, !model.quarantineRuns.isEmpty {
            Text("\(model.quarantineRuns.count)").font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.white.opacity(0.12), in: Capsule())
        } else if item == .security, model.securityFlags > 0 {
            Text("\(model.securityFlags)").font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.25), in: Capsule()).foregroundStyle(.orange)
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
                        Capsule().fill(s.diskUsedFraction > 0.9 ? Color.red : s.diskUsedFraction > 0.75 ? Color.orange : ModuleTheme.brand)
                            .frame(width: g.size.width * s.diskUsedFraction)
                            .animation(.spring(duration: 0.8), value: s.diskUsedFraction)
                    }
                }
                .frame(height: 6)
                HStack {
                    if let last = model.settings.lastCleanDate {
                        Text("Last clean \(last.relativeDescription) · \(ByteFormatter.string(model.settings.lastCleanFreedBytes))")
                    } else { Text("No clean yet") }
                    Spacer()
                    if let t = model.thermal.cpuMax { Text("\(Int(t))°").monospacedDigit() }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
