import SwiftUI

/// Draws a seated limb (thigh + shin, or upper arm + forearm) bending around a pivot, with the
/// iPhone Duo draped over the joint like a tent: inner screen against the skin, the fold on the
/// kneecap, and the outer display on the thigh half facing the patient. A straight limb holds the
/// phone flat (180°); bending closes it — flexion = 180° − hinge angle.
enum LimbPainter {
    struct Style {
        var skinLight = RangeTheme.skinLight
        var skinDark = RangeTheme.skinDark
        var showDevice = true
        var deviceGlow: Double = 0.6
        var kneeGlow: Double = 0.4
        var glowColor = RangeTheme.mint
        var showSurface = true
    }

    /// Math-convention direction (y up) converted to screen space.
    static func dir(_ degrees: Double) -> CGVector {
        let r = degrees * .pi / 180
        return CGVector(dx: cos(r), dy: -sin(r))
    }

    static func point(_ p: CGPoint, _ degrees: Double, _ length: CGFloat) -> CGPoint {
        let d = dir(degrees)
        return CGPoint(x: p.x + d.dx * length, y: p.y + d.dy * length)
    }

    /// Point along the moving segment's direction for a given flexion (seated: sweeps downward).
    static func jointPoint(_ pivot: CGPoint, flexion: Double, tilt: Double, _ r: CGFloat) -> CGPoint {
        point(pivot, -flexion - tilt, r)
    }

    static func draw(in ctx: inout GraphicsContext, pivot: CGPoint, length L: CGFloat,
                     flexion: Double, tilt: Double, joint: Joint, style: Style = Style()) {
        let thighDir = 180 - tilt
        let shinDir = -flexion - tilt   // seated: the lower leg swings down as the knee bends
        let thighLen = L * 1.35
        let shinLen = L * (joint == .knee ? 0.95 : 0.9)
        let thighW0 = L * (joint == .knee ? 0.27 : 0.22)   // at the joint
        let thighW1 = L * (joint == .knee ? 0.36 : 0.26)   // far end
        let shinW0 = L * (joint == .knee ? 0.23 : 0.20)
        let shinW1 = L * (joint == .knee ? 0.13 : 0.15)

        // Surface (bed / table) the stable segment should rest on.
        if style.showSurface {
            let y = pivot.y + thighW0 / 2 + 6
            var surface = Path()
            surface.move(to: CGPoint(x: pivot.x - thighLen - 40, y: y))
            surface.addLine(to: CGPoint(x: pivot.x - L * 0.12, y: y))
            ctx.stroke(surface, with: .color(.white.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 8]))
        }

        let hip = point(pivot, thighDir, thighLen)
        let ankle = point(pivot, shinDir, shinLen)

        // Far segment first so the moving segment sits on top.
        drawSegment(&ctx, from: hip, to: pivot, w0: thighW1, w1: thighW0, style: style, fadeStart: true)

        // Foot or hand.
        if joint == .knee {
            // Seated: the foot points forward, perpendicular to the shin.
            let heel = point(ankle, shinDir - 90, shinW1 * 0.35)
            let toe = point(ankle, shinDir + 90, L * 0.30)
            drawSegment(&ctx, from: heel, to: toe, w0: shinW1 * 1.15, w1: shinW1 * 0.62, style: style)
        } else {
            let hand = point(ankle, shinDir, L * 0.22)
            drawSegment(&ctx, from: ankle, to: hand, w0: shinW1 * 1.1, w1: shinW1 * 1.25, style: style)
        }
        drawSegment(&ctx, from: pivot, to: ankle, w0: shinW0, w1: shinW1, style: style)

        // Kneecap / elbow joint glow.
        let glowR = L * 0.2
        ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - glowR, y: pivot.y - glowR, width: glowR * 2, height: glowR * 2)),
                 with: .radialGradient(Gradient(colors: [style.glowColor.opacity(style.kneeGlow), .clear]),
                                       center: pivot, startRadius: 0, endRadius: glowR))
        let jointR = L * 0.045
        ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - jointR, y: pivot.y - jointR, width: jointR * 2, height: jointR * 2)),
                 with: .color(.white.opacity(0.85)))

        // The phone: tented over the front of the joint, hinge on the kneecap.
        if style.showDevice {
            let plateLen = L * 0.46
            let gap: CGFloat = 5
            let thighNormal = thighDir - 90   // top (front) of the thigh
            let shinNormal = shinDir + 90     // front of the shin
            // Both halves meet at one hinge point: where the two offset surfaces intersect.
            let a1 = point(pivot, thighNormal, thighW0 / 2 + gap)
            let a2 = point(pivot, shinNormal, shinW0 / 2 + gap)
            let d1 = dir(thighDir), d2 = dir(shinDir)
            let denom = d1.dx * d2.dy - d1.dy * d2.dx
            var hingePoint = CGPoint(x: (a1.x + a2.x) / 2, y: (a1.y + a2.y) / 2)
            if abs(denom) > 0.05 {
                let t = ((a2.x - a1.x) * d2.dy - (a2.y - a1.y) * d2.dx) / denom
                let candidate = CGPoint(x: a1.x + d1.dx * t, y: a1.y + d1.dy * t)
                if hypot(candidate.x - pivot.x, candidate.y - pivot.y) < L * 0.6 { hingePoint = candidate }
            }
            drawPlate(&ctx, origin: hingePoint, direction: thighDir,
                      normal: thighNormal, length: plateLen, style: style, glowing: true)   // outer display faces you
            drawPlate(&ctx, origin: hingePoint, direction: shinDir,
                      normal: shinNormal, length: plateLen * 0.92, style: style, glowing: false)
        }
    }

    private static func drawSegment(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                                    w0: CGFloat, w1: CGFloat, style: Style, fadeStart: Bool = false) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.001, sqrt(dx * dx + dy * dy))
        let nx = -dy / len, ny = dx / len
        var path = Path()
        path.move(to: CGPoint(x: a.x + nx * w0 / 2, y: a.y + ny * w0 / 2))
        path.addLine(to: CGPoint(x: b.x + nx * w1 / 2, y: b.y + ny * w1 / 2))
        path.addLine(to: CGPoint(x: b.x - nx * w1 / 2, y: b.y - ny * w1 / 2))
        path.addLine(to: CGPoint(x: a.x - nx * w0 / 2, y: a.y - ny * w0 / 2))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: a.x - w0 / 2, y: a.y - w0 / 2, width: w0, height: w0))
        path.addEllipse(in: CGRect(x: b.x - w1 / 2, y: b.y - w1 / 2, width: w1, height: w1))

        let light = CGPoint(x: (a.x + b.x) / 2 + nx * w0 / 2, y: (a.y + b.y) / 2 + ny * w0 / 2)
        let dark = CGPoint(x: (a.x + b.x) / 2 - nx * w0 / 2, y: (a.y + b.y) / 2 - ny * w0 / 2)
        var shading = ctx
        if fadeStart {
            shading.clipToLayer { layer in
                layer.fill(path, with: .linearGradient(Gradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.45),
                ]), startPoint: a, endPoint: b))
            }
        }
        shading.fill(path, with: .linearGradient(Gradient(colors: [style.skinLight, style.skinDark]),
                                                 startPoint: light, endPoint: dark))
        // Subtle bone line for an anatomical read.
        var bone = Path()
        bone.move(to: a)
        bone.addLine(to: b)
        shading.stroke(bone, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: max(1.5, w1 * 0.08), lineCap: .round))
    }

    private static func drawPlate(_ ctx: inout GraphicsContext, origin: CGPoint, direction: Double,
                                  normal: Double, length: CGFloat, style: Style, glowing: Bool) {
        let thickness: CGFloat = max(11, length * 0.11)
        let end = point(origin, direction, length)
        let n = dir(normal)
        var body = Path()
        body.move(to: origin)
        body.addLine(to: end)
        ctx.stroke(body, with: .color(Color(white: 0.55)), style: StrokeStyle(lineWidth: thickness + 2, lineCap: .round))
        ctx.stroke(body, with: .color(Color(white: 0.12)), style: StrokeStyle(lineWidth: thickness, lineCap: .round))
        guard glowing else { return }
        // The outer display faces the patient and glows.
        let o2 = CGPoint(x: origin.x + n.dx * thickness * 0.42, y: origin.y + n.dy * thickness * 0.42)
        let e2 = CGPoint(x: end.x + n.dx * thickness * 0.42, y: end.y + n.dy * thickness * 0.42)
        var screen = Path()
        screen.move(to: o2)
        screen.addLine(to: e2)
        ctx.stroke(screen, with: .color(style.glowColor.opacity(style.deviceGlow)),
                   style: StrokeStyle(lineWidth: max(3, thickness * 0.34), lineCap: .round))
    }

    // MARK: - Protractor

    struct Marks {
        var flexion: Double
        var tilt: Double
        var start: Double? = nil
        var lastBest: Double?
        var ghost: Double?
        var target: Double?
        var inTarget: Bool
        var pulse: Double
    }

    static func drawProtractor(in ctx: inout GraphicsContext, pivot: CGPoint, radius R: CGFloat, marks m: Marks) {
        func p(_ deg: Double, _ r: CGFloat) -> CGPoint { jointPoint(pivot, flexion: deg, tilt: m.tilt, r) }

        // Base arc.
        var base = Path()
        for d in stride(from: 0.0, through: 180.0, by: 2) {
            d == 0 ? base.move(to: p(d, R)) : base.addLine(to: p(d, R))
        }
        ctx.stroke(base, with: .color(.white.opacity(0.14)), lineWidth: 1.5)

        // Earned wedge: from the chosen start to where the joint is now.
        let from = min(m.start ?? 0, m.flexion)
        var wedge = Path()
        wedge.move(to: pivot)
        for d in stride(from: from, through: m.flexion, by: 1) { wedge.addLine(to: p(d, R)) }
        wedge.addLine(to: p(m.flexion, R))
        wedge.closeSubpath()
        let accent = m.inTarget ? RangeTheme.amber : RangeTheme.mint
        ctx.fill(wedge, with: .radialGradient(Gradient(colors: [accent.opacity(0.02), accent.opacity(0.22 + 0.1 * m.pulse)]),
                                              center: pivot, startRadius: 0, endRadius: R))
        // Chosen start.
        if let start = m.start, start > 0.5 {
            var line = Path()
            line.move(to: pivot)
            line.addLine(to: p(start, R + 20))
            ctx.stroke(line, with: .color(RangeTheme.sky.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            let dot = p(start, R + 20)
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(RangeTheme.sky))
            ctx.draw(Text("Start \(Int(start))°").font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(RangeTheme.sky), at: p(start - 10, R + 36))
        }

        // Ticks every 5°, labels every 30°.
        for d in stride(from: 0, through: 180, by: 5) {
            let major = d % 30 == 0
            var tick = Path()
            tick.move(to: p(Double(d), R - (major ? 16 : 8)))
            tick.addLine(to: p(Double(d), R))
            let lit = Double(d) <= m.flexion
            ctx.stroke(tick, with: .color(lit ? accent.opacity(0.9) : .white.opacity(major ? 0.45 : 0.22)),
                       lineWidth: major ? 2 : 1.2)
            if major {
                let text = Text("\(d)°").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.45))
                ctx.draw(text, at: p(Double(d), R + 16))
            }
        }

        // Ghost range: every new best leaves a translucent arc to beat.
        if let ghost = m.ghost, ghost > 1 {
            var g = Path()
            for d in stride(from: 0.0, through: ghost, by: 1) {
                d == 0 ? g.move(to: p(d, R + 34)) : g.addLine(to: p(d, R + 34))
            }
            g.addLine(to: p(ghost, R + 34))
            ctx.stroke(g, with: .color(RangeTheme.mint.opacity(0.35)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        }

        // Last best: dashed radial.
        if let last = m.lastBest {
            var l = Path()
            l.move(to: p(last, R * 0.35))
            l.addLine(to: p(last, R + 24))
            ctx.stroke(l, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
            ctx.draw(Text("Last \(Int(last))°").font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75)), at: p(last - 9, R * 0.62))
        }

        // Target.
        if let target = m.target {
            var t = Path()
            t.move(to: p(target, R * 0.25))
            t.addLine(to: p(target, R + 28))
            ctx.stroke(t, with: .color(RangeTheme.amber), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            let dot = p(target, R + 28)
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(RangeTheme.amber))
            ctx.draw(Text("Target \(Int(target))°").font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(RangeTheme.amber), at: p(target + 14, R + 40))
        }
    }
}

/// Animatable limb used for replays and illustrations.
struct LimbFigure: View, Animatable {
    var flexion: Double
    var tilt: Double = 0
    var joint: Joint = .knee
    var arcs: [(Double, Color)] = []
    var showDevice = true
    var showScale = false

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(flexion, tilt) }
        set { flexion = newValue.first; tilt = newValue.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let L = min(size.width * 0.33, size.height * 0.46)
            let pivot = CGPoint(x: size.width * 0.46, y: size.height * 0.26)
            if showScale {
                LimbPainter.drawProtractor(in: &ctx, pivot: pivot, radius: L * 1.05,
                                           marks: .init(flexion: flexion, tilt: tilt, lastBest: nil, ghost: nil,
                                                        target: nil, inTarget: false, pulse: 0))
            }
            for (i, arc) in arcs.enumerated() {
                var path = Path()
                let r = L * (1.12 + CGFloat(i) * 0.1)
                for d in stride(from: 0.0, through: arc.0, by: 1) {
                    let pt = LimbPainter.jointPoint(pivot, flexion: d, tilt: tilt, r)
                    d == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                ctx.stroke(path, with: .color(arc.1), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            LimbPainter.draw(in: &ctx, pivot: pivot, length: L, flexion: flexion, tilt: tilt, joint: joint,
                             style: .init(showDevice: showDevice))
        }
    }
}
