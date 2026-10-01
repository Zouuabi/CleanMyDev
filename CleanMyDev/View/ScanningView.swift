import SwiftUI

struct ScanningView: View {
    @ObservedObject var viewModel: AppViewModel
    
    @State private var rotation: Double = 0
    @State private var rippleScale: CGFloat = 0.5
    @State private var rippleOpacity: Double = 1.0
    
    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                // Outer Ripple
                Circle()
                    .stroke(Theme.neonBlue.opacity(0.3), lineWidth: 2)
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpacity)
                    .frame(width: 300, height: 300)
                
                // Scanning Radar
                Circle()
                    .strokeBorder(
                        AngularGradient(gradient: Gradient(colors: [.clear, Theme.neonBlue]), center: .center, angle: .degrees(0)),
                        lineWidth: 4
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(rotation))
                    .shadow(color: Theme.neonBlue, radius: 10)
                
                // Inner Core
                Circle()
                    .fill(Theme.backgroundEnd)
                    .frame(width: 180, height: 180)
                    .overlay(
                        VStack {
                            Image(systemName: "cpu")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                            Text("SCANNING")
                                .font(.caption)
                                .fontWeight(.bold)
                                .tracking(2)
                                .foregroundColor(.gray)
                        }
                    )
            }
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                
                withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                    rippleScale = 1.5
                    rippleOpacity = 0.0
                }
            }
            
            VStack(spacing: 12) {
                Text("Analyzing Directories")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(viewModel.scanningPath)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.gray)
                    .frame(height: 20)
                    .truncationMode(.middle)
                    .animation(.none, value: viewModel.scanningPath)
            }
        }
    }
}
