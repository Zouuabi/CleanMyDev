import SwiftUI

struct ResultsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        VStack {
            // Header Stats
            HStack {
                VStack(alignment: .leading) {
                    Text("System Scan Complete")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    Text("Optimization Ready")
                        .foregroundColor(.gray)
                }
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("RECLAIMABLE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.totalReclaimableSize, countStyle: .file))
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(Theme.neonGreen)
                        .shadow(color: Theme.neonGreen.opacity(0.5), radius: 10)
                }
            }
            .padding()
            
            // List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.items) { item in
                        ItemRow(item: item) {
                            viewModel.toggleSelection(for: item.id)
                        }
                    }
                }
                .padding()
            }
            
            // Action Bar
            GlassCard {
                HStack {
                    Text("\(viewModel.items.filter{ $0.isSelected }.count) items selected")
                        .foregroundColor(.gray)
                    Spacer()
                    Button(action: {
                        withAnimation {
                            viewModel.cleanSelected()
                        }
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("CLEAN NOW")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [Theme.neonBlue, Theme.neonPink], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Theme.neonPink.opacity(0.5), radius: 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

struct ItemRow: View {
    let item: CleanableItem
    let action: () -> Void
    
    var body: some View {
        GlassCard {
            HStack {
                Toggle("", isOn: Binding(get: { item.isSelected }, set: { _ in action() }))
                    .toggleStyle(CheckboxToggleStyle())
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: item.category.icon)
                            .foregroundColor(Color(hex: item.category.colorHex))
                        Text(item.category.rawValue.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.gray)
                    }
                    
                    Text(item.description)
                        .font(.body)
                        .foregroundColor(.white)
                    
                    Text(item.path.path)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(item.formattedSize)
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .foregroundColor(configuration.isOn ? Theme.neonGreen : .gray)
                .font(.system(size: 20))
        }
        .buttonStyle(.plain)
    }
}
