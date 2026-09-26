import SwiftUI

@MainActor
@Observable
final class AppState {
    enum Tab: Hashable { case home, exercise, progress }

    var tab: Tab = .home
    var showPlacementGuide = false
    var showDemoControls = false
    var showOuterSummary = false
    var lastSummary: SessionSummary?
    var isMuted = false { didSet { feedback?.isMuted = isMuted } }

    var primaryPatient: Patient?
    private weak var hinge: HingeEngine?
    private weak var leveler: Leveler?
    private weak var session: SessionEngine?
    private var feedback: FeedbackCoordinator?
    private var autopilot: Task<Void, Never>?

    func attach(hinge: HingeEngine, leveler: Leveler, session: SessionEngine, feedback: FeedbackCoordinator) {
        self.hinge = hinge
        self.leveler = leveler
        self.session = session
        self.feedback = feedback
    }

    // MARK: - Autopilot

    /// Plays the whole patient story by driving the hinge in-app. Mirrors scripts/demo.sh.
    func runAutopilot() {
        autopilot?.cancel()
        guard let hinge, let session, let leveler else { return }
        autopilot = Task { @MainActor in
            hinge.isAutopilot = true
            @MainActor func sweep(_ from: Double, _ to: Double, _ seconds: Double) async {
                let steps = max(1, Int(seconds * 60))
                for i in 0...steps {
                    if Task.isCancelled || !hinge.isAutopilot { return }
                    hinge.ingest(degrees: from + (to - from) * Double(i) / Double(steps))
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            @MainActor func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

            // 1. Closed: the Today card on the outer display.
            session.reset()
            showOuterSummary = false
            tab = .home
            await sweep(0, 0, 0.1)
            await wait(3)
            // 2. Open flat.
            await sweep(0, 180, 1.2)
            await wait(2.5)
            // 3. Start: she chooses to begin with the knee bent at 40°, holds still — start locks.
            if let p = primaryPatient { session.configure(for: p) }
            tab = .exercise
            leveler.autoSettle = true
            session.repGoal = 4
            session.begin()
            leveler.simulatedTilt = 12
            await wait(1.2)
            let start = 180.0 - 40
            await sweep(180, start, 1.6)
            for _ in 0..<80 where session.phase == .positioning { await wait(0.1) }
            await wait(1)
            // Every rep: bend to the dot, hold while the ring fills, come back.
            let hold = SessionEngine.holdSeconds + 0.8
            @MainActor func rep(to flexion: Double, bend: Double = 2.0) async {
                await sweep(start, 180 - flexion, bend)
                await wait(hold)
                await sweep(180 - flexion, start, 1.6)
                await wait(0.8)
            }
            // 4. Rep 1: match last best.
            await rep(to: session.lastBest)
            // 5. Rep 2: past the ghost — new best, and a milestone.
            await rep(to: session.lastBest + 3)
            // 6. A rushed rep: "Slow down" — it doesn't count.
            await sweep(start, 95, 0.2)
            await wait(0.3)
            await sweep(95, start, 1.2)
            await wait(1.8)
            // 7. Rep 3: today's target.
            await rep(to: session.target + 0.5, bend: 2.4)
            // 8. Rep 4 of 4: "Set complete."
            await rep(to: session.target - 1, bend: 1.8)
            await wait(1.5)
            // 9. Close the phone to save → recovery replay on the outer display.
            await sweep(start, 0, 0.35)
            await wait(9)
        }
    }

    func stopAutopilot() {
        autopilot?.cancel()
        hinge?.isAutopilot = false
    }
}
