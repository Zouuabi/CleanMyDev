import SwiftUI
import CleanCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 320)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(for: model.selection)
                .id(model.selection)
                .transition(.opacity.combined(with: .scale(scale: 0.995)))
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .background { ThemeBackground(theme: model.selection.theme) }
        .tint(ModuleTheme.brand)
        .navigationTitle("")
        .task {
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--open"), i + 1 < args.count, let item = SidebarItem(rawValue: args[i + 1]) {
                model.selection = item
                if item == .spaceLens { model.scanDisk(root: CMConstants.home) }
            }
            if args.contains("--scan") { model.scan(model.selection) }
            if let i = args.firstIndex(of: "--demo"), i + 1 < args.count { model.runDemo(args[i + 1]) }
        }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .smartCare: SmartCareView()
        case .projects: ProjectsView()
        case .devStack: DevStackView()
        case .security: SecurityView()
        case .uninstaller: UninstallerView()
        case .spaceLens: SpaceLensView()
        case .quarantine: QuarantineView()
        case .startupItems: StartupItemsView()
        case .ports: PortsView()
        default: ModuleScreen(scope: item)
        }
    }
}
