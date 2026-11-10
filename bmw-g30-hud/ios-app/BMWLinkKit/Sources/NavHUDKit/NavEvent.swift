// SPDX-License-Identifier: MIT
// Vendor-neutral turn-by-turn navigation event (Module 3).
// Mirrors sim/navhud/nav_events.py; JSON keys are identical (snake_case) so
// both implementations share test-vectors/hud_golden.json.
import Foundation

/// Maneuver pictograms, chosen to map onto the fixed BMW guidance-arrow set.
public enum Maneuver: String, Codable, CaseIterable, Sendable {
    case `continue` = "continue"
    case turnLeft = "turn_left"
    case turnRight = "turn_right"
    case slightLeft = "slight_left"
    case slightRight = "slight_right"
    case sharpLeft = "sharp_left"
    case sharpRight = "sharp_right"
    case uturn = "uturn"
    case keepLeft = "keep_left"
    case keepRight = "keep_right"
    case merge = "merge"
    case roundabout = "roundabout"
    case exitLeft = "exit_left"
    case exitRight = "exit_right"
    case ferry = "ferry"
    case destination = "destination"

    public var isTurn: Bool { self != .continue && self != .destination }
}

/// Driving side; affects default exit side and roundabout rotation.
public enum Side: String, Codable, Sendable {
    case right
    case left
}

public enum EventKind: String, Codable, Sendable {
    case guidance
    case reroute
    case arrival
    case navEnded = "nav_ended"
    case navStarted = "nav_started"
}

/// One normalized navigation update. Meters and seconds (SI); the translator
/// localizes to feet/miles for a US car.
public struct NavEvent: Codable, Equatable, Sendable {
    public var eventId: Int
    public var kind: EventKind
    public var maneuver: Maneuver
    /// Distance from the car to the *next* maneuver point, meters.
    public var distanceToManeuverM: Double
    public var roadName: String
    public var exitName: String
    public var exitNumber: String
    /// Which roundabout exit to take (1-based).
    public var roundaboutExit: Int?
    public var distanceRemainingM: Double?
    public var etaEpochS: Int?
    public var lanes: [String]
    public var side: Side

    public init(eventId: Int,
                kind: EventKind = .guidance,
                maneuver: Maneuver = .continue,
                distanceToManeuverM: Double = 0,
                roadName: String = "",
                exitName: String = "",
                exitNumber: String = "",
                roundaboutExit: Int? = nil,
                distanceRemainingM: Double? = nil,
                etaEpochS: Int? = nil,
                lanes: [String] = [],
                side: Side = .right) {
        self.eventId = eventId
        self.kind = kind
        self.maneuver = maneuver
        self.distanceToManeuverM = distanceToManeuverM
        self.roadName = roadName
        self.exitName = exitName
        self.exitNumber = exitNumber
        self.roundaboutExit = roundaboutExit
        self.distanceRemainingM = distanceRemainingM
        self.etaEpochS = etaEpochS
        self.lanes = lanes
        self.side = side
    }

    public enum ValidationError: Error, Equatable {
        case negativeEventId
        case negativeDistance
        case roundaboutExitNotOneBased
        case negativeRemaining
    }

    /// Same rules as the Python reference's __post_init__.
    public func validate() throws {
        if eventId < 0 { throw ValidationError.negativeEventId }
        if distanceToManeuverM < 0 { throw ValidationError.negativeDistance }
        if maneuver == .roundabout, let e = roundaboutExit, e < 1 {
            throw ValidationError.roundaboutExitNotOneBased
        }
        if let r = distanceRemainingM, r < 0 { throw ValidationError.negativeRemaining }
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case kind
        case maneuver
        case distanceToManeuverM = "distance_to_maneuver_m"
        case roadName = "road_name"
        case exitName = "exit_name"
        case exitNumber = "exit_number"
        case roundaboutExit = "roundabout_exit"
        case distanceRemainingM = "distance_remaining_m"
        case etaEpochS = "eta_epoch_s"
        case lanes
        case side
    }

    /// Missing keys take the same defaults as the Python `from_dict`; unknown
    /// keys (e.g. Python's `extra`) are ignored so the schema can grow.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decode(Int.self, forKey: .eventId)
        kind = try c.decodeIfPresent(EventKind.self, forKey: .kind) ?? .guidance
        maneuver = try c.decodeIfPresent(Maneuver.self, forKey: .maneuver) ?? .continue
        distanceToManeuverM = try c.decodeIfPresent(Double.self, forKey: .distanceToManeuverM) ?? 0
        roadName = try c.decodeIfPresent(String.self, forKey: .roadName) ?? ""
        exitName = try c.decodeIfPresent(String.self, forKey: .exitName) ?? ""
        exitNumber = try c.decodeIfPresent(String.self, forKey: .exitNumber) ?? ""
        roundaboutExit = try c.decodeIfPresent(Int.self, forKey: .roundaboutExit)
        distanceRemainingM = try c.decodeIfPresent(Double.self, forKey: .distanceRemainingM)
        etaEpochS = try c.decodeIfPresent(Int.self, forKey: .etaEpochS)
        lanes = try c.decodeIfPresent([String].self, forKey: .lanes) ?? []
        side = try c.decodeIfPresent(Side.self, forKey: .side) ?? .right
    }
}
