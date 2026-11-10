// SPDX-License-Identifier: MIT
// Turns a planned route (a list of steps) into a stream of NavEvents.
//
// Step semantics follow MapKit's `MKRoute.Step`: a step's instruction is the
// maneuver performed at the START of that step, and its distance is the length
// of the road travelled after it. So while driving step i, the upcoming
// maneuver is step i+1, at the end of step i.
import Foundation

/// A platform-neutral route step (MapKit-free, so it is testable on Linux).
public struct RouteStep: Equatable, Sendable {
    public var instruction: String
    public var distanceMeters: Double
    public var coordinates: [Coordinate]
    public var notice: String?

    public init(instruction: String, distanceMeters: Double,
                coordinates: [Coordinate] = [], notice: String? = nil) {
        self.instruction = instruction
        self.distanceMeters = distanceMeters
        self.coordinates = coordinates
        self.notice = notice
    }
}

public final class RouteGuidance {
    public let steps: [RouteStep]
    public let side: Side
    /// Maneuver at the start of each step, index-aligned with `steps`.
    public let maneuvers: [ClassifiedManeuver]
    public let totalDistanceM: Double
    public let etaEpochS: Int?
    public let destinationName: String
    /// Cumulative distance at the END of each step.
    public let cumulativeEndM: [Double]
    private var nextEventId = 1

    /// Countdown checkpoints (meters before a maneuver) used by `simulateDrive`.
    public static let defaultCountdownM: [Double] = [1600, 800, 400, 200, 100, 50, 20]

    public init(steps: [RouteStep], side: Side = .right, etaEpochS: Int? = nil,
                destinationName: String = "") {
        self.steps = steps
        self.side = side
        self.etaEpochS = etaEpochS
        self.destinationName = destinationName

        var cum: [Double] = []
        var total = 0.0
        for s in steps {
            total += max(0, s.distanceMeters)
            cum.append(total)
        }
        cumulativeEndM = cum
        totalDistanceM = total

        var ms: [ClassifiedManeuver] = []
        for (i, s) in steps.enumerated() {
            let angle = i > 0
                ? GeoMath.turnAngle(incoming: steps[i - 1].coordinates, outgoing: s.coordinates)
                : nil
            var c = ManeuverClassifier.classify(instruction: s.instruction, turnAngle: angle,
                                                side: side)
            // A route always ends in arrival, whatever language the text is in.
            if i == steps.count - 1 && i > 0 && c.basis != .text {
                c.maneuver = .destination
            }
            ms.append(c)
        }
        maneuvers = ms
    }

    private func takeId() -> Int {
        defer { nextEventId += 1 }
        return nextEventId
    }

    /// Index of the step being driven `progress` meters from the start.
    public func stepIndex(atProgress p: Double) -> Int {
        for (i, end) in cumulativeEndM.enumerated() where p < end { return i }
        return max(0, steps.count - 1)
    }

    /// The guidance event for a position `progress` meters along the route.
    public func event(atProgress progress: Double) -> NavEvent {
        let p = min(max(0, progress), totalDistanceM)
        if steps.isEmpty || p >= totalDistanceM { return arrivalEvent() }

        let i = stepIndex(atProgress: p)
        let toManeuver = max(0, cumulativeEndM[i] - p)
        let current = maneuvers[i]

        let upcoming: ClassifiedManeuver
        if i + 1 < steps.count {
            upcoming = maneuvers[i + 1]
        } else {
            // Final leg with no explicit arrival step: the next thing is arrival.
            upcoming = ClassifiedManeuver(maneuver: .destination, roadName: current.roadName,
                                          basis: .none)
        }
        let road = upcoming.roadName.isEmpty ? current.roadName : upcoming.roadName

        return NavEvent(eventId: takeId(), kind: .guidance, maneuver: upcoming.maneuver,
                        distanceToManeuverM: toManeuver, roadName: road,
                        exitName: upcoming.exitName, exitNumber: upcoming.exitNumber,
                        roundaboutExit: upcoming.roundaboutExit,
                        distanceRemainingM: totalDistanceM - p, etaEpochS: etaEpochS,
                        lanes: [], side: side)
    }

    public func startedEvent() -> NavEvent {
        NavEvent(eventId: takeId(), kind: .navStarted, maneuver: .continue,
                 distanceToManeuverM: 0, roadName: maneuvers.first?.roadName ?? "",
                 distanceRemainingM: totalDistanceM, etaEpochS: etaEpochS, side: side)
    }

    public func arrivalEvent() -> NavEvent {
        NavEvent(eventId: takeId(), kind: .arrival, maneuver: .destination,
                 roadName: destinationName, distanceRemainingM: 0, etaEpochS: etaEpochS,
                 side: side)
    }

    public func endedEvent() -> NavEvent {
        NavEvent(eventId: takeId(), kind: .navEnded, side: side)
    }

    /// A whole simulated drive: start, a countdown toward every maneuver, arrival, end.
    /// Needs no GPS - used for previews and for testing with real Apple routes.
    public func simulateDrive(countdownM: [Double] = RouteGuidance.defaultCountdownM) -> [NavEvent] {
        let ladder = countdownM.filter { $0 > 0 }.sorted(by: >)
        var out: [NavEvent] = [startedEvent()]
        var legStart = 0.0
        for i in steps.indices {
            let legEnd = cumulativeEndM[i]
            let legLength = legEnd - legStart
            if legLength > 0 {
                out.append(event(atProgress: legStart))
                for d in ladder where d < legLength {
                    out.append(event(atProgress: legEnd - d))
                }
            }
            legStart = legEnd
        }
        out.append(arrivalEvent())
        out.append(endedEvent())
        return out
    }
}
