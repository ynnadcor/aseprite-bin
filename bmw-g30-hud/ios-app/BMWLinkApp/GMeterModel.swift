// SPDX-License-Identifier: MIT
// Feeds the iPhone's motion sensors into the G-meter math (BMWLinkKit's
// CarAxes / GForceTracker). Needs no car connection and no permission prompt.
import CoreMotion
import Foundation
import BMWLinkKit

@MainActor
final class GMeterModel: ObservableObject {
    @Published private(set) var tracker = GForceTracker(smoothing: 0.18, trailLength: 90)
    @Published private(set) var calibrated = false
    @Published private(set) var status = ""
    @Published private(set) var practice = false
    /// For a phone whose screen faces the windshield (or if the dot moves the wrong way).
    @Published var flipped = false

    private let motion = CMMotionManager()
    private var axes: CarAxes?
    private var lastGravity: Vector3?
    private var demoTimer: Timer?
    private var demoTime = 0.0

    var sensorsAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        if ScreenshotMode.isOn || !sensorsAvailable { practice = true }
        if practice {
            startPractice()
            return
        }
        guard !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let m, let model = self else { return }
            let gravity = Vector3(m.gravity.x, m.gravity.y, m.gravity.z)
            let user = Vector3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
            Task { @MainActor in model.apply(gravity: gravity, user: user) }
        }
        status = calibrated ? "Live" : "Put the phone in its mount, then tap Calibrate while parked."
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        demoTimer?.invalidate()
        demoTimer = nil
    }

    func setPractice(_ on: Bool) {
        stop()
        practice = on || !sensorsAvailable
        tracker.resetPeaks()
        start()
    }

    func calibrate() {
        guard let g = lastGravity, let a = CarAxes.calibrate(gravity: g) else {
            status = "Couldn't calibrate yet: hold the phone still in its mount and try again."
            return
        }
        axes = a
        calibrated = true
        tracker.resetPeaks()
        status = "Calibrated. Live."
    }

    func resetPeaks() { tracker.resetPeaks() }

    private func apply(gravity: Vector3, user: Vector3) {
        lastGravity = gravity
        if axes == nil { axes = CarAxes.calibrate(gravity: gravity) }   // until the user calibrates
        guard let axes else { return }
        let felt = axes.felt(user)
        let sign = flipped ? -1.0 : 1.0
        tracker.add(lateral: felt.lateral * sign, longitudinal: felt.longitudinal * sign)
    }

    private func startPractice() {
        status = sensorsAvailable ? "Practice data, not your car" : "No motion sensors here: practice data"
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in model.practiceTick() }
        }
    }

    private func practiceTick() {
        demoTime += 1.0 / 30
        let d = GForceTracker.demo(at: demoTime)
        tracker.add(lateral: d.lateral, longitudinal: d.longitudinal)
    }
}
