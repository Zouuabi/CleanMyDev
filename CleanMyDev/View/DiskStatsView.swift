import SwiftUI

struct DiskStatsView: View {
    let disk: DiskInfo
    
    var body: some View {
        GlassCard {
            HStack(spacing: 20) {
                // Circular Chart
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 10)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: disk.percentageUsed)
                        .stroke(
                            AngularGradient(gradient: Gradient(colors: [Theme.neonBlue, Theme.neonPink]), center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 80, height: 80)
                        .shadow(color: Theme.neonPink.opacity(0.5), radius: 8)
                    
                    VStack {
                        Text("\(Int(disk.percentageUsed * 100))%")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(disk.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack {
                        Circle().fill(Theme.neonGreen).frame(width: 6, height: 6)
                        Text("Free: \(disk.formattedFree)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Circle().fill(Color.gray).frame(width: 6, height: 6)
                        Text("Total: \(disk.formattedTotal)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "internaldrive")
                    .font(.system(size: 30))
                    .foregroundColor(Color.gray.opacity(0.5))
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: 400)
    }
}
