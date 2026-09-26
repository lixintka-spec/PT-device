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
        @Bindable var session = session
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
            .navigationTitle(session.phase.isActive ? session.exercise.title : "Exercise")
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
                ToolbarOverflowMenu {
                    Button { app.showPlacementGuide = true } label: { Label("How to Wear", systemImage: "figure.stand") }
                    Button { app.isMuted.toggle() } label: {
                        Label(app.isMuted ? "Unmute" : "Mute", systemImage: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    if hinge.isManual || leveler.isManual {
                        Button { hinge.useHardware(); leveler.useSensor() } label: {
                            Label("Use Hinge & Sensors", systemImage: "rectangle.portrait.on.rectangle.portrait")
                        }
                    }
                    Button { app.showDemoControls = true } label: { Label("Demo Controls", systemImage: "slider.horizontal.3") }
                    if session.phase == .positioning {
                        Button { session.lockStart() } label: { Label("Start Here", systemImage: "flag.fill") }
                    } else if session.phase.isActive {
                        Button { session.changeStart() } label: { Label("Change Start Position", systemImage: "arrow.left.and.right") }
                    }
                    if session.phase.isActive {
                        Picker(selection: $session.repGoal) {
                            ForEach([5, 8, 10, 12, 15, 20], id: \.self) { Text("\($0) reps").tag($0) }
                        } label: {
                            Label("Rep Goal", systemImage: "repeat")
                        }
                        .pickerStyle(.menu)
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
        @Bindable var session = session
        ArrangementView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let maria = primary.first {
                        Chip(text: "Day \(maria.dayToday) · \(maria.side.title) \(maria.joint.title.lowercased())", systemImage: "calendar", tint: RangeTheme.sky)
                        Text("Today's session")
                            .font(.largeTitle.bold())
                        Text("Last time you reached **\(Int(maria.bestBeforeToday))°**. Today, aim for **\(Int(maria.adaptiveTarget))°**.")
                            .font(.title3)
                            .foregroundStyle(RangeTheme.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        StepRow(number: 1, title: "Choose your start", detail: "Straight or bent — start wherever is comfortable. Hold still to lock it, or tap Start here.")
                        StepRow(number: 2, title: "Bend, hold, come back", detail: "Bend to the amber dot, hold still for \(Int(SessionEngine.holdSeconds)) seconds while the ring fills, then come back to the blue dot. That's one rep.")
                        StepRow(number: 3, title: "Do \(session.repGoal) reps", detail: "Rep 1 aims for your last best (\(Int(session.lastBest))°), then \(Int(session.target))°.")
                        StepRow(number: 4, title: "Close the phone to save", detail: "Your recovery replays on the outside.")
                    }
                    .padding(18)
                    .rangePanel()
                    RepGoalPicker(goal: $session.repGoal)
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

/// The session in one glance: the leg, the angle, one instruction, and one button only when needed.
/// Drag the leg to test without folding the phone.
struct SessionLiveView: View {
    @Environment(SessionEngine.self) private var session
    @Environment(HingeEngine.self) private var hinge
    @Environment(Leveler.self) private var leveler
    private enum Grab { case thigh, lowerLeg }
    @State private var grab: Grab?

    var body: some View {
        GeometryReader { proxy in
            let layout = FoldLayout(proxy)
            let size = proxy.size
            // Inner display: the knee sits on the physical crease. Outer display (no fold):
            // leg on the left, text on the right, nothing overlapping.
            let onCrease = layout.hasFold
            // Narrow portrait screen (outer display held upright): text on top, leg below.
            let stacked = !onCrease && size.height > size.width
            let pivotY = layout.creaseY.map { min(size.height * 0.6, max(size.height * 0.3, $0)) }
                ?? size.height * (onCrease ? 0.46 : (stacked ? 0.58 : 0.36))
            let pivot = CGPoint(x: onCrease ? layout.creaseX : size.width * (stacked ? 0.56 : 0.34), y: pivotY)
            let L = onCrease
                ? min(min(layout.creaseX, size.width - layout.creaseX) * 0.62, size.height * 0.36)
                : (stacked ? min(size.width * 0.30, size.height * 0.2) : min(size.width * 0.22, size.height * 0.34))
            let radius = min(L * 1.02, size.height - pivotY - (onCrease ? 80 : 60))
            let textWidth = onCrease ? min(380, max(240, layout.trailingWidth - 40)) : (stacked ? size.width - 48 : size.width * 0.38)
            // Folded shut and not being dragged: there's no knee to measure yet.
            let waitingToOpen = hinge.status == .closed && !hinge.isManual && session.phase == .positioning
            let shownFlexion = waitingToOpen ? 0 : hinge.flexion
            let holding = session.phase.isExercising && session.repStage == .hold
            let accent: Color = holding ? RangeTheme.amber : (session.phase == .positioning ? RangeTheme.sky : RangeTheme.mint)
            let exercising = session.phase.isExercising && !(session.goalReached && session.repStage == .out)
            let goal: Double? = exercising ? session.currentGoal : nil
            let comingBack = exercising && session.repStage == .back

            ZStack(alignment: .topLeading) {
                // The leg — drag it to test.
                Canvas { ctx, _ in
                    LimbPainter.drawGuide(in: &ctx, pivot: pivot, radius: radius,
                                          flexion: shownFlexion, tilt: leveler.tilt,
                                          start: session.hasStart ? session.startAngle : nil,
                                          ghost: session.sessionBest > 0 ? session.sessionBest : nil,
                                          target: goal, accent: accent,
                                          zoneFrom: exercising && !comingBack ? session.repTurn : nil,
                                          emphasizeStart: comingBack,
                                          holdProgress: holding ? session.holdProgress : nil)
                    LimbPainter.draw(in: &ctx, pivot: pivot, length: L, flexion: shownFlexion, tilt: leveler.tilt,
                                     joint: session.exercise.joint,
                                     style: .init(deviceGlow: 0.9, kneeGlow: holding ? 0.8 : 0.35, glowColor: accent))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if grab == nil {
                                // Whichever segment you touch first is the one you move.
                                let hip = LimbPainter.point(pivot, 180 - leveler.tilt, L * 1.35)
                                let ankle = LimbPainter.jointPoint(pivot, flexion: hinge.flexion, tilt: leveler.tilt, L * 1.1)
                                let toThigh = LimbPainter.distance(value.startLocation, toSegmentFrom: pivot, to: hip)
                                let toShin = LimbPainter.distance(value.startLocation, toSegmentFrom: pivot, to: ankle)
                                let nearKnee = hypot(value.startLocation.x - pivot.x, value.startLocation.y - pivot.y) < L * 0.18
                                grab = (toThigh < toShin && !nearKnee) ? .thigh : .lowerLeg
                            }
                            switch grab {
                            case .thigh:
                                leveler.setManual(tilt: LimbPainter.thighTilt(at: value.location, pivot: pivot))
                            default:
                                hinge.setManual(flexion: LimbPainter.flexion(at: value.location, pivot: pivot, tilt: leveler.tilt))
                            }
                        }
                        .onEnded { _ in grab = nil }
                )
                .accessibilityLabel("Knee at \(Int(hinge.flexion.rounded())) degrees, thigh \(Int(abs(leveler.tilt).rounded())) degrees off level")
                .accessibilityHint("Drag the lower leg to bend the knee, or the thigh to tilt it")

                // Leading: only what needs attention.
                StatusCorner()
                    .frame(width: onCrease ? min(300, max(200, layout.leadingWidth - 48)) : (stacked ? size.width - 48 : size.width * 0.4),
                           alignment: .leading)
                    .padding(.leading, 24)
                    .padding(.top, stacked ? max(0, size.height - 190) : 20)

                // Trailing: the number and one instruction.
                VStack(alignment: stacked ? .leading : .trailing, spacing: 6) {
                    // Every rep, the same three moves — the current one lit.
                    if exercising {
                        RepLoopIndicator(stage: session.repStage, holdMissed: session.holdMissed, large: onCrease)
                            .padding(.bottom, 6)
                    }
                    Text(waitingToOpen ? "Open the phone" : session.headline)
                        .font(holding ? .largeTitle.weight(.bold) : .title2.weight(.semibold))
                        .multilineTextAlignment(stacked ? .leading : .trailing)
                        .foregroundStyle(holding ? (session.holdPaused ? RangeTheme.coral : RangeTheme.amber) : .white)
                        .contentTransition(.interpolate)
                    if holding {
                        HoldCountdown(remaining: session.holdRemaining, progress: session.holdProgress,
                                      paused: session.holdPaused, degrees: hinge.flexion,
                                      diameter: onCrease ? 190 : 120)
                            .padding(.vertical, 4)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(waitingToOpen ? "—" : "\(Int(hinge.flexion.rounded()))")
                                .font(RangeTheme.numeral(onCrease ? 112 : 72, weight: .bold))
                                .contentTransition(.numericText(value: hinge.flexion))
                            if !waitingToOpen {
                                Text("°").font(RangeTheme.numeral(onCrease ? 48 : 36, weight: .semibold)).foregroundStyle(RangeTheme.secondaryText)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white)
                    }
                    Text(waitingToOpen ? "Drape it over your knee and open it — or drag the leg to try"
                         : session.detail(flexion: hinge.flexion, isLevel: leveler.isLevel))
                        .font(onCrease ? .title3 : .subheadline)
                        .multilineTextAlignment(stacked ? .leading : .trailing)
                        .foregroundStyle(RangeTheme.secondaryText)
                        .contentTransition(.interpolate)
                    if session.phase == .positioning && !waitingToOpen {
                        Button { session.lockStart() } label: {
                            Label("Start here", systemImage: "flag.fill").font(.headline).padding(.horizontal, 8)
                        }
                        .disabled(!session.canStart(at: hinge.flexion))
                        .buttonStyle(.borderedProminent)
                        .tint(RangeTheme.sky)
                        .foregroundStyle(.black)
                        .padding(.top, 8)
                    }
                }
                .frame(width: textWidth, alignment: stacked ? .leading : .trailing)
                .padding(.top, 20 + layout.cameraInset(for: CGRect(x: size.width - 400, y: 0, width: 400, height: 220)))
                .padding(.horizontal, stacked ? 24 : 0)
                .padding(.trailing, stacked ? 0 : 28)
                .frame(maxWidth: .infinity, alignment: stacked ? .leading : .trailing)
                .animation(.spring(duration: 0.35), value: session.phase)
                .animation(.spring(duration: 0.35), value: session.repStage)

                // Big moments only (new best, slow down, milestone).
                if let toast = session.toast, toast.kind != .info {
                    ToastView(toast: toast)
                        .frame(maxWidth: min(360, max(250, layout.leadingWidth - 110)))
                        .position(x: max(145, (layout.leadingWidth - 70) / 2), y: size.height - 64)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                }

                if hinge.isManual || leveler.isManual {
                    ManualControlPill { hinge.useHardware(); leveler.useSensor() }
                        .position(x: onCrease ? layout.creaseX + max(layout.trailingWidth, 280) / 2 : size.width - 120,
                                  y: size.height - 36)
                }
            }
            .animation(.spring(duration: 0.4), value: session.toast)
        }
    }
}

/// Top-leading corner: the leveler while choosing a start, a warning if the thigh lifts,
/// otherwise a quiet rep count.
private struct StatusCorner: View {
    @Environment(SessionEngine.self) private var session
    @Environment(Leveler.self) private var leveler

    var body: some View {
        Group {
            if session.phase == .positioning {
                LevelVial(tilt: leveler.tilt, label: "\(session.exercise.stableSegment.capitalized) level",
                          isSimulated: leveler.isSimulated, compact: true)
                    .padding(14)
                    .rangePanel(cornerRadius: 18)
            } else if session.compensatingNow {
                Label(session.exercise.driftCue, systemImage: "level.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RangeTheme.coral)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RangeTheme.coral.opacity(0.14), in: .capsule)
            } else {
                RepProgress(done: session.cleanReps, goal: session.repGoal,
                            flagged: session.reps.count - session.cleanReps)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }
}

/// Shown while the leg is being dragged on screen instead of driven by the hinge.
struct ManualControlPill: View {
    var onUseHinge: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.draw.fill").foregroundStyle(RangeTheme.sky)
            Text("Touch control").font(.subheadline.weight(.semibold))
            Button("Use hinge", action: onUseHinge)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(RangeTheme.sky)
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .capsule)
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
            Text(summary.isNewBest ? "New personal best." : "Solid session. Consistency builds range.")
                .font(.headline)
                .foregroundStyle(summary.isNewBest ? RangeTheme.mint : RangeTheme.secondaryText)
            HStack {
                Chip(text: "\(Int(summary.start))° → \(Int(summary.peak.rounded()))°", systemImage: "flag.fill", tint: RangeTheme.sky)
                Chip(text: "\(summary.cleanReps) of \(summary.repGoal) reps", systemImage: "repeat",
                     tint: summary.cleanReps >= summary.repGoal ? RangeTheme.mint : .white)
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
