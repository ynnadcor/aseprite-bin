// SPDX-License-Identifier: MIT
// G-meter math, kept free of CoreMotion so it can be tested anywhere. The app
// feeds it CoreMotion's gravity and userAcceleration (device axes, in g).
import Foundation

public struct Vector3: Equatable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }

    public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vector3, k: Double) -> Vector3 { Vector3(a.x * k, a.y * k, a.z * k) }
    public func dot(_ b: Vector3) -> Double { x * b.x + y * b.y + z * b.z }
    public func cross(_ b: Vector3) -> Vector3 {
        Vector3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }
    public var length: Double { dot(self).squareRoot() }
    public var normalized: Vector3 { length > 0 ? self * (1 / length) : self }
}

/// The car's axes in the phone's coordinates, found from gravity while parked.
/// Assumes the phone faces the driver (screen toward the cabin), so the car's
/// forward direction points out of the phone's back; if the phone lies flat,
/// its top edge is taken as forward.
public struct CarAxes: Equatable, Sendable {
    public let forward: Vector3
    public let right: Vector3
    public let down: Vector3

    public static func calibrate(gravity: Vector3) -> CarAxes? {
        guard gravity.length > 0.5 else { return nil }
        let down = gravity.normalized
        let back = Vector3(0, 0, -1)
        var forward = back - down * back.dot(down)
        if forward.length < 0.35 {
            let top = Vector3(0, 1, 0)
            forward = top - down * top.dot(down)
        }
        guard forward.length > 0.1 else { return nil }
        let f = forward.normalized
        return CarAxes(forward: f, right: down.cross(f).normalized, down: down)
    }

    /// The force the driver feels, in g: `lateral` > 0 pushes to the right
    /// (turning left), `longitudinal` > 0 pushes forward (braking).
    /// CoreMotion's userAcceleration already points the way the body is pushed.
    public func felt(_ userAcceleration: Vector3) -> (lateral: Double, longitudinal: Double) {
        (userAcceleration.dot(right), userAcceleration.dot(forward))
    }
}

/// Smoothing, peaks and a short trail for the G-meter display.
public struct GForceTracker: Sendable {
    public struct Sample: Equatable, Sendable {
        public var lateral: Double
        public var longitudinal: Double
        public var total: Double { (lateral * lateral + longitudinal * longitudinal).squareRoot() }
    }

    public private(set) var current = Sample(lateral: 0, longitudinal: 0)
    public private(set) var trail: [Sample] = []
    public private(set) var peakBraking = 0.0
    public private(set) var peakAccelerating = 0.0
    public private(set) var peakLeftTurn = 0.0
    public private(set) var peakRightTurn = 0.0
    public private(set) var peakTotal = 0.0

    /// 0...1: how much of each new sample is taken (lower = smoother).
    public var smoothing: Double
    public var trailLength: Int

    public init(smoothing: Double = 0.2, trailLength: Int = 60) {
        self.smoothing = smoothing
        self.trailLength = trailLength
    }

    public mutating func add(lateral: Double, longitudinal: Double) {
        let k = min(1, max(0.01, smoothing))
        current = Sample(lateral: current.lateral + (lateral - current.lateral) * k,
                         longitudinal: current.longitudinal + (longitudinal - current.longitudinal) * k)
        trail.append(current)
        if trail.count > trailLength { trail.removeFirst(trail.count - trailLength) }
        peakBraking = max(peakBraking, current.longitudinal)
        peakAccelerating = max(peakAccelerating, -current.longitudinal)
        peakLeftTurn = max(peakLeftTurn, current.lateral)
        peakRightTurn = max(peakRightTurn, -current.lateral)
        peakTotal = max(peakTotal, current.total)
    }

    public mutating func resetPeaks() {
        peakBraking = 0; peakAccelerating = 0; peakLeftTurn = 0; peakRightTurn = 0; peakTotal = 0
        trail.removeAll()
    }

    /// A smooth made-up drive for practice mode and screenshots.
    public static func demo(at t: Double) -> (lateral: Double, longitudinal: Double) {
        (0.65 * sin(t * 0.9) + 0.1 * sin(t * 3.1), 0.45 * sin(t * 0.55 + 1.2))
    }
}
