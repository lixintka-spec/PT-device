import SwiftUI

/// Range's visual language: a calm, clinical-premium dark UI with one living accent (mint)
/// for motion you've earned, amber for goals, coral for anything that needs attention.
enum RangeTheme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let backgroundTop = Color(red: 0.07, green: 0.11, blue: 0.19)
    static let panel = Color.white.opacity(0.06)
    static let panelStroke = Color.white.opacity(0.10)
    static let mint = Color(red: 0.38, green: 0.93, blue: 0.78)
    static let amber = Color(red: 1.00, green: 0.76, blue: 0.32)
    static let coral = Color(red: 1.00, green: 0.47, blue: 0.43)
    static let sky = Color(red: 0.49, green: 0.74, blue: 1.00)
    static let lilac = Color(red: 0.72, green: 0.62, blue: 1.00)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.40)

    static let skinLight = Color(red: 0.96, green: 0.80, blue: 0.69)
    static let skinDark = Color(red: 0.82, green: 0.60, blue: 0.49)

    static var backdrop: some View {
        LinearGradient(colors: [backgroundTop, background], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    static func numeral(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// A rounded glass-like panel used throughout the app.
struct PanelBackground: ViewModifier {
    var cornerRadius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(RangeTheme.panel, in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(RangeTheme.panelStroke))
    }
}

extension View {
    func rangePanel(cornerRadius: CGFloat = 22) -> some View {
        modifier(PanelBackground(cornerRadius: cornerRadius))
    }
}

struct Chip: View {
    var text: String
    var systemImage: String? = nil
    var tint: Color = .white
    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: .capsule)
    }
}
