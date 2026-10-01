import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(colors: [Theme.backgroundStart, Theme.backgroundEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            // Grid Overlay Pattern
            GeometryReader { proxy in
                GridPattern()
                    .stroke(Color.white.opacity(0.03), lineWidth: 1)
            }
            .ignoresSafeArea()
            
            VStack {
                // Toolbar Area
                HStack {
                    Image(systemName: "cpu") 
                    Text("DEV CLEANER X")
                        .font(.headline)
                        .tracking(3)
                        
                    Spacer()
                }
                .padding()
                .foregroundColor(.white.opacity(0.8))
                .background(Material.thin)
                
                Spacer()
                
                // Main Dashboard Layout
                HStack(spacing: 40) {
                    
                    // Left Column (Vitals)
                    VStack(spacing: 20) {
                        // Updated to pass disks
                        ResourceWidget(stats: viewModel.systemStats, disks: viewModel.disks)
                            .frame(width: 300)
                        
                        // Simulators Shortcut
                        NavigationLink(destination: SimulatorListView()) {
                             GlassCard {
                                 HStack {
                                     Image(systemName: "iphone.gen3")
                                         .foregroundColor(.white)
                                     Text("Simulators")
                                         .foregroundColor(.white)
                                     Spacer()
                                     Image(systemName: "chevron.right")
                                         .foregroundColor(.gray)
                                 }
                                 .padding()
                                 .contentShape(Rectangle())
                             }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 300)
                    }
                    
                    // Center (Scan Button)
                    ZStack {
                        // Pulsing Rings
                        Circle()
                            .stroke(Theme.neonBlue.opacity(0.1), lineWidth: 2)
                            .frame(width: 300, height: 300)
                        
                        Circle()
                            .stroke(Theme.neonBlue.opacity(0.2), lineWidth: 1)
                            .frame(width: 260, height: 260)
                        
                        Button(action: {
                            withAnimation {
                                viewModel.startScan()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isScanning ? Theme.neonPink.opacity(0.1) : Theme.neonBlue.opacity(0.1))
                                    .frame(width: 220, height: 220)
                                    .overlay(
                                        Circle()
                                            .stroke(viewModel.isScanning ? Theme.neonPink : Theme.neonBlue, lineWidth: 2)
                                            .shadow(color: viewModel.isScanning ? Theme.neonPink : Theme.neonBlue, radius: 10)
                                    )
                                
                                VStack(spacing: 12) {
                                    if viewModel.isScanning {
                                        Image(systemName: "stop.circle")
                                            .font(.system(size: 60))
                                            .foregroundColor(Theme.neonPink)
                                        Text("STOP SCAN")
                                            .font(.title3)
                                            .fontWeight(.black)
                                            .foregroundColor(.white)
                                        Text(viewModel.scanningPath)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                            .frame(width: 180)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    } else {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 60))
                                            .foregroundColor(Theme.neonBlue)
                                        Text("SCAN SYSTEM")
                                            .font(.title3)
                                            .fontWeight(.black)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 350, height: 350)
                    
                    // Right Column (Ports)
                    VStack(spacing: 20) {
                        NavigationLink(destination: PortKillerView()) {
                            PortsWidget(ports: viewModel.topPorts)
                                .frame(width: 300)
                        }
                        .buttonStyle(.plain)
                        
                        // Placeholder for another shortcut (e.g. Docker)
                        GlassCard {
                            HStack {
                                Image(systemName: "shippingbox.fill")
                                    .foregroundColor(.white)
                                    .opacity(0.5)
                                Text("Docker Cleaner")
                                    .foregroundColor(.white)
                                    .opacity(0.5)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                        }
                        .frame(width: 300)
                        .opacity(0.6)
                    }
                }
                
                Spacer()
            }
        }
    }
}
