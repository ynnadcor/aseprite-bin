// SPDX-License-Identifier: MIT
// Display-sink capability profiles and the HUD frame IR (Module 4).
// Mirrors sim/navhud/hud_model.py. The limits are conservative estimates for a
// 2018 G30 cluster/HUD; exact glyph metrics still need an on-car check.
import Foundation

public struct HudProfile: Equatable, Sendable {
    public let name: String
    /// Pictograms the panel can actually show (fixed icon set in the cluster).
    public let supportedManeuvers: Set<Maneuver>
    public let maxLabelChars: Int
    public let supportsDistance: Bool
    public let supportsLanes: Bool
    public let supportsRoundaboutExit: Bool
    public let supportsEta: Bool
    /// Coarse countdown steps (meters); only the first (the bar's full scale) is used.
    public let distanceStepsM: [Double]

    public init(name: String, supportedManeuvers: Set<Maneuver>, maxLabelChars: Int,
                supportsDistance: Bool, supportsLanes: Bool, supportsRoundaboutExit: Bool,
                supportsEta: Bool,
                distanceStepsM: [Double] = [1000, 500, 300, 200, 150, 100, 70, 50, 30, 10, 0]) {
        self.name = name
        self.supportedManeuvers = supportedManeuvers
        self.maxLabelChars = maxLabelChars
        self.supportsDistance = supportsDistance
        self.supportsLanes = supportsLanes
        self.supportsRoundaboutExit = supportsRoundaboutExit
        self.supportsEta = supportsEta
        self.distanceStepsM = distanceStepsM
    }

    public func canShow(_ m: Maneuver) -> Bool { supportedManeuvers.contains(m) }

    /// Windshield HUD: arrow + distance + short label. No lanes, no ETA.
    public static let g30HUD = HudProfile(
        name: "G30-HUD",
        supportedManeuvers: Set(Maneuver.allCases).subtracting([.ferry]),
        maxLabelChars: 18,
        supportsDistance: true,
        supportsLanes: false,
        supportsRoundaboutExit: true,
        supportsEta: false
    )

    /// Instrument-cluster guidance strip: a bit more room, lanes and ETA.
    public static let g30KOMBI = HudProfile(
        name: "G30-KOMBI",
        supportedManeuvers: Set(Maneuver.allCases),
        maxLabelChars: 24,
        supportsDistance: true,
        supportsLanes: true,
        supportsRoundaboutExit: true,
        supportsEta: true
    )

    public static let all: [HudProfile] = [.g30HUD, .g30KOMBI]

    public static func named(_ name: String) -> HudProfile? {
        all.first { $0.name == name }
    }
}

/// What a constrained panel can depict, nothing more. `arrow` is always one the
/// target profile can show (the translator guarantees it).
public struct HudFrame: Codable, Equatable, Sendable {
    public var profileName: String
    public var visible: Bool
    public var arrow: Maneuver
    /// Already localized, e.g. "500 ft", "1.2 mi", "now".
    public var distanceText: String
    /// 0...1 countdown-bar fill (1 = far away).
    public var distanceFraction: Double
    /// Road/exit text, already truncated to the profile's budget.
    public var label: String
    public var roundaboutExit: Int?
    public var lanes: [String]
    public var etaText: String
    /// "Rerouting", "Arrived", or "".
    public var banner: String

    public init(profileName: String, visible: Bool = true, arrow: Maneuver = .continue,
                distanceText: String = "", distanceFraction: Double = 0, label: String = "",
                roundaboutExit: Int? = nil, lanes: [String] = [], etaText: String = "",
                banner: String = "") {
        self.profileName = profileName
        self.visible = visible
        self.arrow = arrow
        self.distanceText = distanceText
        self.distanceFraction = distanceFraction
        self.label = label
        self.roundaboutExit = roundaboutExit
        self.lanes = lanes
        self.etaText = etaText
        self.banner = banner
    }

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case visible
        case arrow
        case distanceText = "distance_text"
        case distanceFraction = "distance_fraction"
        case label
        case roundaboutExit = "roundabout_exit"
        case lanes
        case etaText = "eta_text"
        case banner
    }
}
