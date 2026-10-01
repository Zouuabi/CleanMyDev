import SwiftUI
import CleanCore

/// Per-module colour worlds, like CleanMyMac's gradient panes. Each module
/// gets a two-stop background gradient and an accent for its controls.
enum ModuleTheme: Hashable {
    case smart, cleanup, developer, protection, applications, files, neutral

    var gradient: [Color] {
        switch self {
        case .smart: [Color(hex: 0x3B1F7A), Color(hex: 0x120A2E)]
        case .cleanup: [Color(hex: 0x0E6B3C), Color(hex: 0x062A18)]
        case .developer: [Color(hex: 0x0B4F7A), Color(hex: 0x061F33)]
        case .protection: [Color(hex: 0x8A1B5C), Color(hex: 0x33081F)]
        case .applications: [Color(hex: 0x1F3A9A), Color(hex: 0x0B1540)]
        case .files: [Color(hex: 0x0E6B6B), Color(hex: 0x052B2B)]
        case .neutral: [Color(hex: 0x2A2A3A), Color(hex: 0x121218)]
        }
    }

    var accent: Color {
        switch self {
        case .smart: Color(hex: 0xC084FC)
        case .cleanup: Color(hex: 0x4ADE80)
        case .developer: Color(hex: 0x38BDF8)
        case .protection: Color(hex: 0xF472B6)
        case .applications: Color(hex: 0x818CF8)
        case .files: Color(hex: 0x2DD4BF)
        case .neutral: Color(hex: 0xA1A1AA)
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

struct ThemeBackground: View {
    let theme: ModuleTheme
    var body: some View {
        ZStack {
            LinearGradient(colors: theme.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [theme.accent.opacity(0.22), .clear], center: .init(x: 0.75, y: 0.25), startRadius: 0, endRadius: 600)
            RadialGradient(colors: [Color.white.opacity(0.06), .clear], center: .init(x: 0.1, y: 0.9), startRadius: 0, endRadius: 500)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: theme)
    }
}

// MARK: - Glass

struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = 18
    var tint: Color? = nil
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let tint {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.opacity(0.10))
                }
            }
            .glassEffect(.regular.tint(Color.black.opacity(0.18)), in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }
}

extension View {
    func glassCard(radius: CGFloat = 18, tint: Color? = nil) -> some View {
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
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
            .foregroundStyle(tint)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 26).padding(.vertical, 12)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .foregroundStyle(.black.opacity(0.85))
            .shadow(color: tint.opacity(configuration.isPressed ? 0.2 : 0.55), radius: configuration.isPressed ? 6 : 16, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            .foregroundStyle(.white)
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
                .animation(.easeOut(duration: 0.6), value: value)
            Text(center).font(.system(.callout, design: .rounded).weight(.bold)).foregroundStyle(.white)
        }
    }
}

struct BigScanButton: View {
    let title: String
    let tint: Color
    let isBusy: Bool
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(tint.opacity(0.18), lineWidth: 2).frame(width: 150, height: 150)
                    .scaleEffect(pulse ? 1.12 : 1).opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], center: .topLeading, startRadius: 0, endRadius: 140))
                    .frame(width: 118, height: 118)
                    .shadow(color: tint.opacity(0.6), radius: 24, y: 6)
                Text(isBusy ? "Stop" : title).font(.title3.weight(.bold)).foregroundStyle(.black.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .onAppear { pulse = true }
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
        Text(ByteFormatter.string(bytes)).font(font).monospacedDigit().foregroundStyle(.white)
    }
}

extension Date {
    var relativeDescription: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
