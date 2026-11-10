// SPDX-License-Identifier: MIT
import XCTest
@testable import NavHUDKit

final class RouteTrackerTests: XCTestCase {

    func makeTracker() -> RouteTracker {
        RouteTracker(guidance: DemoRoute.guidance(now: Date(timeIntervalSince1970: 0)))
    }

    /// The point `progress` meters along the route, optionally pushed sideways.
    func point(_ tracker: RouteTracker, at progress: Double, offsetM: Double = 0) -> Coordinate {
        let seg = tracker.segments.first { progress <= $0.endProgress } ?? tracker.segments.last!
        let span = seg.endProgress - seg.startProgress
        let t = span > 0 ? (progress - seg.startProgress) / span : 0
        let heading = GeoMath.bearing(from: seg.a, to: seg.b)
        let onRoute = GeoMath.destination(from: seg.a, bearing: heading,
                                          meters: t * GeoMath.distance(seg.a, seg.b))
        return offsetM == 0 ? onRoute
            : GeoMath.destination(from: onRoute, bearing: heading + 90, meters: offsetM)
    }

    func testOnRouteFixesRecoverProgress() {
        let tr = makeTracker()
        for p in stride(from: 0.0, through: 6700, by: 335) {
            let e = tr.update(location: point(tr, at: p))
            XCTAssertEqual(tr.progressM, p, accuracy: 1.0, "at \(p) m")
            XCTAssertFalse(tr.isOffRoute)
            XCTAssertEqual(e.kind, .guidance)
        }
    }

    func testLateralOffsetStillOnRoute() {
        let tr = makeTracker()
        tr.update(location: point(tr, at: 1000, offsetM: 12))
        XCTAssertEqual(tr.progressM, 1000, accuracy: 1.5)
        XCTAssertEqual(tr.lastDistanceFromRouteM, 12, accuracy: 0.5)
        XCTAssertFalse(tr.isOffRoute)
    }

    func testSmallBackwardJitterIsHeld() {
        let tr = makeTracker()
        tr.update(location: point(tr, at: 500))
        let before = tr.event(at: tr.progressM)
        tr.update(location: point(tr, at: 488))          // 12 m "behind": GPS noise
        XCTAssertEqual(tr.progressM, 500, accuracy: 1.0)  // held, countdown can't rise
        XCTAssertEqual(tr.event(at: tr.progressM).distanceToManeuverM,
                       before.distanceToManeuverM, accuracy: 1.0)
    }

    func testOffRouteRaisesRerouteThenRecovers() {
        let tr = makeTracker()
        tr.update(location: point(tr, at: 800))
        let e = tr.update(location: point(tr, at: 820, offsetM: 150))
        XCTAssertTrue(tr.isOffRoute)
        XCTAssertEqual(e.kind, .reroute)
        XCTAssertEqual(tr.progressM, 800, accuracy: 1.0)  // unchanged while off-route
        tr.update(location: point(tr, at: 850))
        XCTAssertFalse(tr.isOffRoute)
        XCTAssertEqual(tr.progressM, 850, accuracy: 1.0)
    }

    func testNoisyFullDriveCountsDownAndArrives() {
        let tr = makeTracker()
        // deterministic pseudo-random lateral noise in [-6, 6] m
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53) * 12 - 6
        }
        var last: NavEvent?
        var lastFed = 0.0
        for p in stride(from: 0.0, through: 6790, by: 20) {
            lastFed = p
            let e = tr.update(location: point(tr, at: p, offsetM: noise()))
            XCTAssertFalse(tr.isOffRoute, "spurious off-route at \(p) m")
            if let l = last, l.maneuver == e.maneuver, l.roadName == e.roadName, l.kind == e.kind {
                XCTAssertLessThanOrEqual(e.distanceToManeuverM, l.distanceToManeuverM + 1e-6,
                                         "countdown rose at \(p) m")
            }
            last = e
        }
        XCTAssertEqual(lastFed, 6780)                       // stride by 20 stops at 6780
        XCTAssertEqual(tr.progressM, lastFed, accuracy: 2)
        XCTAssertEqual(last?.maneuver, .destination)        // final leg: arrival ahead
        XCTAssertEqual(last?.distanceToManeuverM ?? -1, 6800 - lastFed, accuracy: 2)
    }

    func testEmptyRouteReportsArrival() {
        let tr = RouteTracker(guidance: RouteGuidance(steps: []))
        XCTAssertEqual(tr.update(location: Coordinate(latitude: 0, longitude: 0)).kind, .arrival)
    }
}

private extension RouteTracker {
    func event(at progress: Double) -> NavEvent { guidance.event(atProgress: progress) }
}
