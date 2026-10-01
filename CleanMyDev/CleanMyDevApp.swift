import SwiftUI

@main
struct CleanMyDevApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Enforce Dark Mode for the "Futuristic" look
                .preferredColorScheme(.dark)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands() // Standard commands
        }
    }
}
