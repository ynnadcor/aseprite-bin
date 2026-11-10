// SPDX-License-Identifier: MIT
import XCTest
@testable import NavHUDKit

final class ClassifierTests: XCTestCase {

    struct Row {
        let text: String
        let angle: Double?
        let maneuver: Maneuver
        var road: String = ""
        var exitNumber: String = ""
        var exitName: String = ""
        var roundabout: Int? = nil
    }

    // English instruction phrasings of the kind MapKit returns on en-US devices.
    let rows: [Row] = [
        Row(text: "Head north on Main St", angle: nil, maneuver: .continue, road: "Main St"),
        Row(text: "Proceed to the route", angle: nil, maneuver: .continue),
        Row(text: "Turn right onto E Main St", angle: 88, maneuver: .turnRight, road: "E Main St"),
        Row(text: "Turn left onto Lincoln Ave", angle: -91, maneuver: .turnLeft, road: "Lincoln Ave"),
        Row(text: "Slight left onto Oak Ave", angle: -30, maneuver: .slightLeft, road: "Oak Ave"),
        Row(text: "Bear right onto Mill Rd", angle: nil, maneuver: .slightRight, road: "Mill Rd"),
        Row(text: "Make a sharp right onto Hill Rd", angle: nil, maneuver: .sharpRight, road: "Hill Rd"),
        Row(text: "Make a U-turn", angle: nil, maneuver: .uturn),
        Row(text: "Keep left at the fork", angle: nil, maneuver: .keepLeft),
        Row(text: "Keep right to stay on I-94 W", angle: nil, maneuver: .keepRight, road: "I-94 W"),
        Row(text: "Merge onto I-94 W", angle: nil, maneuver: .merge, road: "I-94 W"),
        Row(text: "Take exit 215B toward Jefferson Ave", angle: 20, maneuver: .exitRight,
            road: "Jefferson Ave", exitNumber: "215B", exitName: "Jefferson Ave"),
        Row(text: "Take the exit on the left toward Downtown", angle: nil, maneuver: .exitLeft,
            road: "Downtown", exitName: "Downtown"),
        Row(text: "Take the ramp toward Airport", angle: -25, maneuver: .exitLeft,
            road: "Airport", exitName: "Airport"),
        Row(text: "Take exit 12 toward Leftwich", angle: 15, maneuver: .exitRight,
            road: "Leftwich", exitNumber: "12", exitName: "Leftwich"),
        Row(text: "At the roundabout, take the 2nd exit onto Park Blvd", angle: 5,
            maneuver: .roundabout, road: "Park Blvd", roundabout: 2),
        Row(text: "At the traffic circle, take the third exit", angle: nil,
            maneuver: .roundabout, roundabout: 3),
        Row(text: "Take the ferry", angle: nil, maneuver: .ferry),
        Row(text: "Arrive at your destination", angle: nil, maneuver: .destination),
        Row(text: "The destination is on your right", angle: nil, maneuver: .destination),
        Row(text: "Turn right onto Destination Pkwy", angle: 90, maneuver: .turnRight,
            road: "Destination Pkwy"),
    ]

    func testEnglishInstructionTable() {
        for r in rows {
            let c = ManeuverClassifier.classify(instruction: r.text, turnAngle: r.angle)
            XCTAssertEqual(c.maneuver, r.maneuver, r.text)
            XCTAssertEqual(c.roadName, r.road, "road: \(r.text)")
            XCTAssertEqual(c.exitNumber, r.exitNumber, "exit#: \(r.text)")
            XCTAssertEqual(c.exitName, r.exitName, "exit name: \(r.text)")
            XCTAssertEqual(c.roundaboutExit, r.roundabout, "roundabout: \(r.text)")
            XCTAssertEqual(c.basis, .text, "basis: \(r.text)")
        }
    }

    func testUnknownLanguageFallsBackToGeometry() {
        let right = ManeuverClassifier.classify(instruction: "Rechts abbiegen auf Elm St", turnAngle: 92)
        XCTAssertEqual(right.maneuver, .turnRight)
        XCTAssertEqual(right.basis, .geometry)

        let none = ManeuverClassifier.classify(instruction: "Rechts abbiegen", turnAngle: nil)
        XCTAssertEqual(none.maneuver, .continue)
        XCTAssertEqual(none.basis, .none)
    }

    func testAngleThresholds() {
        let table: [(Double, Maneuver)] = [
            (0, .continue), (14.9, .continue), (-14.9, .continue),
            (15, .slightRight), (-30, .slightLeft), (44.9, .slightRight),
            (45, .turnRight), (-90, .turnLeft), (134.9, .turnRight),
            (135, .sharpRight), (-150, .sharpLeft), (169.9, .sharpRight),
            (170, .uturn), (-175, .uturn), (180, .uturn),
        ]
        for (a, m) in table {
            XCTAssertEqual(ManeuverClassifier.maneuver(forTurnAngle: a), m, "angle \(a)")
        }
    }

    func testExitSideDefaultsToDrivingSideWithoutHints() {
        let rht = ManeuverClassifier.classify(instruction: "Take exit 5", turnAngle: nil, side: .right)
        XCTAssertEqual(rht.maneuver, .exitRight)
        let lht = ManeuverClassifier.classify(instruction: "Take exit 5", turnAngle: nil, side: .left)
        XCTAssertEqual(lht.maneuver, .exitLeft)
    }
}

final class GeoMathTests: XCTestCase {
    let origin = Coordinate(latitude: 39.8283, longitude: -98.5795)

    func testDistanceAndBearing() {
        let north = GeoMath.destination(from: origin, bearing: 0, meters: 1000)
        XCTAssertEqual(GeoMath.distance(origin, north), 1000, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: origin, to: north), 0, accuracy: 0.01)
        let east = GeoMath.destination(from: origin, bearing: 90, meters: 500)
        XCTAssertEqual(GeoMath.distance(origin, east), 500, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: origin, to: east), 90, accuracy: 0.05)
        // one degree of latitude is about 111.2 km
        let deg = Coordinate(latitude: 40.8283, longitude: -98.5795)
        XCTAssertEqual(GeoMath.distance(origin, deg), 111_195, accuracy: 50)
    }

    func testNormalize180() {
        XCTAssertEqual(GeoMath.normalize180(190), -170, accuracy: 1e-9)
        XCTAssertEqual(GeoMath.normalize180(-190), 170, accuracy: 1e-9)
        XCTAssertEqual(GeoMath.normalize180(180), 180, accuracy: 1e-9)
        XCTAssertEqual(GeoMath.normalize180(-180), 180, accuracy: 1e-9)
        XCTAssertEqual(GeoMath.normalize180(720), 0, accuracy: 1e-9)
    }

    func testTurnAngleIgnoresTinyJunctionJog() {
        let a = GeoMath.destination(from: origin, bearing: 0, meters: 300)  // drive north
        // a 2 m sideways jog right at the junction, typical of real polylines
        let jog = GeoMath.destination(from: a, bearing: 300, meters: 2)
        let incoming = [origin, GeoMath.destination(from: origin, bearing: 0, meters: 150), a]
        let outgoing = [a, jog, GeoMath.destination(from: a, bearing: 90, meters: 200)]
        let angle = try? XCTUnwrap(GeoMath.turnAngle(incoming: incoming, outgoing: outgoing))
        XCTAssertNotNil(angle)
        XCTAssertEqual(angle ?? 0, 90, accuracy: 8)
        XCTAssertEqual(ManeuverClassifier.maneuver(forTurnAngle: angle ?? 0), .turnRight)
    }

    func testTurnAngleNeedsGeometry() {
        XCTAssertNil(GeoMath.turnAngle(incoming: [origin], outgoing: [origin]))
        XCTAssertNil(GeoMath.turnAngle(incoming: [], outgoing: []))
    }
}
