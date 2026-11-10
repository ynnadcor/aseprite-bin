// SPDX-License-Identifier: MIT
// Apple MapKit as a navigation source (Module 3, real source).
//
// This uses Apple's own routing engine (the one behind Apple Maps) through
// the public MapKit API: search places, request a driving route, and convert
// its steps into RouteGuidance -> NavEvents. It does NOT read the Apple Maps
// app; your app does the routing itself, which is fully supported by iOS.
// Compiled only where MapKit exists (iOS/macOS). Not available on Linux.
import Foundation

#if canImport(MapKit)
import MapKit

public enum MapKitRouteSource {

    public enum SourceError: Error, LocalizedError {
        case noRoute
        case emptyQuery

        public var errorDescription: String? {
            switch self {
            case .noRoute: return "Apple Maps returned no driving route."
            case .emptyQuery: return "Enter a place to search for."
            }
        }
    }

    /// Convert an MKRoute into platform-neutral steps.
    public static func steps(from route: MKRoute) -> [RouteStep] {
        route.steps.map { step in
            let polyline = step.polyline
            let count = polyline.pointCount
            let points = polyline.points()
            var coords: [Coordinate] = []
            coords.reserveCapacity(count)
            for k in 0..<count {
                let c = points[k].coordinate
                coords.append(Coordinate(latitude: c.latitude, longitude: c.longitude))
            }
            return RouteStep(instruction: step.instructions, distanceMeters: step.distance,
                             coordinates: coords, notice: step.notice)
        }
    }

    /// Guidance for a route, with ETA = departure + Apple's expected travel time.
    public static func guidance(for route: MKRoute, destinationName: String = "",
                                side: Side = .right, departure: Date = Date()) -> RouteGuidance {
        let eta = Int(departure.addingTimeInterval(route.expectedTravelTime).timeIntervalSince1970)
        return RouteGuidance(steps: steps(from: route), side: side, etaEpochS: eta,
                             destinationName: destinationName)
    }

    /// Apple Maps place search.
    @MainActor
    public static func search(_ query: String,
                              near center: CLLocationCoordinate2D? = nil) async throws -> [MKMapItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw SourceError.emptyQuery }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        if let c = center {
            request.region = MKCoordinateRegion(center: c, latitudinalMeters: 80_000,
                                                longitudinalMeters: 80_000)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
    }

    /// Ask Apple's routing engine for a driving route.
    @MainActor
    public static func route(from source: MKMapItem, to destination: MKMapItem) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw SourceError.noRoute }
        return route
    }
}
#endif
