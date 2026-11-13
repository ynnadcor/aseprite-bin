// SPDX-License-Identifier: MIT
// The live G-meter's data source: the phone's own motion sensors (CoreMotion),
// fed into BMWLinkKit's GForceTracker. This needs no car at all - it's the
// phone measuring the forces you feel. In the Simulator (no sensors) it falls
// back to a simulated drive so the gauge still moves.
import Foundation
import Combine
import CoreMotion
import BMWLinkKit

final class MotionGauge: ObservableObject {
    @Published private(set) var tracker = GForceTracker(smoothing: 0.25, trailLength: 50)
    @Published private(set) var running = false
    /// true while using the phone's real sensors; false when simulating.
    @Published private(set) var usingSensors = false

    private let manager = CMMotionManager()
    private var axes: CarAxes?
    private var demoTimer: Timer?
    private var demoT = 0.0

    /// Start the G-meter. `simulate` forces the demo drive (used for screenshots).
    func start(simulate: Bool = false) {
        stop()
        running = true
        if simulate || !manager.isDeviceMotionAvailable {
            usingSensors = false
            startDemo()
            return
        }
        usingSensors = true
        axes = nil   // re-find the car's orientation from gravity on the next sample
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let gravity = Vector3(m.gravity.x, m.gravity.y, m.gravity.z)
            let user = Vector3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
            if self.axes == nil { self.axes = CarAxes.calibrate(gravity: gravity) }
            guard let axes = self.axes else { return }
            let felt = axes.felt(user)
            self.tracker.add(lateral: felt.lateral, longitudinal: felt.longitudinal)
        }
    }

    /// Re-learn which way the phone is facing (use after mounting it).
    func recenter() { axes = nil }

    func resetPeaks() { tracker.resetPeaks() }

    func stop() {
        manager.stopDeviceMotionUpdates()
        demoTimer?.invalidate()
        demoTimer = nil
        running = false
    }

    private func startDemo() {
        demoT = 0
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.demoT += 1.0 / 20.0
            let d = GForceTracker.demo(at: self.demoT)
            self.tracker.add(lateral: d.lateral, longitudinal: d.longitudinal)
        }
    }
}
