// SPDX-License-Identifier: MIT
// Small spherical-geometry helpers for route polylines (WGS-84 degrees).
import Foundation

public struct Coordinate: Equatable, Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum GeoMath {
    /// Mean Earth radius (IUGG), meters.
    public static let earthRadiusM = 6_371_008.8

    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Great-circle distance in meters (haversine).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let p1 = rad(a.latitude), p2 = rad(b.latitude)
        let dp = p2 - p1
        let dl = rad(b.longitude - a.longitude)
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadiusM * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`, degrees clockwise from north, [0, 360).
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let p1 = rad(a.latitude), p2 = rad(b.latitude)
        let dl = rad(b.longitude - a.longitude)
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let d = deg(atan2(y, x))
        let r = (d + 360).truncatingRemainder(dividingBy: 360)
        return r == 360 ? 0 : r
    }

    /// Wrap an angle to (-180, 180].
    public static func normalize180(_ d: Double) -> Double {
        var x = d.truncatingRemainder(dividingBy: 360)
        if x <= -180 { x += 360 } else if x > 180 { x -= 360 }
        return x
    }

    public static func pathLength(_ pts: [Coordinate]) -> Double {
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count { total += distance(pts[i - 1], pts[i]) }
        return total
    }

    /// Signed turn angle (degrees) where `incoming` ends and `outgoing` begins:
    /// positive = right turn, negative = left, ~0 = straight, ~±180 = U-turn.
    ///
    /// Bearings are measured over about `lookMeters` on each side of the
    /// junction rather than over the first/last polyline segment, because real
    /// route polylines often have tiny, noisy segments right at an intersection.
    /// Returns nil when either side has less than a meter of usable geometry.
    public static func turnAngle(incoming: [Coordinate], outgoing: [Coordinate],
                                 lookMeters: Double = 25) -> Double? {
        guard let junctionIn = incoming.last, let junctionOut = outgoing.first else { return nil }

        var before: Coordinate?
        var acc = 0.0
        var i = incoming.count - 1
        while i > 0 {
            acc += distance(incoming[i - 1], incoming[i])
            before = incoming[i - 1]
            if acc >= lookMeters { break }
            i -= 1
        }

        var after: Coordinate?
        acc = 0.0
        var j = 0
        while j + 1 < outgoing.count {
            acc += distance(outgoing[j], outgoing[j + 1])
            after = outgoing[j + 1]
            if acc >= lookMeters { break }
            j += 1
        }

        guard let a = before, let b = after,
              distance(a, junctionIn) >= 1, distance(junctionOut, b) >= 1 else { return nil }
        let inBearing = bearing(from: a, to: junctionIn)
        let outBearing = bearing(from: junctionOut, to: b)
        return normalize180(outBearing - inBearing)
    }

    /// The point `meters` along a bearing from `start` (spherical destination formula).
    public static func destination(from start: Coordinate, bearing: Double, meters: Double) -> Coordinate {
        let d = meters / earthRadiusM
        let th = rad(bearing)
        let p1 = rad(start.latitude), l1 = rad(start.longitude)
        let p2 = asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(th))
        let l2 = l1 + atan2(sin(th) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2))
        return Coordinate(latitude: deg(p2), longitude: normalize180(deg(l2)))
    }
}
