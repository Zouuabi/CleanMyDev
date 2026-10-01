import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    
    var body: some View {
        NavigationStack {
            if viewModel.isSandboxed {
                SandboxWarningView()
            } else {
                HomeView(viewModel: viewModel)
                    .navigationDestination(for: String.self) { destination in
                        if destination == "Simulators" {
                            SimulatorListView()
                        }
                    }
                    .navigationDestination(isPresented: $viewModel.shouldNavigateToResults) {
                        ResultsView(viewModel: viewModel)
                    }
                    .navigationDestination(for: DiskInfo.self) { disk in
                        DiskDetailView(disk: disk, viewModel: viewModel)
                    }
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
    }
}

struct SandboxWarningView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundStart, Theme.backgroundEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                Text("SANDBOX RESTRICTED")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("This app cannot access your files because App Sandbox is enabled.\nPlease disable 'App Sandbox' in Xcode Project Settings > Signing & Capabilities.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding()
            }
        }
    }
}
