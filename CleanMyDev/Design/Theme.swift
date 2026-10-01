import SwiftUI
import CleanCore

/// One brand: teal. Sections get a sibling accent so the sidebar glass still
/// shifts subtly when you move around, but everything reads as one app.
enum ModuleTheme: Hashable {
    case smart, cleanup, developer, protection, applications, files, neutral

    static let brand = Color(hex: 0x2DD4BF)

    var gradient: [Color] {
        switch self {
        case .smart: [Color(hex: 0x0E4F55), Color(hex: 0x071E2A)]
        case .cleanup: [Color(hex: 0x0B4A45), Color(hex: 0x061C22)]
        case .developer: [Color(hex: 0x0B4458), Color(hex: 0x061B2A)]
        case .protection: [Color(hex: 0x0F4A5A), Color(hex: 0x081A26)]
        case .applications: [Color(hex: 0x0B4350), Color(hex: 0x061A24)]
        case .files: [Color(hex: 0x0A4A4A), Color(hex: 0x061E22)]
        case .neutral: [Color(hex: 0x173238), Color(hex: 0x0A161A)]
        }
    }

    var accent: Color {
        switch self {
        case .smart: Color(hex: 0x2DD4BF)
        case .cleanup: Color(hex: 0x34D399)
        case .developer: Color(hex: 0x22D3EE)
        case .protection: Color(hex: 0x5EEAD4)
        case .applications: Color(hex: 0x67E8F9)
        case .files: Color(hex: 0x99F6E4)
        case .neutral: Color(hex: 0x94A3B8)
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

struct ThemeBackground: View {
    let theme: ModuleTheme
    @State private var drift = false
    var body: some View {
        ZStack {
            LinearGradient(colors: theme.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [theme.accent.opacity(0.26), .clear], center: .init(x: drift ? 0.8 : 0.7, y: drift ? 0.2 : 0.3), startRadius: 0, endRadius: 640)
            RadialGradient(colors: [Color(hex: 0x14B8A6).opacity(0.14), .clear], center: .init(x: drift ? 0.15 : 0.05, y: drift ? 0.85 : 0.95), startRadius: 0, endRadius: 560)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: theme)
        .onAppear { withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true } }
    }
}

// MARK: - Liquid Glass

/// Content card on Liquid Glass, per Apple's guidance: the glass is applied
/// last, in a single rounded shape, with a faint tint so cards sit above the
/// gradient without stacking glass on glass inside them.
struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = 20
    var tint: Color? = nil
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.tint((tint ?? Color.black).opacity(tint == nil ? 0.16 : 0.22)), in: .rect(cornerRadius: radius))
    }
}

extension View {
    func glassCard(radius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(radius: radius, tint: tint))
    }
}

// MARK: - Components

struct StatusChip: View {
    let text: String
    let systemImage: String
    let tint: Color
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(tint)
            .glassEffect(.regular.tint(tint.opacity(0.25)), in: .capsule)
    }
}

/// Prominent teal glass button for the one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 24).padding(.vertical, 11)
            .foregroundStyle(.black.opacity(0.85))
            .glassEffect(.regular.tint(tint.opacity(configuration.isPressed ? 0.75 : 0.95)).interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.22), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 15).padding(.vertical, 8)
            .foregroundStyle(.white)
            .glassEffect(.regular.interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct RingGauge: View {
    let value: Double
    let tint: Color
    let center: String
    var lineWidth: CGFloat = 7
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: value)
            Text(center).font(.system(.callout, design: .rounded).weight(.bold)).foregroundStyle(.white).contentTransition(.numericText())
        }
    }
}

/// The hero button: a breathing teal orb with orbiting light.
struct BigScanButton: View {
    let title: String
    let tint: Color
    let isBusy: Bool
    let action: () -> Void
    @State private var breathe = false
    @State private var spin = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(tint.opacity(0.22), lineWidth: 1.5).frame(width: 176, height: 176)
                    .scaleEffect(breathe ? 1.08 : 0.96).opacity(breathe ? 0.3 : 0.9)
                Circle().stroke(tint.opacity(0.16), lineWidth: 1).frame(width: 206, height: 206)
                    .scaleEffect(breathe ? 1.04 : 0.98).opacity(breathe ? 0.2 : 0.7)
                Circle()
                    .trim(from: 0.0, to: 0.22)
                    .stroke(AngularGradient(colors: [tint.opacity(0), tint], center: .center), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.95), tint.opacity(0.45)], center: .topLeading, startRadius: 0, endRadius: 150))
                    .frame(width: 124, height: 124)
                    .shadow(color: tint.opacity(0.65), radius: breathe ? 34 : 22, y: 8)
                    .scaleEffect(breathe ? 1.03 : 1)
                Text(isBusy ? "Stop" : title).font(.title3.weight(.bold)).foregroundStyle(.black.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.55))
    }
}

struct SizeText: View {
    let bytes: UInt64
    var font: Font = .headline
    var body: some View {
        Text(ByteFormatter.string(bytes)).font(font).monospacedDigit().foregroundStyle(.white).contentTransition(.numericText())
    }
}

extension Date {
    var relativeDescription: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}

/// Live, animated dots for anything waiting on work.
struct PulseDots: View {
    let tint: Color
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(tint).frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.4 : 0.8).opacity(phase == i ? 1 : 0.45)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { _ in
                Task { @MainActor in withAnimation(.easeInOut(duration: 0.25)) { phase = (phase + 1) % 3 } }
            }
        }
    }
}
