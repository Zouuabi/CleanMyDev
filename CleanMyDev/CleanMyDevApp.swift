import SwiftUI
import CleanCore

@main
struct CleanMyDevApp: App {
    @State private var model = AppModel()

    init() {
        if CommandLine.arguments.contains("--background-clean") {
            Task.detached {
                await Scheduler.runBackgroundClean()
                exit(0)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)

        MenuBarExtra(isInserted: Binding(get: { model.settings.menuBarEnabled }, set: { if model.settings.menuBarEnabled != $0 { model.settings.menuBarEnabled = $0 } })) {
            MenuBarView().environment(model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                if let s = model.stats {
                    Text(ByteFormatter.string(s.diskFree)).font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model).frame(width: 640, height: 620)
        }
    }
}
