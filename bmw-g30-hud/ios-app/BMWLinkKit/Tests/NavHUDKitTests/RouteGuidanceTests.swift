// SPDX-License-Identifier: MIT
import XCTest
@testable import NavHUDKit

/// A synthetic MapKit-shaped route: north 400 m on Main St, right onto Elm St
/// (600 m east), slight left onto Oak Ave (500 m at 60 deg), roundabout 2nd exit
/// onto Park Blvd (300 m), arrive.
enum SyntheticRoute {
    static let origin = Coordinate(latitude: 39.8283, longitude: -98.5795)

    static func steps(_ texts: [String]) -> [RouteStep] {
        precondition(texts.count == 5)
        let p0 = origin
        let p1 = GeoMath.destination(from: p0, bearing: 0, meters: 400)
        let p2 = GeoMath.destination(from: p1, bearing: 90, meters: 600)
        let p3 = GeoMath.destination(from: p2, bearing: 60, meters: 500)
        let p4 = GeoMath.destination(from: p3, bearing: 65, meters: 300)
        func mid(_ a: Coordinate, _ bearing: Double, _ m: Double) -> Coordinate {
            GeoMath.destination(from: a, bearing: bearing, meters: m)
        }
        return [
            RouteStep(instruction: texts[0], distanceMeters: 400, coordinates: [p0, mid(p0, 0, 200), p1]),
            RouteStep(instruction: texts[1], distanceMeters: 600, coordinates: [p1, mid(p1, 90, 300), p2]),
            RouteStep(instruction: texts[2], distanceMeters: 500, coordinates: [p2, mid(p2, 60, 250), p3]),
            RouteStep(instruction: texts[3], distanceMeters: 300, coordinates: [p3, mid(p3, 65, 150), p4]),
            RouteStep(instruction: texts[4], distanceMeters: 0, coordinates: [p4]),
        ]
    }

    static let english = [
        "Head north on Main St",
        "Turn right onto Elm St",
        "Slight left onto Oak Ave",
        "At the roundabout, take the 2nd exit onto Park Blvd",
        "Arrive at your destination",
    ]

    static let german = [
        "Fahren Sie nach Norden auf Main St",
        "Rechts abbiegen auf Elm St",
        "Leicht links abbiegen auf Oak Ave",
        "Im Kreisverkehr die zweite Ausfahrt nehmen",
        "Sie haben Ihr Ziel erreicht",
    ]
}

final class RouteGuidanceTests: XCTestCase {

    func testManeuversFromEnglishText() {
        let g = RouteGuidance(steps: SyntheticRoute.steps(SyntheticRoute.english))
        XCTAssertEqual(g.maneuvers.map(\.maneuver),
                       [.continue, .turnRight, .slightLeft, .roundabout, .destination])
        XCTAssertEqual(g.maneuvers.map(\.roadName), ["Main St", "Elm St", "Oak Ave", "Park Blvd", ""])
        XCTAssertEqual(g.maneuvers[3].roundaboutExit, 2)
        XCTAssertEqual(g.totalDistanceM, 1800, accuracy: 1e-9)
    }

    func testManeuversFromGeometryWhenTextIsNotEnglish() {
        let g = RouteGuidance(steps: SyntheticRoute.steps(SyntheticRoute.german))
        let ms = g.maneuvers.map(\.maneuver)
        XCTAssertEqual(ms[1], .turnRight)     // +90 deg
        XCTAssertEqual(ms[2], .slightLeft)    // -30 deg
        // Geometry alone cannot tell a roundabout from going straight: honest limit.
        XCTAssertEqual(ms[3], .continue)
        XCTAssertEqual(ms[4], .destination)   // last step is always arrival
        XCTAssertEqual(g.maneuvers[1].basis, .geometry)
    }

    func testEventAtProgress() {
        let g = RouteGuidance(steps: SyntheticRoute.steps(SyntheticRoute.english),
                              destinationName: "Park Blvd 100")
        let e1 = g.event(atProgress: 100)
        XCTAssertEqual(e1.maneuver, .turnRight)
        XCTAssertEqual(e1.distanceToManeuverM, 300, accuracy: 1e-9)
        XCTAssertEqual(e1.roadName, "Elm St")
        XCTAssertEqual(e1.distanceRemainingM ?? -1, 1700, accuracy: 1e-9)

        let e2 = g.event(atProgress: 450)
        XCTAssertEqual(e2.maneuver, .slightLeft)
        XCTAssertEqual(e2.distanceToManeuverM, 550, accuracy: 1e-9)

        let e3 = g.event(atProgress: 1250)
        XCTAssertEqual(e3.maneuver, .roundabout)
        XCTAssertEqual(e3.roundaboutExit, 2)
        XCTAssertEqual(e3.roadName, "Park Blvd")

        let e4 = g.event(atProgress: 1600)  // final leg -> arrival ahead
        XCTAssertEqual(e4.maneuver, .destination)
        XCTAssertEqual(e4.distanceToManeuverM, 200, accuracy: 1e-9)
        XCTAssertEqual(e4.roadName, "Park Blvd")  // falls back to the current road

        let end = g.event(atProgress: 5000)
        XCTAssertEqual(end.kind, .arrival)
        XCTAssertEqual(end.roadName, "Park Blvd 100")
    }

    func testSimulatedDriveIsWellFormed() throws {
        let g = RouteGuidance(steps: SyntheticRoute.steps(SyntheticRoute.english))
        let events = g.simulateDrive()
        XCTAssertEqual(events.first?.kind, .navStarted)
        XCTAssertEqual(events[events.count - 2].kind, .arrival)
        XCTAssertEqual(events.last?.kind, .navEnded)

        // ids strictly increase; every event is valid
        for (a, b) in zip(events, events.dropFirst()) {
            XCTAssertLessThan(a.eventId, b.eventId)
        }
        for e in events { XCTAssertNoThrow(try e.validate()) }

        // within an approach to the same maneuver, the distance only shrinks
        let guidance = events.filter { $0.kind == .guidance }
        for (a, b) in zip(guidance, guidance.dropFirst())
            where a.maneuver == b.maneuver && a.roadName == b.roadName {
            XCTAssertGreaterThan(a.distanceToManeuverM, b.distanceToManeuverM)
        }
        // every real maneuver gets announced
        let announced = Set(guidance.map(\.maneuver))
        XCTAssertTrue(announced.isSuperset(of: [.turnRight, .slightLeft, .roundabout, .destination]))
    }

    func testEndToEndThroughTheHudTranslator() {
        let g = RouteGuidance(steps: SyntheticRoute.steps(SyntheticRoute.english))
        let hud = Translator(profile: .g30HUD)
        let frames = g.simulateDrive().map(hud.translate)
        XCTAssertTrue(frames.allSatisfy { HudProfile.g30HUD.canShow($0.arrow) })
        XCTAssertTrue(frames.contains { $0.arrow == .roundabout && $0.roundaboutExit == 2 })
        XCTAssertTrue(frames.contains { $0.arrow == .turnRight && $0.label == "Elm St" })
        XCTAssertEqual(frames.last?.visible, false)          // navigation ended -> HUD off
        XCTAssertEqual(frames[frames.count - 2].banner, "Arrived")
    }

    func testEmptyRouteGoesStraightToArrival() {
        let g = RouteGuidance(steps: [])
        XCTAssertEqual(g.event(atProgress: 0).kind, .arrival)
        XCTAssertEqual(g.simulateDrive().map(\.kind), [.navStarted, .arrival, .navEnded])
    }
}

final class DemoRouteTests: XCTestCase {
    func testDemoRouteClassifiesAsDesigned() {
        let g = DemoRoute.guidance(now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(g.maneuvers.map(\.maneuver),
                       [.continue, .turnLeft, .slightRight, .roundabout, .keepLeft,
                        .exitRight, .turnRight, .destination])
        XCTAssertEqual(g.maneuvers[5].exitNumber, "12")
        XCTAssertEqual(g.maneuvers[5].exitName, "Airport")
        XCTAssertEqual(g.totalDistanceM, 6800, accuracy: 1e-9)
        XCTAssertEqual(g.etaEpochS, 660)
    }

    func testDemoDriveRendersOnBothDisplays() {
        for profile in HudProfile.all {
            let frames = DemoRoute.guidance().simulateDrive().map(Translator(profile: profile).translate)
            XCTAssertGreaterThan(frames.count, 20)
            XCTAssertTrue(frames.allSatisfy { profile.canShow($0.arrow) })
            XCTAssertTrue(frames.allSatisfy { $0.label.count <= profile.maxLabelChars })
            XCTAssertTrue(frames.contains { $0.label == "12 Airport" }, profile.name)
        }
    }
}
