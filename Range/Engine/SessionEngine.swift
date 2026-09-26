import SwiftUI
import SwiftData

enum Exercise: String, CaseIterable, Identifiable {
    case seatedKneeBend, elbowBend
    var id: String { rawValue }
    var joint: Joint { self == .seatedKneeBend ? .knee : .elbow }
    var title: String { self == .seatedKneeBend ? "Seated knee bend" : "Elbow bend at a table" }
    var stableSegment: String { self == .seatedKneeBend ? "thigh" : "upper arm" }
    var movingSegment: String { self == .seatedKneeBend ? "lower leg" : "forearm" }
    var startPosition: String {
        self == .seatedKneeBend
            ? "Sit tall, thigh flat on the chair, leg straight out."
            : "Upper arm flat on the table, arm straight."
    }
    var placement: String {
        self == .seatedKneeBend
            ? "Drape the phone over your knee like a tent — fold on the kneecap, inner screen against your leg."
            : "Drape the phone over your elbow like a tent — fold on the elbow tip, inner screen against your arm."
    }
    var driftCue: String { self == .seatedKneeBend ? "Keep your thigh flat on the chair" : "Keep your upper arm on the table" }
}

struct Rep: Identifiable, Hashable {
    let id = UUID()
    let peak: Double
    let compensated: Bool
    let tooFast: Bool
}

struct CoachToast: Identifiable, Equatable {
    enum Kind { case info, tip, success, warning, milestone }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String?
    let symbol: String
}

struct SessionSummary: Equatable {
    let start: Double
    let cleanReps: Int
    let repGoal: Int
    let peak: Double
    let previousBest: Double
    let reps: Int
    let targetHeld: Bool
    let target: Double
    let milestone: Milestone?
    var gain: Double { peak - previousBest }
    var beyondNoise: Bool { gain >= Clinical.measurementNoise }
}

@MainActor
@Observable
final class SessionEngine {
    enum Phase: Equatable {
        /// `.matchLastBest` is simply rep 1, aimed at yesterday's best instead of today's target.
        case ready, positioning, matchLastBest, reps, holding, complete
        var isActive: Bool { self != .ready && self != .complete }
        var isExercising: Bool { self == .matchLastBest || self == .reps || self == .holding }
    }

    /// Every rep is the same two moves: bend out to the goal, then come back to your start.
    enum RepStage { case out, back }

    // Configuration
    var exercise: Exercise = .seatedKneeBend
    private(set) var patientName = "Maria"
    private(set) var lastBest: Double = 92
    private(set) var comfortableMax: Double = 92
    private(set) var target: Double = 97
    private(set) var joint: Joint = .knee

    /// How many clean reps the patient chose to do (remembered between sessions).
    /// (Clamped by callers to 1...30; @Observable properties must not reassign themselves in didSet.)
    var repGoal: Int = min(30, max(1, UserDefaults.standard.object(forKey: "repGoal") as? Int ?? 10)) {
        didSet { UserDefaults.standard.set(repGoal, forKey: "repGoal") }
    }

    // Live state
    private(set) var phase: Phase = .ready
    private(set) var repStage: RepStage = .out
    private(set) var sessionBest: Double = 0
    private(set) var reps: [Rep] = []
    private(set) var positionProgress: Double = 0   // 0...1 over 3 s
    private(set) var holdRemaining: Double = 5
    private(set) var targetHeld = false
    private(set) var toast: CoachToast?
    private(set) var unlockedMilestone: Milestone?
    private(set) var summary: SessionSummary?
    private(set) var tickPulse = 0
    private(set) var compensatingNow = false
    /// Where the patient chose to start stretching (flexion°). Reps are measured from here.
    private(set) var startAngle: Double = 0

    var hasStart: Bool { phase != .ready && phase != .positioning }
    /// Reps that count: controlled and with the thigh level.
    var cleanReps: Int { reps.filter { !$0.compensated && !$0.tooFast }.count }
    var goalReached: Bool { cleanReps >= repGoal }

    /// Where this rep is aiming: yesterday's best on the first rep, today's target after that.
    var currentGoal: Double { phase == .matchLastBest ? lastBest : target }
    /// Reach this far and the rep is "out" — the chime plays and it's time to come back.
    var repTurn: Double { startAngle + max(6, (currentGoal - startAngle) * 0.8) }
    /// Back within this of your start and the rep counts.
    var repHome: Double { startAngle + max(4, (currentGoal - startAngle) * 0.15) }
    /// A start has to leave room to bend.
    func canStart(at flexion: Double) -> Bool { flexion <= target - 12 }

    // MARK: - Words on screen

    /// One short instruction — what to do right now.
    var headline: String {
        switch phase {
        case .ready: "Ready when you are"
        case .positioning: "Choose your start"
        case .holding: "Hold"
        case .complete: "Saved"
        case .matchLastBest, .reps:
            if goalReached && repStage == .out { "Set complete" }
            else if repStage == .out { "Bend to \(Int(currentGoal))°" }
            else { "Now back to \(Int(startAngle))°" }
        }
    }

    /// One supporting line, derived from the live angle.
    func detail(flexion: Double, isLevel: Bool) -> String {
        switch phase {
        case .positioning:
            if !canStart(at: flexion) { return "Straighten a little more — leave room to bend" }
            if !isLevel { return "Level your \(exercise.stableSegment) first" }
            return positionProgress > 0.05 ? "Setting your start… \(Int(ceil(3 - positionProgress * 3)))" : "Get comfortable, then hold still"
        case .holding:
            return "\(Int(ceil(holdRemaining))) more second\(Int(ceil(holdRemaining)) == 1 ? "" : "s")"
        case .matchLastBest, .reps:
            if goalReached && repStage == .out { return "Close the phone to save" }
            let toGo = repStage == .out ? currentGoal - flexion : flexion - startAngle
            if repStage == .out && phase == .matchLastBest && toGo <= 3 { return "Where you were last time" }
            return toGo > 1 ? "\(Int(toGo.rounded()))° to go" : (repStage == .out ? "That's it" : "Almost there")
        default:
            return ""
        }
    }

    // MARK: - Wiring

    private weak var hinge: HingeEngine?
    private weak var leveler: Leveler?
    private var feedback: FeedbackCoordinator?
    private var repPeak: Double = 0
    private var repCompensated = false
    private var repTooFast = false
    private var slowDownPending = false
    private var elapsed: Double = 0
    private var toastExpiry: Double = 0
    private var lastSpokenHold = 6
    private var slowDownCooldown: Double = 0
    private var driftCooldown: Double = 0
    private var tipShown = false
    var onFinished: ((SessionSummary) -> Void)?

    func attach(hinge: HingeEngine, leveler: Leveler, feedback: FeedbackCoordinator) {
        self.hinge = hinge
        self.leveler = leveler
        self.feedback = feedback
        hinge.onTick = { [weak self] dt in self?.tick(dt: dt) }
        feedback.onTickPulse = { [weak self] in self?.tickPulse += 1 }
    }

    func configure(for patient: Patient) {
        patientName = patient.firstName
        joint = patient.joint
        exercise = patient.joint == .knee ? .seatedKneeBend : .elbowBend
        lastBest = patient.bestBeforeToday
        comfortableMax = patient.comfortableMax
        target = patient.adaptiveTarget
    }

    func begin() {
        reset()
        phase = .positioning
        if let leveler, leveler.isSimulated, leveler.autoSettle, abs(leveler.simulatedTilt) < 1 {
            leveler.simulatedTilt = 12   // patient starts slightly off, then settles
        }
        feedback?.say("Choose where to start.")
    }

    /// "Start here": lock the start at the current angle immediately.
    func lockStart() {
        guard phase == .positioning, let hinge, canStart(at: hinge.flexion) else { return }
        lockStart(at: hinge.flexion)
    }

    /// Go back and pick a different starting position mid-session. Reps so far are kept.
    func changeStart() {
        guard phase.isActive, phase != .positioning else { return }
        phase = .positioning
        positionProgress = 0
        repStage = .out
        feedback?.say("Move to your new start and hold still.")
    }

    private func lockStart(at flexion: Double) {
        guard let hinge else { return }
        // Straight limb with the phone flat doubles as the zero check.
        if hinge.status == .fullyOpen && flexion < 4 { hinge.zeroCheck() }
        startAngle = hinge.flexion.rounded()
        positionProgress = 1
        beginRep()
        feedback?.success()
        // Rep 1 aims at yesterday's best when there's room for it; otherwise straight to today's target.
        phase = (reps.isEmpty && lastBest > startAngle + 10 && lastBest < target) ? .matchLastBest : .reps
        feedback?.say("Start set. Bend to \(Int(currentGoal)) degrees, then come back.")
        if !tipShown {
            tipShown = true
            show(.tip, "One rep = out and back",
                 "Bend to the amber dot, then come back to the blue dot.", "arrow.left.arrow.right", duration: 6)
        }
    }

    func reset() {
        phase = .ready
        repStage = .out
        sessionBest = 0
        reps = []
        positionProgress = 0
        holdRemaining = 5
        targetHeld = false
        toast = nil
        unlockedMilestone = nil
        summary = nil
        startAngle = 0
        tipShown = false
        beginRep()
        lastSpokenHold = 6
        feedback?.setTone(active: false, flexion: 0)
    }

    private func beginRep() {
        repStage = .out
        repPeak = 0
        repCompensated = false
        repTooFast = false
        slowDownPending = false
    }

    // MARK: - Tick

    private func tick(dt: Double) {
        elapsed += dt
        slowDownCooldown -= dt
        driftCooldown -= dt
        if toast != nil, elapsed > toastExpiry { toast = nil }
        guard let hinge, let leveler else { return }
        let flexion = hinge.flexion
        let velocity = hinge.flexionVelocity

        switch phase {
        case .ready, .complete:
            feedback?.setTone(active: false, flexion: flexion)

        case .positioning:
            leveler.settleStep(dt: dt)
            feedback?.setTone(active: false, flexion: flexion)
            // Any angle with room to bend works as a start — it just has to be steady and level.
            let still = abs(velocity) < 4 && (hinge.status != .closed || hinge.isManual)
            if still && leveler.isLevel && canStart(at: flexion) {
                positionProgress = min(1, positionProgress + dt / 3)
                if positionProgress >= 1 { lockStart(at: flexion) }
            } else {
                positionProgress = max(0, positionProgress - dt * 1.5)
            }

        case .matchLastBest, .reps:
            feedback?.setTone(active: true, flexion: flexion)
            watchQuality(flexion: flexion, velocity: velocity, leveler: leveler)
            repPeak = max(repPeak, flexion)
            switch repStage {
            case .out:
                if !goalReached { feedback?.proximity(flexion: flexion, target: currentGoal) }
                if flexion >= currentGoal - 1 {
                    // Reached the dot. Today's target gets one five-second hold.
                    if phase == .reps && !targetHeld && !compensatingNow {
                        repStage = .back
                        phase = .holding
                        holdRemaining = 5
                        lastSpokenHold = 6
                        feedback?.perfect()
                        feedback?.say("Perfect. Hold.")
                    } else {
                        turnAround()
                    }
                } else if flexion >= repTurn && velocity < -6 {
                    // Went as far as they could inside the amber zone and started back: still a rep.
                    turnAround()
                }
            case .back:
                if flexion <= repHome { completeRep() }
            }

        case .holding:
            feedback?.setTone(active: true, flexion: flexion)
            watchQuality(flexion: flexion, velocity: velocity, leveler: leveler)
            repPeak = max(repPeak, flexion)
            if flexion < target - 4 {
                phase = .reps
                feedback?.warning()
                show(.warning, "Hold slipped", "Now come back to your start.", "arrow.uturn.backward", duration: 2.5)
            } else {
                holdRemaining = max(0, holdRemaining - dt)
                let whole = Int(ceil(holdRemaining))
                if whole < lastSpokenHold && whole > 0 && whole <= 3 {
                    lastSpokenHold = whole
                    feedback?.tick(intensity: 0.9)
                }
                if holdRemaining <= 0 { completeHold() }
            }
        }
    }

    /// Reached the goal zone: chime, and tell them to come back.
    private func turnAround() {
        repStage = .back
        feedback?.success()
        if phase == .matchLastBest {
            feedback?.say("This is where you were. Now back.")
        } else {
            feedback?.say("Good. Now back.")
        }
    }

    /// Rushed or compensated movement marks the rep; warn at the turnaround, not while closing the phone.
    private func watchQuality(flexion: Double, velocity: Double, leveler: Leveler) {
        let base = startAngle
        compensatingNow = leveler.isDrifting && flexion > base + 5
        if compensatingNow {
            repCompensated = true
            if driftCooldown <= 0 {
                driftCooldown = 3
                feedback?.warning()
                show(.warning, exercise.driftCue, "This rep won't count.", "level.fill", duration: 2.5)
            }
        }
        if abs(velocity) > 110 && flexion > base + 5 && !repTooFast {
            repTooFast = true
            slowDownPending = true
        }
        if slowDownPending && velocity < -8 && flexion < 125 {
            slowDownPending = false
            if slowDownCooldown <= 0 {
                slowDownCooldown = 3
                feedback?.warning()
                feedback?.say("Slow down.")
                show(.warning, "Slow down", "Two seconds out, two seconds back. This rep won't count.", "tortoise.fill", duration: 2.8)
            }
        }
    }

    private func completeRep() {
        let rep = Rep(peak: repPeak, compensated: repCompensated, tooFast: repTooFast)
        reps.append(rep)
        let wasMatch = phase == .matchLastBest
        beginRep()
        if wasMatch { phase = .reps }
        guard !rep.compensated && !rep.tooFast else { return }
        let previous = max(sessionBest, lastBest)
        if rep.peak > sessionBest { sessionBest = rep.peak }
        if cleanReps == repGoal {
            feedback?.success()
            feedback?.say("\(repGoal). Set complete. Close the phone to save.")
            show(.success, "Set complete", "\(repGoal) of \(repGoal) reps — close the phone to save.", "checkmark.circle.fill", duration: 4)
            return
        }
        if cleanReps < repGoal { feedback?.say("\(cleanReps)") }
        if rep.peak > previous + 0.5 && toast?.kind != .milestone {
            let gain = rep.peak - lastBest
            show(.success, "New best · \(Int(rep.peak.rounded()))°",
                 gain >= Clinical.measurementNoise ? "+\(Int(gain))° — beyond measurement error" : "+\(Int(gain.rounded()))° past your last best",
                 "sparkles", duration: 2.6)
        }
    }

    private func completeHold() {
        targetHeld = true
        phase = .reps           // still coming back: the rep counts when they return to the start
        repStage = .back
        sessionBest = max(sessionBest, hinge?.flexion ?? target)
        feedback?.success()
        if let milestone = joint.milestones.first(where: { $0.degrees > lastBest && $0.degrees <= max(sessionBest, target) }) {
            unlockedMilestone = milestone
            feedback?.say("Milestone unlocked. \(milestone.title). Now back.")
            show(.milestone, "Unlocked: \(milestone.title)", "You now have the \(Int(milestone.degrees))° it takes.", milestone.symbol, duration: 5)
        } else {
            feedback?.say("Great hold. Now back.")
        }
    }

    // MARK: - Finish

    /// Close-to-save: the natural end of a session is closing the phone.
    @discardableResult
    func finish(patient: Patient?, context: ModelContext) -> SessionSummary? {
        guard phase.isActive || phase == .ready && !reps.isEmpty else { return nil }
        feedback?.setTone(active: false, flexion: 0)
        let clean = reps.filter { !$0.compensated && !$0.tooFast }
        let peak = max(sessionBest, clean.map(\.peak).max() ?? 0)
        let result = SessionSummary(start: startAngle, cleanReps: clean.count, repGoal: repGoal, peak: peak,
                                    previousBest: lastBest, reps: reps.count,
                                    targetHeld: targetHeld, target: target, milestone: unlockedMilestone)
        summary = result
        phase = .complete
        if let patient, peak > 0 {
            let peaks = clean.map(\.peak).sorted()
            let session = RehabSession(date: .now, peakFlexion: peak.rounded(),
                                       comfortableMax: peaks.isEmpty ? peak : peaks[peaks.count / 2].rounded(),
                                       extensionDeficit: max(0, (patient.extensionDeficit - 1)),
                                       reps: reps.count, compensatedReps: reps.filter(\.compensated).count,
                                       fastReps: reps.filter(\.tooFast).count, pain: 3,
                                       target: target, targetHeld: targetHeld)
            session.startFlexion = startAngle
            session.repGoal = repGoal
            session.patient = patient
            context.insert(session)
            try? context.save()
        }
        onFinished?(result)
        return result
    }

    func show(_ kind: CoachToast.Kind, _ title: String, _ detail: String?, _ symbol: String, duration: Double) {
        toast = CoachToast(kind: kind, title: title, detail: detail, symbol: symbol)
        toastExpiry = elapsed + duration
    }
}
