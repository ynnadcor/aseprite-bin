// SPDX-License-Identifier: MIT
// A built-in synthetic route for previews and tests. It needs no network and
// no GPS. It is placed at the geographic center of the contiguous US purely as
// a neutral spot; the roads are invented.
import Foundation

public enum DemoRoute {
    public static let destinationName = "Demo Destination"

    /// One leg = instruction for the maneuver at its start, travel bearing, length.
    static let legs: [(String, Double, Double)] = [
        ("Head east on Main St", 90, 700),
        ("Turn left onto Elm St", 0, 900),
        ("Slight right onto Oak Ave", 30, 1200),
        ("At the roundabout, take the 2nd exit onto Park Blvd", 35, 800),
        ("Keep left at the fork", 20, 1500),
        ("Take exit 12 toward Airport", 45, 600),
        ("Turn right onto Airport Rd", 135, 1100),
        ("Arrive at your destination", 0, 0),
    ]

    public static func steps(
        origin: Coordinate = Coordinate(latitude: 39.8283, longitude: -98.5795)
    ) -> [RouteStep] {
        var steps: [RouteStep] = []
        var cur = origin
        for (text, bearing, meters) in legs {
            if meters > 0 {
                let mid = GeoMath.destination(from: cur, bearing: bearing, meters: meters / 2)
                let end = GeoMath.destination(from: cur, bearing: bearing, meters: meters)
                steps.append(RouteStep(instruction: text, distanceMeters: meters,
                                       coordinates: [cur, mid, end]))
                cur = end
            } else {
                steps.append(RouteStep(instruction: text, distanceMeters: 0, coordinates: [cur]))
            }
        }
        return steps
    }

    /// Ready-to-play guidance with an ETA `minutes` from `now`.
    public static func guidance(now: Date = Date(), minutes: Double = 11) -> RouteGuidance {
        RouteGuidance(steps: steps(),
                      etaEpochS: Int(now.timeIntervalSince1970 + minutes * 60),
                      destinationName: destinationName)
    }
}
