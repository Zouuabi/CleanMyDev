import SwiftUI
import CleanCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ZStack {
                ThemeBackground(theme: model.selection.theme)
                detail(for: model.selection)
                    .id(model.selection)
                    .transition(.opacity)
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .navigationTitle("")
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .smartCare: SmartCareView()
        case .projects: ProjectsView()
        case .ports: PortsView()
        case .startupItems: StartupItemsView()
        case .uninstaller: UninstallerView()
        case .spaceLens: SpaceLensView()
        case .quarantine: QuarantineView()
        default: ModuleScreen(scope: item)
        }
    }
}
