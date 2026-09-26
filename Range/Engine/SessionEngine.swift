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
    /// Held at the top for the full hold. Only held, controlled, level reps count.
    let held: Bool
    var counts: Bool { held && !compensated && !tooFast }
}

struct CoachToast: Identifiable, Equatable {
    enum Kind { case info, success, warning, milestone }
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
    var isNewBest: Bool { gain >= 1 }
}

@MainActor
@Observable
final class SessionEngine {
    enum Phase: Equatable {
        /// `.matchLastBest` is simply rep 1, aimed at yesterday's best instead of today's target.
        case ready, positioning, matchLastBest, reps, complete
        var isActive: Bool { self != .ready && self != .complete }
        var isExercising: Bool { self == .matchLastBest || self == .reps }
    }

    /// Every rep is the same three moves: bend out to the goal, hold it, come back to your start.
    enum RepStage: Int, Comparable {
        case out, hold, back
        static func < (a: RepStage, b: RepStage) -> Bool { a.rawValue < b.rawValue }
    }

    /// How long to hold at the top of every rep.
    static let holdSeconds: Double = 3
    /// Stopping this still (°/s) inside the goal zone for `settleSeconds` starts the hold.
    private static let stillVelocity: Double = 6
    private static let settleSeconds: Double = 0.4
    /// Sweeping through faster than this (°/s) — e.g. closing the phone — never starts a hold.
    private static let maxHoldStartVelocity: Double = 60
    /// How far below the goal zone the knee can sag before the hold pauses.
    private static let holdSlack: Double = 3

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
    private(set) var holdRemaining: Double = SessionEngine.holdSeconds
    /// The knee sagged out of the goal zone mid-hold; the countdown waits for it.
    private(set) var holdPaused = false
    /// Came back without finishing the hold: this rep won't count.
    private(set) var holdMissed = false
    private(set) var targetHeld = false
    private(set) var toast: CoachToast?
    private(set) var unlockedMilestone: Milestone?
    private(set) var summary: SessionSummary?
    private(set) var tickPulse = 0
    private(set) var compensatingNow = false
    /// Where the patient chose to start stretching (flexion°). Reps are measured from here.
    private(set) var startAngle: Double = 0

    var hasStart: Bool { phase != .ready && phase != .positioning }
    /// Reps that count: held, controlled and with the thigh level.
    var cleanReps: Int { reps.filter(\.counts).count }
    var holdProgress: Double { 1 - holdRemaining / Self.holdSeconds }
    var goalReached: Bool { cleanReps >= repGoal }

    /// Where this rep is aiming: yesterday's best on the first rep, today's target after that.
    var currentGoal: Double { phase == .matchLastBest ? lastBest : target }
    /// Stop anywhere from here to the goal and the hold starts.
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
        case .complete: "Saved"
        case .matchLastBest, .reps:
            switch repStage {
            case .out: goalReached ? "Set complete" : "Bend to \(Int(currentGoal))°"
            case .hold: holdPaused ? "Bend a little more" : "Hold"
            case .back: "Now back to \(Int(startAngle))°"
            }
        }
    }

    /// One supporting line, derived from the live angle.
    func detail(flexion: Double, isLevel: Bool) -> String {
        switch phase {
        case .positioning:
            if !canStart(at: flexion) { return "Straighten a little more — leave room to bend" }
            if !isLevel { return "Level your \(exercise.stableSegment) first" }
            return positionProgress > 0.05 ? "Setting your start… \(Int(ceil(3 - positionProgress * 3)))" : "Get comfortable, then hold still"
        case .matchLastBest, .reps:
            switch repStage {
            case .out:
                if goalReached { return "Close the phone to save" }
                if flexion >= repTurn { return repTooFast ? "Too fast — this one won't count" : "Stop and hold it here" }
                return "\(Int((currentGoal - flexion).rounded()))° to go, then hold"
            case .hold:
                return holdPaused ? "Hold paused — bend back into the amber" : "Keep it still"
            case .back:
                let toGo = flexion - startAngle
                return toGo > 1 ? "\(Int(toGo.rounded()))° to go" : "Almost there"
            }
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
    private var lastSpokenHold = Int(SessionEngine.holdSeconds)
    private var settle: Double = 0
    private var slowDownCooldown: Double = 0
    private var driftCooldown: Double = 0
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
        beginRep()
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
        feedback?.say("Start set. Bend to \(Int(currentGoal)) degrees and hold.")
    }

    func reset() {
        phase = .ready
        repStage = .out
        sessionBest = 0
        reps = []
        positionProgress = 0
        targetHeld = false
        toast = nil
        unlockedMilestone = nil
        summary = nil
        startAngle = 0
        beginRep()
        feedback?.setTone(active: false, flexion: 0)
    }

    private func beginRep() {
        repStage = .out
        holdRemaining = Self.holdSeconds
        holdPaused = false
        holdMissed = false
        lastSpokenHold = Int(Self.holdSeconds)
        settle = 0
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
                // Set done: extra movement (like closing the phone) isn't a rep.
                guard !goalReached else { break }
                feedback?.proximity(flexion: flexion, target: currentGoal)
                settle = flexion >= repTurn && abs(velocity) < Self.stillVelocity ? settle + dt : 0
                let atDot = flexion >= currentGoal - 1 && abs(velocity) < Self.maxHoldStartVelocity
                // A rushed rep already can't count, so it doesn't get a hold.
                if !repTooFast && (atDot || settle >= Self.settleSeconds) {
                    startHold()
                } else if repPeak >= repTurn && flexion <= repHome {
                    completeRep(held: false)   // out and straight back, no hold
                }
            case .hold:
                if flexion >= repTurn - Self.holdSlack {
                    holdPaused = false
                    holdRemaining = max(0, holdRemaining - dt)
                    let whole = Int(ceil(holdRemaining))
                    if whole < lastSpokenHold && whole > 0 {
                        lastSpokenHold = whole
                        feedback?.tick(intensity: 0.9)
                        feedback?.say("\(whole)")
                    }
                    if holdRemaining <= 0 { completeHold() }
                } else if flexion < (startAngle + repTurn) / 2 {
                    // Heading home: the hold is missed, and the screen says so.
                    holdMissed = true
                    holdPaused = false
                    repStage = .back
                } else if !holdPaused {
                    holdPaused = true
                    feedback?.warning()
                }
            case .back:
                if flexion <= repHome { completeRep(held: !holdMissed) }
            }
        }
    }

    /// Stopped in the goal zone (or reached the dot): the countdown starts.
    private func startHold() {
        repStage = .hold
        holdRemaining = Self.holdSeconds
        holdPaused = false
        lastSpokenHold = Int(Self.holdSeconds)
        settle = 0
        feedback?.perfect()
        feedback?.say("Hold")
    }

    /// Held long enough: chime, maybe a milestone, and tell them to come back.
    private func completeHold() {
        repStage = .back
        holdPaused = false
        if repPeak >= target - 1 { targetHeld = true }
        feedback?.success()
        let alreadyHave = max(lastBest, unlockedMilestone?.degrees ?? 0)
        if !repCompensated && !repTooFast,
           let milestone = joint.milestones.first(where: { $0.degrees > alreadyHave && $0.degrees <= repPeak }) {
            unlockedMilestone = milestone
            feedback?.say("Milestone unlocked. \(milestone.title). Now back.")
            show(.milestone, "Unlocked: \(milestone.title)", "You now have the \(Int(milestone.degrees))° it takes.", milestone.symbol, duration: 5)
        } else if phase == .matchLastBest {
            feedback?.say("That's where you were last time. Now back.")
        } else {
            feedback?.say("Now back.")
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

    private func completeRep(held: Bool) {
        let rep = Rep(peak: repPeak, compensated: repCompensated, tooFast: repTooFast, held: held)
        reps.append(rep)
        beginRep()
        guard rep.counts else {
            // Rushing and a lifting thigh already said why; a skipped hold says it here.
            if !rep.tooFast && !rep.compensated {
                feedback?.warning()
                feedback?.say("Hold at the top for it to count.")
                show(.warning, "Hold for \(Int(Self.holdSeconds)) seconds", "Stop at the amber dot and hold still — then it counts.",
                     "timer", duration: 3)
            }
            return
        }
        if phase == .matchLastBest { phase = .reps }
        let previous = max(sessionBest, lastBest)
        sessionBest = max(sessionBest, rep.peak)
        if cleanReps == repGoal {
            feedback?.success()
            feedback?.say("\(repGoal). Set complete. Close the phone to save.")
            show(.success, "Set complete", "\(repGoal) of \(repGoal) reps — close the phone to save.", "checkmark.circle.fill", duration: 4)
            return
        }
        if cleanReps < repGoal { feedback?.say("\(cleanReps)") }
        if rep.peak > previous + 0.5 && toast?.kind != .milestone {
            show(.success, "New best · \(Int(rep.peak.rounded()))°",
                 "+\(Int((rep.peak - lastBest).rounded()))° past your last best", "sparkles", duration: 2.6)
        }
    }

    // MARK: - Finish

    /// Close-to-save: the natural end of a session is closing the phone.
    @discardableResult
    func finish(patient: Patient?, context: ModelContext) -> SessionSummary? {
        guard phase.isActive || phase == .ready && !reps.isEmpty else { return nil }
        feedback?.setTone(active: false, flexion: 0)
        let clean = reps.filter(\.counts)
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
                                       extensionDeficit: max(0, (patient.sortedSessions.last?.extensionDeficit ?? 1) - 1),
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
