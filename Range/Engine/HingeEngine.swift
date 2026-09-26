import SwiftUI
import QuartzCore

/// Turns iPhone Duo hinge updates into a smooth, clinically usable joint angle.
///
/// Apple notes the hinge update rate is system policy, so we never trust a single sample:
/// raw updates set a target, and a 60 Hz tick eases toward it and derives angular velocity.
@MainActor
@Observable
final class HingeEngine {
    enum Status: String {
        case closed, partiallyOpen, fullyOpen, unavailable
        var title: String {
            switch self {
            case .closed: "Closed"
            case .partiallyOpen: "Partially open"
            case .fullyOpen: "Fully open"
            case .unavailable: "No hinge"
            }
        }
    }

    /// Smoothed hinge angle in degrees: 0 = closed, 180 = flat.
    private(set) var angle: Double = 180
    private(set) var rawAngle: Double = 180
    /// Degrees per second of the hinge (positive = opening).
    private(set) var velocity: Double = 0
    private(set) var status: Status = .unavailable
    private(set) var hasHardwareHinge = false
    /// Actually folded shut. The system may report `.closed` early while folding fast
    /// (it anticipates closing to switch displays), so session logic keys off the angle.
    private(set) var isPhysicallyClosed = false
    /// Zero-check offset captured when the phone lies flat on a straight limb.
    var calibrationOffset: Double = 0

    /// When true, the in-app autopilot drives the hinge (e.g. in Bitrig, where the CLI can't reach).
    var isAutopilot = false

    /// Called every tick with dt, after smoothing.
    var onTick: ((Double) -> Void)?
    var onStatusChange: ((Status, Status) -> Void)?

    private var targetAngle: Double = 180
    private var lastTick: CFTimeInterval = 0
    private var timer: Timer?

    /// Joint flexion: a straight limb holds the phone flat (180°); bending closes it.
    var flexion: Double { min(170, max(0, 180 - angle - calibrationOffset)) }
    /// Flexion velocity in degrees per second (positive = bending further).
    var flexionVelocity: Double { -velocity }

    static let logHinge = ProcessInfo.processInfo.arguments.contains("-logHinge")

    init() { start() }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Feed from SwiftUI's `onHingeChange`.
    func ingest(_ context: DeviceHingeContext) {
        guard let hinge = context.hinge else {
            hasHardwareHinge = false
            if !isAutopilot { setStatus(.unavailable) }
            return
        }
        hasHardwareHinge = true
        if Self.logHinge { print("HINGE angle=\(hinge.angle.degrees) status=\(hinge.status)") }
        guard !isAutopilot else { return }
        let newStatus: Status = if hinge.status == .closed { .closed }
            else if hinge.status == .partiallyOpen { .partiallyOpen }
            else { .fullyOpen }
        ingest(degrees: hinge.angle.degrees, status: newStatus)
    }

    /// Feed from the autopilot or the on-screen fallback slider.
    func ingest(degrees: Double, status newStatus: Status? = nil) {
        rawAngle = min(180, max(0, degrees))
        targetAngle = rawAngle
        let derived: Status = rawAngle < 3 ? .closed : (rawAngle > 177 ? .fullyOpen : .partiallyOpen)
        setStatus(newStatus ?? derived)
    }

    private func setStatus(_ new: Status) {
        guard new != status else { return }
        let old = status
        status = new
        onStatusChange?(old, new)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTick == 0 ? 1.0 / 60.0 : min(0.1, max(1.0 / 240.0, now - lastTick))
        lastTick = now
        let previous = angle
        // Critically-damped-ish easing: fast enough to feel live, smooth enough to read.
        let k = 1 - exp(-dt * 18)
        angle += (targetAngle - angle) * k
        if abs(targetAngle - angle) < 0.01 { angle = targetAngle }
        let instant = (angle - previous) / dt
        velocity += (instant - velocity) * (1 - exp(-dt * 12))
        let closedNow = isPhysicallyClosed ? angle < 40 : ((status == .closed || targetAngle < 3) && angle < 25)
        if closedNow != isPhysicallyClosed { isPhysicallyClosed = closedNow }
        onTick?(dt)
    }

    /// Zero check: the limb is straight, so whatever the hinge reads now is "0° flexion".
    func zeroCheck() {
        calibrationOffset = 180 - angle
    }
}
