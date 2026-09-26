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
    enum Kind { case info, success, warning, milestone }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String?
    let symbol: String
}

struct SessionSummary: Equatable {
    let start: Double
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
        case ready, positioning, matchLastBest, reps, holding, complete
        var isActive: Bool { self != .ready && self != .complete }
    }

    // Configuration
    var exercise: Exercise = .seatedKneeBend
    private(set) var patientName = "Maria"
    private(set) var lastBest: Double = 92
    private(set) var comfortableMax: Double = 92
    private(set) var target: Double = 97
    private(set) var joint: Joint = .knee

    // Live state
    private(set) var phase: Phase = .ready
    private(set) var sessionBest: Double = 0
    private(set) var reps: [Rep] = []
    private(set) var positionProgress: Double = 0   // 0...1 over 3 s
    private(set) var matchProgress: Double = 0      // 0...1 over 1 s
    private(set) var holdRemaining: Double = 5
    private(set) var targetHeld = false
    private(set) var toast: CoachToast?
    private(set) var unlockedMilestone: Milestone?
    private(set) var summary: SessionSummary?
    private(set) var tickPulse = 0
    private(set) var compensatingNow = false
    private(set) var tooFastNow = false
    /// Where the patient chose to start stretching (flexion°). Reps are measured from here.
    private(set) var startAngle: Double = 0
    var hasStart: Bool { phase != .ready && phase != .positioning }

    /// One short instruction — what to do right now.
    var headline: String {
        switch phase {
        case .ready: "Ready when you are"
        case .positioning: "Choose your start"
        case .matchLastBest: "Bend to \(Int(lastBest))°"
        case .reps: targetHeld ? "Nice work" : "Bend to \(Int(target))°"
        case .holding: "Hold"
        case .complete: "Saved"
        }
    }

    /// One supporting line, derived from the live angle.
    func detail(flexion: Double, isLevel: Bool) -> String {
        switch phase {
        case .positioning:
            if !isLevel { return "Level your \(exercise.stableSegment) first" }
            return positionProgress > 0.05 ? "Setting your start… \(Int(ceil(3 - positionProgress * 3)))" : "Get comfortable, then hold still"
        case .matchLastBest: return "Where you were last time"
        case .reps:
            if targetHeld { return "Close the phone to save" }
            let toGo = Int((target - flexion).rounded())
            return toGo > 0 ? "\(toGo)° to go" : "Hold it there"
        case .holding: return "\(Int(ceil(holdRemaining))) more second\(Int(ceil(holdRemaining)) == 1 ? "" : "s")"
        default: return ""
        }
    }

    var instruction: String {
        switch phase {
        case .ready: "Your comfortable max is \(Int(comfortableMax))°. Let's aim for \(Int(target))° today."
        case .positioning: "Straight or bent — start wherever feels right. Hold still, or tap Start here."
        case .matchLastBest: "This is where you were last time: \(Int(lastBest))°."
        case .reps: targetHeld ? "Close the phone to save." : "Slow, controlled bends. Push past your ghost."
        case .holding: "Hold for \(Int(ceil(holdRemaining))) more second\(Int(ceil(holdRemaining)) == 1 ? "" : "s")."
        case .complete: "Close the phone to see how far you've come."
        }
    }

    private weak var hinge: HingeEngine?
    private weak var leveler: Leveler?
    private var feedback: FeedbackCoordinator?
    private var repInProgress = false
    private var repPeak: Double = 0
    private var repCompensated = false
    private var repTooFast = false
    private var matchedAnnounced = false
    private var matchedAt: Double?
    private var elapsed: Double = 0
    private var toastExpiry: Double = 0
    private var lastSpokenHold = 6
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
        feedback?.say("Get into position.")
    }

    /// "Start here": lock the start at the current angle immediately.
    func lockStart() {
        guard phase == .positioning, let hinge else { return }
        lockStart(at: hinge.flexion)
    }

    /// Go back and pick a different starting position mid-session. Reps so far are kept.
    func changeStart() {
        guard phase.isActive, phase != .positioning else { return }
        phase = .positioning
        positionProgress = 0
        matchedAnnounced = false
        matchedAt = nil
        matchProgress = 0
        repInProgress = false
        feedback?.say("Move to your new start and hold still.")
        show(.info, "Choose a new start", "Move to where you want to begin, then hold still.", "arrow.left.and.right", duration: 3)
    }

    private func lockStart(at flexion: Double) {
        guard let hinge else { return }
        // Straight limb with the phone flat doubles as the zero check.
        if hinge.status == .fullyOpen && flexion < 4 { hinge.zeroCheck() }
        startAngle = hinge.flexion.rounded()
        positionProgress = 1
        repInProgress = false
        feedback?.success()
        if startAngle >= lastBest - 3 || matchedAnnounced {
            phase = .reps
            feedback?.say("Start set at \(Int(startAngle)) degrees. Push toward \(Int(target)).")
            show(.info, "Start set at \(Int(startAngle))°", nil, "flag.fill", duration: 2)
        } else {
            phase = .matchLastBest
            feedback?.say("Start set at \(Int(startAngle)) degrees. Now fold to your last best, \(Int(lastBest)).")
            show(.info, "Start set at \(Int(startAngle))°", nil, "flag.fill", duration: 2)
        }
    }

    func reset() {
        phase = .ready
        sessionBest = 0
        reps = []
        positionProgress = 0
        matchProgress = 0
        holdRemaining = 5
        targetHeld = false
        toast = nil
        unlockedMilestone = nil
        summary = nil
        startAngle = 0
        repInProgress = false
        matchedAnnounced = false
        matchedAt = nil
        lastSpokenHold = 6
        feedback?.setTone(active: false, flexion: 0)
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
            // Any angle works as a start — it just has to be steady and level.
            let still = abs(velocity) < 4 && hinge.status != .closed
            if still && leveler.isLevel {
                positionProgress = min(1, positionProgress + dt / 3)
                if positionProgress >= 1 { lockStart(at: flexion) }
            } else {
                positionProgress = max(0, positionProgress - dt * 1.5)
            }

        case .matchLastBest:
            feedback?.setTone(active: true, flexion: flexion)
            feedback?.proximity(flexion: flexion, target: lastBest)
            if abs(flexion - lastBest) <= 2.5 {
                matchProgress = min(1, matchProgress + dt / 1.0)
                if matchProgress >= 1 && !matchedAnnounced {
                    matchedAnnounced = true
                    matchedAt = elapsed
                    feedback?.success()
                    feedback?.say("This is where you were. Now go \(Int(target - lastBest)) degrees further.")
                    show(.info, "This is where you were", "Now go \(Int(target - lastBest))° further.", "flag.checkered", duration: 3.5)
                }
            } else if !matchedAnnounced {
                matchProgress = max(0, matchProgress - dt * 2)
            }
            if let at = matchedAt, elapsed - at > 1.2 {
                phase = .reps
            }
            trackReps(flexion: flexion, velocity: velocity, leveler: leveler)

        case .reps:
            feedback?.setTone(active: true, flexion: flexion)
            if !targetHeld { feedback?.proximity(flexion: flexion, target: target) }
            trackReps(flexion: flexion, velocity: velocity, leveler: leveler)
            if !targetHeld && flexion >= target - 1 && !compensatingNow {
                phase = .holding
                holdRemaining = 5
                lastSpokenHold = 6
                feedback?.perfect()
                feedback?.say("Perfect. Hold.")
            }

        case .holding:
            feedback?.setTone(active: true, flexion: flexion)
            trackReps(flexion: flexion, velocity: velocity, leveler: leveler)
            if flexion < target - 4 {
                phase = .reps
                feedback?.warning()
                show(.warning, "Hold slipped", "Ease back to \(Int(target))° and hold.", "arrow.uturn.backward", duration: 2.5)
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

    /// How far past the start a movement must go to count as a rep.
    private var repRise: Double { max(6, min(15, (target - startAngle) * 0.45)) }

    private func trackReps(flexion: Double, velocity: Double, leveler: Leveler) {
        let base = startAngle
        compensatingNow = leveler.isDrifting && flexion > base + 8
        if compensatingNow && driftCooldown <= 0 {
            driftCooldown = 3
            feedback?.warning()
            show(.warning, exercise.driftCue, "This rep won't count toward your best.", "level.fill", duration: 2.5)
        }

        let tooFast = abs(velocity) > 110 && flexion > base + 5
        tooFastNow = tooFast
        if !repInProgress {
            if flexion > base + repRise * 0.6 {
                repInProgress = true
                repPeak = flexion
                repCompensated = compensatingNow
                repTooFast = tooFast
            }
        } else {
            repPeak = max(repPeak, flexion)
            repCompensated = repCompensated || compensatingNow
            if tooFast && !repTooFast {
                repTooFast = true
                slowDownPending = true
            }
            // Warn at the peak of a rushed rep (when it turns around). Closing the phone
            // never turns around, so a fast close never triggers this.
            if slowDownPending && velocity < -8 && flexion < 125 {
                slowDownPending = false
                if slowDownCooldown <= 0 {
                    slowDownCooldown = 3
                    feedback?.warning()
                    feedback?.say("Slow down.")
                    show(.warning, "Slow down", "Controlled movement — two seconds up, two down.", "tortoise.fill", duration: 2.8)
                }
            }
            if flexion < base + repRise * 0.35 {
                slowDownPending = false
                finishRep()
            }
        }
    }

    private var slowDownPending = false

    private func finishRep() {
        repInProgress = false
        guard repPeak >= startAngle + repRise else { return }
        let rep = Rep(peak: repPeak, compensated: repCompensated, tooFast: repTooFast)
        reps.append(rep)
        guard !rep.compensated && !rep.tooFast else { return }
        let previous = max(sessionBest, lastBest)
        if rep.peak > sessionBest { sessionBest = rep.peak }
        if rep.peak > previous + 0.5 && phase != .holding && toast?.kind != .milestone {
            let gain = rep.peak - lastBest
            feedback?.success()
            show(.success, "New best · \(Int(rep.peak.rounded()))°",
                 gain >= Clinical.measurementNoise ? "+\(Int(gain))° — beyond measurement error" : "+\(Int(gain.rounded()))° past your last best",
                 "sparkles", duration: 2.6)
        }
    }

    private func completeHold() {
        targetHeld = true
        phase = .reps
        sessionBest = max(sessionBest, hinge?.flexion ?? target)
        feedback?.success()
        if let milestone = joint.milestones.first(where: { $0.degrees > lastBest && $0.degrees <= max(sessionBest, target) }) {
            unlockedMilestone = milestone
            feedback?.say("Milestone unlocked. \(milestone.title).")
            show(.milestone, "Unlocked: \(milestone.title)", "You now have the \(Int(milestone.degrees))° it takes.", milestone.symbol, duration: 5)
        } else {
            feedback?.say("Target held. Great work.")
            show(.success, "Target held", "\(Int(target))° for five seconds.", "checkmark.circle.fill", duration: 3)
        }
    }

    // MARK: - Finish

    /// Close-to-save: the natural end of a session is closing the phone.
    @discardableResult
    func finish(patient: Patient?, context: ModelContext) -> SessionSummary? {
        guard phase.isActive || phase == .ready && !reps.isEmpty else { return nil }
        if repInProgress { repInProgress = false }  // discard the half-rep caused by closing
        feedback?.setTone(active: false, flexion: 0)
        let peak = max(sessionBest, reps.filter { !$0.compensated && !$0.tooFast }.map(\.peak).max() ?? 0)
        let result = SessionSummary(start: startAngle, peak: peak, previousBest: lastBest, reps: reps.count,
                                    targetHeld: targetHeld, target: target, milestone: unlockedMilestone)
        summary = result
        phase = .complete
        if let patient, peak > 0 {
            let clean = reps.filter { !$0.compensated && !$0.tooFast }.map(\.peak).sorted()
            let session = RehabSession(date: .now, peakFlexion: peak.rounded(),
                                       comfortableMax: clean.isEmpty ? peak : clean[clean.count / 2].rounded(),
                                       extensionDeficit: max(0, (patient.extensionDeficit - 1)),
                                       reps: reps.count, compensatedReps: reps.filter(\.compensated).count,
                                       fastReps: reps.filter(\.tooFast).count, pain: 3,
                                       target: target, targetHeld: targetHeld)
            session.startFlexion = startAngle
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
