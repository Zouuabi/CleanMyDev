import SwiftUI

struct SimulatorListView: View {
    @State private var simulators: [SimulatorDevice] = []
    private let service = SimulatorService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Xcode Simulators")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Theme.backgroundStart.opacity(0.5))
            
            // List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(simulators) { sim in
                        SimulatorRow(sim: sim, onRefresh: refresh)
                    }
                }
                .padding()
            }
        }
        .onAppear(perform: refresh)
    }
    
    func refresh() {
        Task {
            let devices = await service.listDevices()
            await MainActor.run {
                self.simulators = devices
            }
        }
    }
}

struct SimulatorRow: View {
    let sim: SimulatorDevice
    let onRefresh: () -> Void
    private let service = SimulatorService.shared
    
    var body: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading) {
                    Text(sim.name)
                        .font(.body)
                        .bold()
                        .foregroundColor(.white)
                    Text(sim.runtime)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if sim.isBooted {
                    Text("BOOTED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.neonGreen.opacity(0.2))
                        .foregroundColor(Theme.neonGreen)
                        .cornerRadius(4)
                }
                
                // Actions
                HStack(spacing: 12) {
                    if sim.isBooted {
                        Button(action: {
                            Task {
                                await service.shutdown(udid: sim.udid)
                                onRefresh()
                            }
                        }) {
                            Image(systemName: "power.circle.fill")
                                .foregroundColor(.orange)
                        }
                        .help("Shutdown")
                    } else {
                        Button(action: {
                            Task {
                                await service.boot(udid: sim.udid)
                                onRefresh() // Ideally poll for state change
                            }
                        }) {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(Theme.neonBlue)
                        }
                        .help("Boot")
                    }
                    
                    Button(action: {
                        Task {
                            await service.erase(udid: sim.udid)
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle")
                            .foregroundColor(.white)
                    }
                    .help("Factory Reset (Wipe Data)")
                    
                    Button(action: {
                        Task {
                            await service.delete(udid: sim.udid)
                            onRefresh()
                        }
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .help("Delete Simulator")
                }
                .buttonStyle(.plain)
                .font(.title2)
            }
        }
    }
}
