import SwiftUI

struct DiskDetailView: View {
    let disk: DiskInfo
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(colors: [Theme.backgroundStart, Theme.backgroundEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 60))
                            .foregroundColor(Theme.neonBlue)
                        Text(disk.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("\(disk.formattedFree) Free of \(disk.formattedTotal)")
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                    
                    if viewModel.isAnalyzing {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Analyzing Storage...")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                        .frame(height: 300)
                    } else {
                        // Analysis Results
                        
                        // 1. File Groups Chart (Simple Bar List for now)
                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("STORAGE BREAKDOWN")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.gray)
                                
                                ForEach(viewModel.diskAnalysisGroups) { group in
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: group.type.colorHex))
                                            .frame(width: 8, height: 8)
                                        Text(group.type.rawValue)
                                            .foregroundColor(.white)
                                            .frame(width: 80, alignment: .leading)
                                        
                                        // Pseodo-bar
                                        GeometryReader { proxy in
                                            ZStack(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.white.opacity(0.1))
                                                    .frame(height: 8)
                                                
                                                if let max = viewModel.diskAnalysisGroups.first?.totalSize, max > 0 {
                                                    let width = CGFloat(group.totalSize) / CGFloat(max) * proxy.size.width
                                                    Capsule()
                                                        .fill(Color(hex: group.type.colorHex))
                                                        .frame(width: width, height: 8)
                                                }
                                            }
                                        }
                                        .frame(height: 8)
                                        
                                        Text(group.formattedSize)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .frame(width: 70, alignment: .trailing)
                                    }
                                }
                            }
                            .padding()
                        }
                        .padding(.horizontal)
                        
                        // 2. Large Files List
                        VStack(alignment: .leading) {
                            Text("LARGEST FILES")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.largeFiles) { file in
                                    GlassCard {
                                        HStack {
                                            Image(systemName: "doc.fill")
                                                .font(.title2)
                                                .foregroundColor(Color(hex: file.type.colorHex))
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(file.name)
                                                    .font(.body)
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                Text(file.path.path)
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                            
                                            Spacer()
                                            
                                            VStack(alignment: .trailing) {
                                                Text(file.formattedSize)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                
                                                Button("Show") {
                                                    NSWorkspace.shared.selectFile(file.path.path, inFileViewerRootedAtPath: "")
                                                }
                                                .font(.caption2)
                                                .buttonStyle(.plain)
                                                .foregroundColor(Theme.neonBlue)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            viewModel.selectDisk(disk)
        }
    }
}
