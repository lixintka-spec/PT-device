import SwiftUI
import CoreMotion
import UIKit

/// Checks that the segment that should stay still (thigh / upper arm) is level.
///
/// On iPhone Duo, Core Motion can report attitude relative to the display your UI is on:
/// set `deviceMotionBody` to a view (UIView adopts `CMBodyIdentifiable`). The Simulator has
/// no motion sensors, so Range falls back to a simulated sensor that the demo controls drive.
@MainActor
@Observable
final class Leveler {
    /// Degrees away from the required start position (0 = perfect).
    private(set) var measuredTilt: Double = 0
    private(set) var isSimulated = true
    /// Simulated tilt used when no motion hardware is available.
    var simulatedTilt: Double = 0
    /// When simulated, gently settle toward level during positioning (a patient adjusting).
    var autoSettle = true

    private let manager = CMMotionManager()
    private var running = false

    var tilt: Double { isSimulated ? simulatedTilt : measuredTilt }
    var isLevel: Bool { abs(tilt) <= 5 }
    var isDrifting: Bool { abs(tilt) > 10 }

    func start(body: UIView?) {
        guard !running else { return }
        running = true
        guard manager.isDeviceMotionAvailable else {
            isSimulated = true
            return
        }
        isSimulated = false
        if let body { manager.deviceMotionBody = body }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Flat segment: gravity should point straight through the display (z = -1).
            let g = motion.gravity
            let tiltFromFlat = acos(min(1, max(-1, -g.z))) * 180 / .pi
            let signed = g.y >= 0 ? tiltFromFlat : -tiltFromFlat
            self.measuredTilt = signed
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        running = false
    }

    /// Simulated patient settling into position.
    func settleStep(dt: Double) {
        guard isSimulated, autoSettle else { return }
        simulatedTilt += (0 - simulatedTilt) * (1 - exp(-dt * 1.1))
        if abs(simulatedTilt) < 0.05 { simulatedTilt = 0 }
    }
}

/// Hands Core Motion the UIView that hosts the session, so attitude matches that display.
struct MotionBodyAnchor: UIViewRepresentable {
    var onView: (UIView) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { onView(view) }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
