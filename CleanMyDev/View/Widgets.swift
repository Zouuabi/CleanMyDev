import SwiftUI

struct ResourceWidget: View {
    let stats: SystemStats?
    let disks: [DiskInfo]
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                // Header with CPU/RAM Stats
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundColor(Theme.neonGreen)
                    Text("STORAGE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    // CPU/RAM Pills on Border
                    if let stats = stats {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text("CPU")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Text("\(Int(stats.cpuUsage * 100))%")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.neonPink)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(4)
                            
                            HStack(spacing: 4) {
                                Text("RAM")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Text("\(Int(stats.ramUsage * 100))%")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.neonBlue)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(4)
                        }
                    }
                }
                
                // Disks List
                if disks.isEmpty {
                    Text("No usage data")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    VStack(spacing: 12) {
                        ForEach(disks) { disk in
                           NavigationLink(value: disk) {
                               HStack(spacing: 12) {
                                   // Ring
                                   ZStack {
                                       Circle()
                                           .stroke(Color.white.opacity(0.1), lineWidth: 4)
                                           .frame(width: 40, height: 40)
                                       
                                       Circle()
                                           .trim(from: 0, to: disk.percentageUsed)
                                           .stroke(
                                               AngularGradient(gradient: Gradient(colors: [Theme.neonBlue, Theme.neonPink]), center: .center),
                                               style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                           )
                                           .rotationEffect(.degrees(-90))
                                           .frame(width: 40, height: 40)
                                   }
                                   
                                   VStack(alignment: .leading, spacing: 2) {
                                       Text(disk.name)
                                           .font(.subheadline)
                                           .fontWeight(.bold)
                                           .foregroundColor(.white)
                                       
                                       HStack {
                                           Text(disk.formattedFree + " free")
                                               .font(.caption2)
                                               .foregroundColor(.gray)
                                       }
                                   }
                                   
                                   Spacer()
                                   
                                   Text("\(Int(disk.percentageUsed * 100))%")
                                       .font(.caption)
                                       .fontWeight(.bold)
                                       .foregroundColor(.white)
                               }
                               .contentShape(Rectangle())
                           }
                           .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct PortsWidget: View {
    let ports: [OpenPort]
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(Theme.neonBlue)
                    Text("ACTIVE PORTS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.gray)
                }
                
                if ports.isEmpty {
                    Text("No active ports")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ports) { port in
                            HStack {
                                Circle()
                                    .fill(Theme.neonGreen)
                                    .frame(width: 6, height: 6)
                                Text(port.process)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(":\(port.port)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.neonBlue)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}
