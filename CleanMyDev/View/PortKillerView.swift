import SwiftUI

struct PortKillerView: View {
    @State private var ports: [OpenPort] = []
    @State private var isScanning: Bool = false
    
    private let service = PortService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Active Ports")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isScanning ? 360 : 0))
                        .animation(isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isScanning)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Theme.backgroundStart.opacity(0.5))
            
            // List
            ScrollView {
                LazyVStack(spacing: 12) {
                    if ports.isEmpty && !isScanning {
                        Text("No active listening ports found.")
                            .foregroundColor(.gray)
                            .padding(.top, 40)
                    }
                    
                    ForEach(ports) { port in
                        GlassCard {
                            HStack {
                                Image(systemName: port.iconName)
                                    .font(.title2)
                                    .foregroundColor(Theme.neonBlue)
                                    .frame(width: 40)
                                
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(":\(String(port.port))")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .fontDesign(.monospaced)
                                        
                                        Text(port.process)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.1))
                                            .cornerRadius(4)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Text("PID: \(port.pid)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Button(action: { killProcess(port) }) {
                                    Text("KILL")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Theme.neonPink.opacity(0.2))
                                        .foregroundColor(Theme.neonPink)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Theme.neonPink, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear(perform: refresh)
    }
    
    func refresh() {
        isScanning = true
        Task {
            let found = await service.listListeningPorts()
            await MainActor.run {
                self.ports = found
                self.isScanning = false
            }
        }
    }
    
    func killProcess(_ port: OpenPort) {
        Task {
            _ = await service.kill(pid: port.pid)
            // Wait a moment for system to release port
            try? await Task.sleep(nanoseconds: 500_000_000) 
            refresh()
        }
    }
}

extension Font {
    static var monospacedDesign: Font {
        .system(.body, design: .monospaced)
    }
}
