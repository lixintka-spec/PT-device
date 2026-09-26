import SwiftUI
import SwiftData

struct SessionScreen: View {
    @Environment(SessionEngine.self) private var session
    @Environment(HingeEngine.self) private var hinge
    @Environment(Leveler.self) private var leveler
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Patient> { $0.isPrimary }) private var primary: [Patient]

    var body: some View {
        NavigationStack {
            ZStack {
                RangeTheme.backdrop
                switch session.phase {
                case .ready:
                    SessionReadyView()
                case .complete:
                    SessionCompleteView()
                default:
                    SessionLiveView()
                }
            }
            .navigationTitle(session.phase.isActive ? session.exercise.title : "Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.phase.isActive {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            if let s = session.finish(patient: primary.first, context: context) { app.lastSummary = s }
                        } label: {
                            Label("Finish", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .visibilityPriority(.high)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { app.showPlacementGuide = true } label: {
                        Label("Placement", systemImage: "figure.stand")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { app.isMuted.toggle() } label: {
                        Label(app.isMuted ? "Unmute" : "Mute", systemImage: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                }
                .visibilityPriority(.low)
                ToolbarOverflowMenu {
                    Button { app.showDemoControls = true } label: { Label("Demo Controls", systemImage: "slider.horizontal.3") }
                    if session.phase == .positioning {
                        Button { session.lockStart() } label: { Label("Start Here", systemImage: "flag.fill") }
                    } else if session.phase.isActive {
                        Button { session.changeStart() } label: { Label("Change Start Position", systemImage: "arrow.left.and.right") }
                    }
                    Button(role: .destructive) { session.reset() } label: { Label("Restart Session", systemImage: "arrow.counterclockwise") }
                }
            }
            .background(MotionBodyAnchor { view in leveler.start(body: view) })
        }
        .onAppear {
            if session.phase == .ready, let maria = primary.first { session.configure(for: maria) }
        }
    }
}

// MARK: - Ready

struct SessionReadyView: View {
    @Environment(SessionEngine.self) private var session
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<Patient> { $0.isPrimary }) private var primary: [Patient]

    var body: some View {
        ArrangementView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let maria = primary.first {
                        Chip(text: "Day \(maria.dayToday) · \(maria.side.title) \(maria.joint.title.lowercased())", systemImage: "calendar", tint: RangeTheme.sky)
                        Text("Today's session")
                            .font(.largeTitle.bold())
                        Text("Your comfortable max is **\(Int(maria.comfortableMax))°**. Let's aim for **\(Int(maria.adaptiveTarget))°** today.")
                            .font(.title3)
                            .foregroundStyle(RangeTheme.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        StepRow(number: 1, title: "Choose your start", detail: "Straight or bent — start wherever is comfortable. Hold still to lock it, or tap Start here.")
                        StepRow(number: 2, title: "Match your last best", detail: "Fold to \(Int(session.lastBest))° — where you were last time.")
                        StepRow(number: 3, title: "Push past your ghost", detail: "Slow reps. Hold \(Int(session.target))° for five seconds.")
                        StepRow(number: 4, title: "Close the phone to save", detail: "Your recovery replays on the outside.")
                    }
                    .padding(18)
                    .rangePanel()
                    Button {
                        session.begin()
                    } label: {
                        Label("Start session", systemImage: "play.fill")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RangeTheme.mint)
                    .foregroundStyle(.black)
                }
                .padding(24)
            }
        } secondary: {
            PlacementCard(exercise: session.exercise)
                .padding(24)
        }
        .arrangementViewStyle(.split.axes(.horizontal))
    }
}

struct StepRow: View {
    var number: Int
    var title: String
    var detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(RangeTheme.numeral(15, weight: .bold))
                .frame(width: 28, height: 28)
                .background(RangeTheme.mint.opacity(0.18), in: .circle)
                .foregroundStyle(RangeTheme.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(RangeTheme.secondaryText)
            }
        }
    }
}

struct PlacementCard: View {
    var exercise: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How to wear it", systemImage: "figure.stand")
                .font(.headline)
            LimbFigure(flexion: 55, joint: exercise.joint)
                .frame(minHeight: 180)
                .accessibilityLabel("Illustration: phone strapped on the flexion side of the joint")
            Text(exercise.placement)
                .font(.subheadline.weight(.semibold))
            Text("A \(exercise.joint.fullExtensionLabel) holds it flat at 180°; bending closes it around the joint. Flexion = 180° − hinge angle. In this tent pose the outer screen faces you.")
                .font(.footnote)
                .foregroundStyle(RangeTheme.secondaryText)
        }
        .padding(18)
        .rangePanel()
    }
}

// MARK: - Live

struct SessionLiveView: View {
    @Environment(SessionEngine.self) private var session
    @Environment(HingeEngine.self) private var hinge
    @Environment(Leveler.self) private var leveler

    var body: some View {
        GeometryReader { proxy in
            let layout = FoldLayout(proxy)
            let size = proxy.size
            let pivotY = layout.creaseY.map { min(size.height * 0.6, max(size.height * 0.3, $0)) } ?? size.height * 0.5
            let pivot = CGPoint(x: layout.creaseX, y: pivotY)
            let L = min(min(layout.creaseX, size.width - layout.creaseX) * 0.6, size.height * 0.34)
            let radius = min(L * 1.02, size.height - pivotY - 64)
            let inTarget = session.phase == .holding

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    LimbPainter.drawProtractor(in: &ctx, pivot: pivot, radius: radius, marks: .init(
                        flexion: hinge.flexion, tilt: leveler.tilt,
                        start: session.hasStart ? session.startAngle : nil,
                        lastBest: session.lastBest,
                        ghost: session.sessionBest > 0 ? session.sessionBest : nil,
                        target: session.phase == .positioning ? nil : session.target,
                        inTarget: inTarget,
                        pulse: Double(session.tickPulse % 2)))
                    LimbPainter.draw(in: &ctx, pivot: pivot, length: L, flexion: hinge.flexion, tilt: leveler.tilt,
                                     joint: session.exercise.joint,
                                     style: .init(deviceGlow: 0.9, kneeGlow: inTarget ? 0.8 : 0.35,
                                                  glowColor: inTarget ? RangeTheme.amber : RangeTheme.mint))
                }
                .allowsHitTesting(false)

                // Leading half: position & reps.
                VStack(alignment: .leading, spacing: 14) {
                    LevelVial(tilt: leveler.tilt, label: "\(session.exercise.stableSegment.capitalized) level",
                              isSimulated: leveler.isSimulated)
                    if session.phase == .positioning {
                        PositionLockView(angle: hinge.flexion, progress: session.positionProgress,
                                         isLevel: leveler.isLevel) { session.lockStart() }
                    } else {
                        RepStrip(reps: session.reps, target: session.target, lastBest: session.lastBest)
                    }
                }
                .padding(18)
                .frame(width: min(340, max(220, layout.leadingWidth - 40)), alignment: .leading)
                .rangePanel()
                .padding(.leading, 20)
                .padding(.top, 16)

                // Trailing half: the number and the coach.
                VStack(alignment: .trailing, spacing: 6) {
                    Text(session.headline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(inTarget ? RangeTheme.amber : .white)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(hinge.flexion.rounded()))")
                            .font(RangeTheme.numeral(size.width > 700 ? 96 : 72, weight: .bold))
                            .contentTransition(.numericText(value: hinge.flexion))
                        Text("°").font(RangeTheme.numeral(44, weight: .semibold)).foregroundStyle(RangeTheme.secondaryText)
                    }
                    .foregroundStyle(inTarget ? RangeTheme.amber : .white)
                    Text(session.instruction)
                        .font(.callout)
                        .foregroundStyle(RangeTheme.secondaryText)
                        .multilineTextAlignment(.trailing)
                    if session.phase != .positioning {
                        let start = Chip(text: "Start \(Int(session.startAngle))°", systemImage: "flag.fill", tint: RangeTheme.sky)
                        let last = Chip(text: "Last \(Int(session.lastBest))°", tint: .white)
                        let ghost = Chip(text: "Ghost \(Int(session.sessionBest.rounded()))°", systemImage: "sparkles", tint: RangeTheme.mint)
                        let target = Chip(text: "Target \(Int(session.target))°", systemImage: "scope", tint: RangeTheme.amber)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                start; last
                                if session.sessionBest > 0 { ghost }
                                target
                            }
                            VStack(alignment: .trailing, spacing: 6) {
                                HStack(spacing: 6) { start; last }
                                HStack(spacing: 6) {
                                    if session.sessionBest > 0 { ghost }
                                    target
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    if session.phase == .holding {
                        HoldRing(remaining: session.holdRemaining)
                            .frame(width: 64, height: 64)
                            .padding(.top, 6)
                    }
                    if session.phase == .matchLastBest {
                        ProgressView(value: session.matchProgress)
                            .tint(RangeTheme.mint)
                            .frame(width: 160)
                    }
                }
                .frame(width: min(360, max(220, layout.trailingWidth - 40)), alignment: .trailing)
                .padding(.top, 16 + layout.cameraInset(for: CGRect(x: size.width - 380, y: 0, width: 380, height: 200)))
                .padding(.trailing, 24)
                .frame(maxWidth: .infinity, alignment: .trailing)

                if let toast = session.toast {
                    // Lower-leading corner: clear of the fold, the arc and the target line.
                    ToastView(toast: toast)
                        .frame(maxWidth: min(360, max(250, layout.leadingWidth - 110)))
                        .position(x: max(145, (layout.leadingWidth - 70) / 2), y: size.height - 64)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                }
            }
            .animation(.spring(duration: 0.4), value: session.toast)
            .animation(.spring(duration: 0.4), value: session.phase)
        }
    }
}

/// The patient decides where to start: any angle, as long as it's steady and level.
struct PositionLockView: View {
    var angle: Double
    var progress: Double
    var isLevel: Bool
    var onStartHere: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Start at \(Int(angle.rounded()))°", systemImage: "flag.fill")
                    .font(.headline)
                    .foregroundStyle(RangeTheme.sky)
                    .contentTransition(.numericText(value: angle))
                Spacer()
                Text(isLevel ? (progress > 0 ? "Hold \(Int(ceil(3 - progress * 3)))" : "Hold still") : "Level your thigh")
                    .font(RangeTheme.numeral(13, weight: .bold))
                    .foregroundStyle(isLevel ? RangeTheme.secondaryText : RangeTheme.amber)
            }
            ProgressView(value: progress).tint(RangeTheme.sky)
            Button(action: onStartHere) {
                Label("Start here", systemImage: "flag.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(RangeTheme.sky)
            .foregroundStyle(.black)
        }
    }
}

struct RepStrip: View {
    var reps: [Rep]
    var target: Double
    var lastBest: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reps").font(.caption.weight(.semibold)).foregroundStyle(RangeTheme.secondaryText)
                Spacer()
                Text("\(reps.count)").font(RangeTheme.numeral(15, weight: .bold))
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(reps.suffix(10)) { rep in
                    let color: Color = rep.compensated || rep.tooFast ? RangeTheme.coral
                        : (rep.peak >= target - 1 ? RangeTheme.amber : (rep.peak > lastBest ? RangeTheme.mint : .white.opacity(0.5)))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: 14, height: max(6, CGFloat(rep.peak) * 0.45))
                        .overlay(alignment: .top) {
                            if rep.tooFast { Image(systemName: "tortoise.fill").font(.system(size: 8)).offset(y: -12) }
                        }
                }
                if reps.isEmpty {
                    Text("Your reps appear here").font(.caption).foregroundStyle(RangeTheme.tertiaryText)
                }
            }
            .frame(height: 64, alignment: .bottom)
        }
    }
}

struct HoldRing: View {
    var remaining: Double
    var body: some View {
        ZStack {
            Circle().stroke(RangeTheme.amber.opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: remaining / 5)
                .stroke(RangeTheme.amber, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(ceil(remaining)))")
                .font(RangeTheme.numeral(22, weight: .bold))
                .foregroundStyle(RangeTheme.amber)
                .contentTransition(.numericText())
        }
        .animation(.linear(duration: 0.1), value: remaining)
    }
}

struct ToastView: View {
    var toast: CoachToast
    var tint: Color {
        switch toast.kind {
        case .info: RangeTheme.sky
        case .success: RangeTheme.mint
        case .warning: RangeTheme.coral
        case .milestone: RangeTheme.amber
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: toast.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.headline)
                if let detail = toast.detail {
                    Text(detail).font(.subheadline).foregroundStyle(RangeTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(tint.opacity(0.5), lineWidth: 1.5))
        .shadow(color: tint.opacity(0.25), radius: 18)
    }
}

// MARK: - Complete

struct SessionCompleteView: View {
    @Environment(SessionEngine.self) private var session
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<Patient> { $0.isPrimary }) private var primary: [Patient]

    var body: some View {
        ArrangementView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Chip(text: "Saved", systemImage: "checkmark.seal.fill", tint: RangeTheme.mint)
                    if let s = session.summary {
                        SummaryHeadline(summary: s)
                    }
                    HStack {
                        Button {
                            session.reset()
                        } label: {
                            Label("New session", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            app.tab = .progress
                        } label: {
                            Label("See progress", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RangeTheme.mint)
                        .foregroundStyle(.black)
                    }
                }
                .padding(24)
            }
        } secondary: {
            if let maria = primary.first {
                RecoveryReplayView(patient: maria)
                    .padding(24)
            }
        }
        .arrangementViewStyle(.split.axes(.horizontal))
    }
}

struct SummaryHeadline: View {
    var summary: SessionSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(summary.peak.rounded()))°")
                    .font(RangeTheme.numeral(64, weight: .bold))
                if summary.gain > 0.5 {
                    Text("+\(Int(summary.gain.rounded()))°")
                        .font(RangeTheme.numeral(28, weight: .bold))
                        .foregroundStyle(RangeTheme.mint)
                }
            }
            Text(summary.beyondNoise ? "Beyond measurement error — real progress." : "Solid session. Consistency builds range.")
                .font(.headline)
                .foregroundStyle(summary.beyondNoise ? RangeTheme.mint : RangeTheme.secondaryText)
            HStack {
                Chip(text: "\(Int(summary.start))° → \(Int(summary.peak.rounded()))°", systemImage: "flag.fill", tint: RangeTheme.sky)
                Chip(text: "\(summary.reps) reps", systemImage: "repeat")
                Chip(text: summary.targetHeld ? "Held \(Int(summary.target))°" : "Target \(Int(summary.target))°",
                     systemImage: "scope", tint: RangeTheme.amber)
            }
            if let m = summary.milestone {
                Label("Unlocked: \(m.title)", systemImage: m.symbol)
                    .font(.headline)
                    .foregroundStyle(RangeTheme.amber)
                    .padding(12)
                    .background(RangeTheme.amber.opacity(0.12), in: .rect(cornerRadius: 14))
            }
        }
    }
}
