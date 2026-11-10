// SPDX-License-Identifier: MIT
// Classifies a route step into a Maneuver.
//
// Why this exists: Apple's MapKit `MKRoute.Step` exposes only a *localized
// instruction string*, a distance and a polyline. There is no maneuver-type
// field. (CarPlay's CPManeuver does carry a type, but only inside a CarPlay
// navigation app, which needs Apple's entitlement.) So we combine:
//   1. English text rules (MapKit's wording for en-US devices), and
//   2. the turn angle measured from the step polylines, which works in any
//      language and is the fallback when no text rule matches.
// Text wins when it matches, because it carries intent the geometry can't
// (roundabout exit numbers, exits vs. bends, arrival).
import Foundation

public struct ClassifiedManeuver: Equatable, Sendable {
    public enum Basis: String, Sendable {
        case text       // an instruction-text rule matched
        case geometry   // classified from the turn angle
        case none       // nothing to go on; defaulted
    }

    public var maneuver: Maneuver
    /// Road being turned onto / continued on ("" if unknown).
    public var roadName: String
    /// Signpost destination for exits ("toward X").
    public var exitName: String
    /// e.g. "215B".
    public var exitNumber: String
    public var roundaboutExit: Int?
    public var basis: Basis

    public init(maneuver: Maneuver, roadName: String = "", exitName: String = "",
                exitNumber: String = "", roundaboutExit: Int? = nil, basis: Basis) {
        self.maneuver = maneuver
        self.roadName = roadName
        self.exitName = exitName
        self.exitNumber = exitNumber
        self.roundaboutExit = roundaboutExit
        self.basis = basis
    }
}

public enum ManeuverClassifier {

    public static func classify(instruction: String, turnAngle: Double?,
                                side: Side = .right) -> ClassifiedManeuver {
        let s = " " + instruction.lowercased() + " "
        func has(_ phrase: String) -> Bool { s.contains(phrase) }
        /// Whole-word match, so "Leftwich" does not count as "left".
        func hasWord(_ word: String) -> Bool {
            capture(#"\b("# + NSRegularExpression.escapedPattern(for: word) + #")\b"#,
                    in: instruction) != nil
        }

        let road = roadName(in: instruction)
        let toward = capture(#"\btowards?\s+(.+?)\s*$"#, in: instruction).map(cleanName) ?? ""

        func result(_ m: Maneuver, roundabout: Int? = nil, exitName: String = "",
                    exitNumber: String = "") -> ClassifiedManeuver {
            ClassifiedManeuver(maneuver: m, roadName: road, exitName: exitName,
                               exitNumber: exitNumber, roundaboutExit: roundabout, basis: .text)
        }

        if has("arrive") || has("your destination") || has("the destination")
            || has("destination is") || has("destination will be") {
            // "The destination is on your right" / "Arrive at ..." - no road to name.
            var r = result(.destination)
            r.roadName = ""
            return r
        }
        if has("roundabout") || has("traffic circle") || has("rotary") {
            return result(.roundabout, roundabout: roundaboutExit(in: instruction))
        }
        if has("u-turn") || has("u turn") || has(" uturn") {
            return result(.uturn)
        }
        if has("ferry") {
            return result(.ferry)
        }
        if has("merge") {
            return result(.merge)
        }
        if hasWord("exit") || hasWord("ramp") || has("off-ramp") {
            let m: Maneuver
            if hasWord("left") {
                m = .exitLeft
            } else if hasWord("right") {
                m = .exitRight
            } else if let a = turnAngle {
                m = a < 0 ? .exitLeft : .exitRight
            } else {
                m = side == .left ? .exitLeft : .exitRight
            }
            return result(m, exitName: toward.isEmpty ? road : toward,
                          exitNumber: exitNumber(in: instruction))
        }
        if has("keep left") || has("stay left") { return result(.keepLeft) }
        if has("keep right") || has("stay right") { return result(.keepRight) }
        if has("sharp left") { return result(.sharpLeft) }
        if has("sharp right") { return result(.sharpRight) }
        if has("slight left") || has("bear left") { return result(.slightLeft) }
        if has("slight right") || has("bear right") { return result(.slightRight) }
        if has("turn left") || has("make a left") || has("left turn") { return result(.turnLeft) }
        if has("turn right") || has("make a right") || has("right turn") { return result(.turnRight) }
        if has("continue") || has("go straight") || has(" head ") || has("proceed")
            || has("straight") || has("start ") {
            return result(.continue)
        }

        // No English rule matched (e.g. a non-English device): use geometry.
        if let a = turnAngle {
            return ClassifiedManeuver(maneuver: maneuver(forTurnAngle: a), roadName: road,
                                      basis: .geometry)
        }
        return ClassifiedManeuver(maneuver: .continue, roadName: road, basis: .none)
    }

    /// Maneuver for a signed turn angle (positive = right).
    public static func maneuver(forTurnAngle a: Double) -> Maneuver {
        let mag = abs(a)
        let right = a > 0
        if mag < 15 { return .continue }
        if mag < 45 { return right ? .slightRight : .slightLeft }
        if mag < 135 { return right ? .turnRight : .turnLeft }
        if mag < 170 { return right ? .sharpRight : .sharpLeft }
        return .uturn
    }

    // MARK: - text extraction

    /// "Turn right onto E Main St toward Downtown" -> "E Main St".
    public static func roadName(in instruction: String) -> String {
        let patterns = [
            #"\bonto\s+(.+?)(?:\s+towards?\s+.*)?\s*$"#,
            #"\bon\s+(.+?)(?:\s+towards?\s+.*)?\s*$"#,
            #"\btowards?\s+(.+?)\s*$"#,
        ]
        for p in patterns {
            if let raw = capture(p, in: instruction) {
                let name = cleanName(raw)
                if !name.isEmpty { return name }
            }
        }
        return ""
    }

    /// "Take exit 215B toward Jefferson Ave" -> "215B".
    public static func exitNumber(in instruction: String) -> String {
        capture(#"\bexit\s+([0-9]+[a-zA-Z]?)\b"#, in: instruction)?.uppercased() ?? ""
    }

    /// "At the roundabout, take the 2nd exit" -> 2 (also "second exit").
    public static func roundaboutExit(in instruction: String) -> Int? {
        if let n = capture(#"\b([0-9]+)(?:st|nd|rd|th)\s+exit"#, in: instruction), let v = Int(n) {
            return v
        }
        let words = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
                     "sixth": 6, "seventh": 7, "eighth": 8]
        if let w = capture(#"\b(first|second|third|fourth|fifth|sixth|seventh|eighth)\s+exit"#,
                           in: instruction) {
            return words[w.lowercased()]
        }
        return nil
    }

    /// Strip punctuation and drop phrases that aren't road names.
    static func cleanName(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,;:")))
        let lower = name.lowercased()
        let junk: Set<String> = ["the route", "route", "the left", "the right", "left", "right"]
        if junk.contains(lower) || lower.hasPrefix("your ") { return "" }
        return name
    }

    static func capture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
