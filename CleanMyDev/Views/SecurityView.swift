import SwiftUI
import CleanCore

struct SecurityView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Malware check").tag(0)
                Text("Startup items").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 320)
            .padding(.top, 14)
            if tab == 0 { ModuleScreen(scope: .security) } else { StartupItemsView() }
        }
    }
}
