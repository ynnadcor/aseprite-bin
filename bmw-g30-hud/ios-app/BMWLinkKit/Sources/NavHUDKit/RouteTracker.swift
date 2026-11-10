// SPDX-License-Identifier: MIT
// Live progress along a planned route from GPS fixes (map matching).
//
// Projects each fix onto the route polyline to find how far along the route
// the car is, then asks RouteGuidance for the matching NavEvent. Guards
// against the usual GPS problems:
//  - jitter: progress never moves backwards by more than `maxBacktrackM`;
//  - routes that pass the same place twice: matches near the current progress
//    are preferred over equally close matches far away on the route;
//  - leaving the route: if the best match is farther than `offRouteM`, the
//    tracker reports off-route (and emits a "reroute" event) so the caller can
//    request a new route.
import Foundation

public final class RouteTracker {
    public let guidance: RouteGuidance
    /// Distance from the route beyond which the car is considered off-route.
    public var offRouteM: Double
    /// Largest backwards correction accepted (GPS noise), meters.
    public var maxBacktrackM: Double
    /// Look-ahead window searched first (meters past the current progress).
    public var lookAheadM: Double

    public private(set) var progressM: Double = 0
    public private(set) var isOffRoute = false
    public private(set) var lastDistanceFromRouteM: Double = 0

    struct Segment {
        let a: Coordinate
        let b: Coordinate
        /// Route progress (declared step distances) at `a` and `b`.
        let startProgress: Double
        let endProgress: Double
    }
    let segments: [Segment]

    public init(guidance: RouteGuidance, offRouteM: Double = 50, maxBacktrackM: Double = 30,
                lookAheadM: Double = 2000) {
        self.guidance = guidance
        self.offRouteM = offRouteM
        self.maxBacktrackM = maxBacktrackM
        self.lookAheadM = lookAheadM
        self.segments = RouteTracker.buildSegments(guidance)
    }

    /// Polyline segments, with progress scaled per step so polyline geometry
    /// and the step's declared distance (what event(atProgress:) uses) agree.
    static func buildSegments(_ g: RouteGuidance) -> [Segment] {
        var out: [Segment] = []
        var stepStart = 0.0
        for (i, step) in g.steps.enumerated() {
            let stepEnd = g.cumulativeEndM[i]
            let pts = step.coordinates
            let polyLen = GeoMath.pathLength(pts)
            if pts.count >= 2 && polyLen > 0 {
                var acc = 0.0
                for k in 1..<pts.count {
                    let len = GeoMath.distance(pts[k - 1], pts[k])
                    let s = stepStart + (acc / polyLen) * (stepEnd - stepStart)
                    acc += len
                    let e = stepStart + (acc / polyLen) * (stepEnd - stepStart)
                    out.append(Segment(a: pts[k - 1], b: pts[k], startProgress: s, endProgress: e))
                }
            }
            stepStart = stepEnd
        }
        return out
    }

    /// Nearest point on a segment, in a local flat (equirectangular) frame -
    /// accurate to well under a meter over street-length segments.
    static func project(_ p: Coordinate, onto seg: Segment) -> (t: Double, distanceM: Double) {
        let lat0 = GeoMath.rad(seg.a.latitude)
        let r = GeoMath.earthRadiusM
        func xy(_ c: Coordinate) -> (Double, Double) {
            (GeoMath.rad(c.longitude - seg.a.longitude) * cos(lat0) * r,
             GeoMath.rad(c.latitude - seg.a.latitude) * r)
        }
        let (bx, by) = xy(seg.b)
        let (px, py) = xy(p)
        let len2 = bx * bx + by * by
        let t = len2 > 0 ? max(0, min(1, (px * bx + py * by) / len2)) : 0
        let dx = px - t * bx, dy = py - t * by
        return (t, sqrt(dx * dx + dy * dy))
    }

    /// Best match among segments whose progress range intersects [lo, hi].
    func bestMatch(_ p: Coordinate, lo: Double, hi: Double) -> (progress: Double, distanceM: Double)? {
        var best: (progress: Double, distanceM: Double)?
        for seg in segments where seg.endProgress >= lo && seg.startProgress <= hi {
            let (t, d) = RouteTracker.project(p, onto: seg)
            if let b = best, b.distanceM <= d { continue }
            best = (seg.startProgress + t * (seg.endProgress - seg.startProgress), d)
        }
        return best
    }

    /// Feed one GPS fix; returns the event to display.
    @discardableResult
    public func update(location: Coordinate) -> NavEvent {
        guard !segments.isEmpty else { return guidance.event(atProgress: guidance.totalDistanceM) }

        // 1) near where we are now, 2) anywhere on the route.
        let windowed = bestMatch(location, lo: progressM - maxBacktrackM, hi: progressM + lookAheadM)
        let match: (progress: Double, distanceM: Double)?
        if let w = windowed, w.distanceM <= offRouteM {
            match = w
        } else {
            match = bestMatch(location, lo: -.infinity, hi: .infinity)
        }
        guard let m = match else { return guidance.event(atProgress: progressM) }

        lastDistanceFromRouteM = m.distanceM
        if m.distanceM > offRouteM {
            isOffRoute = true
            var e = guidance.event(atProgress: progressM)
            e.kind = .reroute
            return e
        }
        isOffRoute = false
        if m.progress >= progressM {
            progressM = m.progress            // normal forward motion
        } else if m.progress >= progressM - maxBacktrackM {
            // small backwards GPS jitter: hold position so the HUD countdown never rises
        } else {
            progressM = m.progress            // re-acquired elsewhere on the route
        }
        return guidance.event(atProgress: progressM)
    }
}
