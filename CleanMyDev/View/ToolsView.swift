import SwiftUI

struct ToolsView: View {
    @State private var selectedTab: ToolTab = .simulators
    
    enum ToolTab {
        case simulators
        case ports
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Header
            HStack(spacing: 0) {
                TabButton(title: "Simulator Hangar", icon: "iphone", isSelected: selectedTab == .simulators) {
                    selectedTab = .simulators
                }
                TabButton(title: "Port Terminator", icon: "network", isSelected: selectedTab == .ports) {
                    selectedTab = .ports
                }
            }
            .background(Theme.backgroundStart)
            
            // Content
            ZStack {
                Theme.backgroundEnd.opacity(0.5).ignoresSafeArea()
                
                if selectedTab == .simulators {
                    SimulatorListView()
                } else {
                    PortKillerView()
                }
            }
        }
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Theme.neonBlue.opacity(0.1) : Color.clear)
            .foregroundColor(isSelected ? Theme.neonBlue : .gray)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(isSelected ? Theme.neonBlue : .clear),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}
