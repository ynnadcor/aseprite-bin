// SPDX-License-Identifier: MIT
// NavEvent -> HudFrame for a given display profile (Module 4).
// A line-for-line port of sim/navhud/translator.py, verified against
// test-vectors/hud_golden.json. Degrades to the panel's real limits and never
// invents data: if a field isn't in the event, it isn't in the frame.
import Foundation

public struct Translator: Sendable {
    public let profile: HudProfile
    /// Used only to format ETA clock times (KOMBI). Injected for testability.
    public var timeZone: TimeZone

    public init(profile: HudProfile, timeZone: TimeZone = .current) {
        self.profile = profile
        self.timeZone = timeZone
    }

    public func translate(_ ev: NavEvent) -> HudFrame {
        let p = profile

        switch ev.kind {
        case .navEnded:
            return HudFrame(profileName: p.name, visible: false)
        case .arrival:
            return HudFrame(
                profileName: p.name,
                visible: true,
                arrow: Translator.resolveArrow(p, .destination),
                distanceText: "now",
                distanceFraction: 0,
                label: Translator.truncate(ev.roadName.isEmpty ? "Destination" : ev.roadName,
                                           p.maxLabelChars),
                banner: "Arrived"
            )
        case .guidance, .reroute, .navStarted:
            break
        }

        let banner = ev.kind == .reroute ? "Rerouting" : ""
        let arrow = Translator.resolveArrow(p, ev.maneuver)

        var distanceText = ""
        var distanceFraction = 0.0
        if p.supportsDistance {
            distanceText = Translator.usDistanceText(ev.distanceToManeuverM)
            distanceFraction = Translator.distanceFraction(p, ev.distanceToManeuverM)
        }

        // Prefer the exit signpost on highway exits, else the road name.
        let base: String
        if (ev.maneuver == .exitLeft || ev.maneuver == .exitRight) && !ev.exitName.isEmpty {
            base = ev.exitNumber.isEmpty ? ev.exitName : "\(ev.exitNumber) \(ev.exitName)"
        } else {
            base = ev.roadName
        }
        let label = Translator.truncate(base, p.maxLabelChars)

        let roundaboutExit = (p.supportsRoundaboutExit && ev.maneuver == .roundabout)
            ? ev.roundaboutExit : nil
        let lanes = (p.supportsLanes && !ev.lanes.isEmpty) ? ev.lanes : []

        var etaText = ""
        if p.supportsEta, let eta = ev.etaEpochS, eta != 0 {
            etaText = Translator.formatEta(eta, timeZone: timeZone)
        }

        return HudFrame(profileName: p.name, visible: true, arrow: arrow,
                        distanceText: distanceText, distanceFraction: distanceFraction,
                        label: label, roundaboutExit: roundaboutExit, lanes: lanes,
                        etaText: etaText, banner: banner)
    }

    // MARK: - helpers (public for tests and previews)

    static let arrowFallback: [Maneuver: Maneuver] = [
        .keepLeft: .slightLeft,
        .keepRight: .slightRight,
        .exitLeft: .slightLeft,
        .exitRight: .slightRight,
        .ferry: .continue,
        .sharpLeft: .turnLeft,
        .sharpRight: .turnRight,
        .slightLeft: .turnLeft,
        .slightRight: .turnRight,
        .merge: .continue,
        .roundabout: .continue,
    ]

    /// An arrow the profile can show, following the fallback chain.
    public static func resolveArrow(_ p: HudProfile, _ m: Maneuver) -> Maneuver {
        var seen = Set<Maneuver>()
        var cur = m
        while !p.canShow(cur) && !seen.contains(cur) {
            seen.insert(cur)
            cur = arrowFallback[cur] ?? .continue
        }
        return p.canShow(cur) ? cur : .continue
    }

    static let metersPerMile = 1609.344
    static let metersPerFoot = 0.3048

    /// Distance as a US cluster shows it. Rounding is half-to-even to match
    /// Python's round(), and never overshoots the next unit step (see Python).
    public static func usDistanceText(_ m: Double) -> String {
        if m <= 0 { return "now" }
        let feet = m / metersPerFoot
        if feet < 528 {
            var val: Int
            if feet < 100 {
                val = Int((feet / 10.0).rounded(.toNearestOrEven)) * 10
            } else {
                val = Int((feet / 50.0).rounded(.toNearestOrEven)) * 50
            }
            val = max(val, 10)
            if val < 528 { return "\(val) ft" }
            // rounded up past 0.1 mi: fall through to miles
        }
        let miles = m / metersPerMile
        if miles < 10 {
            let txt = String(format: "%.1f", miles)
            if txt != "10.0" { return "\(txt) mi" }
        }
        return "\(Int(miles.rounded(.toNearestOrEven))) mi"
    }

    /// 0...1 countdown-bar fill (1.0 = at or beyond the bar's full scale).
    public static func distanceFraction(_ p: HudProfile, _ m: Double) -> Double {
        let top = p.distanceStepsM.first ?? 1000
        if m >= top { return 1.0 }
        if m <= 0 { return 0.0 }
        return max(0.0, min(1.0, m / top))
    }

    /// Trim whitespace, then cut to `n` characters with a trailing ellipsis.
    public static func truncate(_ text: String, _ n: Int) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= n { return t }
        if n <= 1 { return String(t.prefix(max(n, 0))) }
        return String(t.prefix(n - 1)) + "\u{2026}"
    }

    /// "h:mm AM/PM" in the given time zone.
    public static func formatEta(_ epochS: Int, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let parts = cal.dateComponents([.hour, .minute],
                                       from: Date(timeIntervalSince1970: TimeInterval(epochS)))
        let h = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let ampm = h < 12 ? "AM" : "PM"
        var h12 = h % 12
        if h12 == 0 { h12 = 12 }
        let mm = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(h12):\(mm) \(ampm)"
    }
}
