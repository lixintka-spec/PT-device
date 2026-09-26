import SwiftUI

/// Where the physical crease and camera are, from iPhone Duo reserved regions.
/// Inactive division regions still report the crease position (zero width when flat),
/// so the protractor stays pinned to the hinge in every pose.
struct FoldLayout {
    let size: CGSize
    let fold: CGRect?
    let foldActive: Bool
    let camera: CGRect?

    init(_ proxy: GeometryProxy) {
        size = proxy.size
        let divisions = proxy.reservedRegions(kind: .division, options: .includeInactive)
        fold = divisions.first?.frame
        foldActive = divisions.first?.isActive ?? false
        camera = proxy.reservedRegions(kind: .occlusion).first?.frame
    }

    var hasFold: Bool { fold != nil }
    var isVerticalFold: Bool {
        guard let fold else { return true }
        return fold.height >= fold.width
    }
    var creaseX: CGFloat {
        if let fold, isVerticalFold, fold.midX > 40, fold.midX < size.width - 40 { return fold.midX }
        return size.width / 2
    }
    var creaseY: CGFloat? {
        if let fold, !isVerticalFold { return fold.midY }
        return nil
    }
    var foldHalfWidth: CGFloat {
        guard let fold, isVerticalFold, foldActive else { return 12 }
        return max(12, fold.width / 2 + 8)
    }
    var leadingWidth: CGFloat { max(0, creaseX - foldHalfWidth) }
    var trailingWidth: CGFloat { max(0, size.width - creaseX - foldHalfWidth) }
    var isWide: Bool { size.width > size.height * 1.15 && size.width > 600 }

    /// Extra top inset for content that would sit under an active camera occlusion.
    func cameraInset(for rect: CGRect) -> CGFloat {
        guard let camera, camera.intersects(rect) else { return 0 }
        return camera.maxY - rect.minY + 8
    }
}

/// Spirit-level vial for the leveler.
struct LevelVial: View {
    var tilt: Double
    var label: String
    var isSimulated: Bool
    var compact = false

    private var tint: Color {
        abs(tilt) <= 5 ? RangeTheme.mint : (abs(tilt) <= 10 ? RangeTheme.amber : RangeTheme.coral)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(label, systemImage: "level.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RangeTheme.secondaryText)
                Spacer()
                Text(abs(tilt) < 0.5 ? "Level" : "\(Int(abs(tilt).rounded()))° off")
                    .font(RangeTheme.numeral(13, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                let w = geo.size.width
                let bubble: CGFloat = compact ? 22 : 26
                let travel = (w - bubble) / 2
                let offset = CGFloat(max(-1, min(1, tilt / 15))) * travel
                ZStack {
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.10), tint.opacity(0.22), tint.opacity(0.10)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                    // ±5° band
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
                        .frame(width: travel * (5 / 15) * 2 + bubble, height: geo.size.height - 8)
                    Circle()
                        .fill(RadialGradient(colors: [.white, tint], center: .topLeading, startRadius: 1, endRadius: bubble))
                        .frame(width: bubble, height: bubble)
                        .shadow(color: tint.opacity(0.6), radius: 6)
                        .offset(x: offset)
                        .animation(.spring(duration: 0.35), value: offset)
                }
            }
            .frame(height: compact ? 30 : 36)
            if isSimulated {
                Text("Simulated sensor · Simulator has no motion hardware")
                    .font(.caption2)
                    .foregroundStyle(RangeTheme.tertiaryText)
            }
        }
    }
}
