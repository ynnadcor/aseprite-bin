// SPDX-License-Identifier: MIT
// Live performance data for the Gauges dashboard: one read-only snapshot of the
// standard OBD values the engine computer shares, decoded to numbers. The app
// polls this repeatedly to drive the gauges. Reads only (ReadDataByIdentifier),
// the same traffic any live-data scan tool sends.
import Foundation

/// One moment of live engine data. Any field can be nil if the car didn't share
/// that value over this connection.
public struct LiveSample: Equatable, Sendable {
    public var time: Date
    public var rpm: Double?           // OBD 0C
    public var coolantC: Int?         // OBD 05
    public var intakeAirC: Int?       // OBD 0F
    public var oilC: Int?             // OBD 5C (BMW shares this one on many cars)
    public var manifoldKpa: Int?      // OBD 0B (absolute)
    public var baroKpa: Int?          // OBD 33
    public var loadPct: Double?       // OBD 04
    public var speedKph: Int?         // OBD 0D

    // BMW-specific values the video's dashboard shows (fuel rail pressure,
    // requested vs actual charge). These aren't standard OBD identifiers, so
    // they stay nil until captured and confirmed on the car. The UI shows them
    // as "needs on-car capture" rather than guessing.
    public var railFuelBar: Double?
    public var chargeRequestedPct: Double?
    public var chargeActualPct: Double?

    public init(time: Date = Date()) { self.time = time }

    /// Boost over ambient, in psi (manifold minus barometric). nil if either is missing.
    public var boostPsi: Double? {
        guard let m = manifoldKpa, let b = baroKpa else { return nil }
        return Double(m - b) * 0.1450377
    }

    /// Boost over ambient, in bar.
    public var boostBar: Double? {
        guard let m = manifoldKpa, let b = baroKpa else { return nil }
        return Double(m - b) / 100.0
    }

    public var hasAnything: Bool {
        rpm != nil || coolantC != nil || intakeAirC != nil || oilC != nil
            || manifoldKpa != nil || loadPct != nil || speedKph != nil
    }

    /// A lively made-up sample for practice mode and screenshots: a gentle pull
    /// through the rev range with boost and temperatures that move with it.
    public static func demo(at t: Double) -> LiveSample {
        var s = LiveSample(time: Date(timeIntervalSince1970: t))
        let throttle = max(0, sin(t * 0.5))                  // 0...1 surge
        s.rpm = 900 + throttle * 4800 + 40 * sin(t * 6)
        let boostBar = throttle * throttle * 0.9              // up to ~13 psi
        s.baroKpa = 100
        s.manifoldKpa = 100 + Int(boostBar * 100)
        s.loadPct = 12 + throttle * 85
        s.speedKph = Int(20 + throttle * 90)
        s.intakeAirC = 30 + Int(throttle * 18)               // heat soak under load
        s.coolantC = 92 + Int(sin(t * 0.2) * 3)
        s.oilC = 98 + Int(throttle * 20)
        s.railFuelBar = 120 + throttle * 230                 // demo only, clearly synthetic
        s.chargeRequestedPct = 20 + throttle * 75
        s.chargeActualPct = 20 + throttle * 73
        return s
    }
}

extension ReadOnlyDiagClient {
    /// Read one live snapshot. Never throws: a value the car doesn't share is
    /// left nil. A dropped connection surfaces as an all-nil sample, which the
    /// caller can treat as "lost".
    public func readLiveSample(target: UInt16 = BMWModules.engine) -> LiveSample {
        var s = LiveSample()
        func byte(_ did: UInt16) -> Int? { (try? readDID(did, target: target))?.first.map(Int.init) }
        func word(_ did: UInt16) -> Int? {
            guard let d = try? readDID(did, target: target), d.count >= 2 else { return nil }
            return Int(d[0]) << 8 | Int(d[1])
        }
        if let w = word(0xF40C) { s.rpm = Double(w) / 4 }
        if let b = byte(0xF405) { s.coolantC = b - 40 }
        if let b = byte(0xF40F) { s.intakeAirC = b - 40 }
        if let b = byte(0xF45C) { s.oilC = b - 40 }
        s.manifoldKpa = byte(0xF40B)
        s.baroKpa = byte(0xF433)
        if let b = byte(0xF404) { s.loadPct = Double(b) * 100 / 255 }
        s.speedKph = byte(0xF40D)
        return s
    }
}
