// SPDX-License-Identifier: MIT
// Renders one HudFrame the way the factory HUD/cluster would: an amber
// pictogram, a distance, a countdown bar and a short label on black.
// The arrow art is SF Symbols, not BMW's own glyphs - a legible stand-in.
import SwiftUI
import NavHUDKit

enum HudStyle {
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.0)
}

enum HudSymbols {
    /// SF Symbol name plus a rotation (degrees) used to fake the in-between angles.
    static func symbol(for m: Maneuver) -> (name: String, rotation: Double) {
        switch m {
        case .continue: return ("arrow.up", 0)
        case .turnLeft: return ("arrow.turn.up.left", 0)
        case .turnRight: return ("arrow.turn.up.right", 0)
        case .slightLeft: return ("arrow.up", -40)
        case .slightRight: return ("arrow.up", 40)
        case .sharpLeft: return ("arrow.up", -135)
        case .sharpRight: return ("arrow.up", 135)
        case .uturn: return ("arrow.uturn.down", 0)
        case .keepLeft: return ("arrow.up.left", 0)
        case .keepRight: return ("arrow.up.right", 0)
        case .merge: return ("arrow.triangle.merge", 0)
        case .roundabout: return ("arrow.triangle.turn.up.right.circle", 0)
        case .exitLeft: return ("arrow.up.left", 0)
        case .exitRight: return ("arrow.up.right", 0)
        case .ferry: return ("ferry", 0)
        case .destination: return ("mappin.and.ellipse", 0)
        }
    }

    static func lane(_ hint: String) -> String {
        switch hint {
        case "l": return "arrow.turn.up.left"
        case "r": return "arrow.turn.up.right"
        default: return "arrow.up"
        }
    }
}

struct HudView: View {
    let frame: HudFrame?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
            if let f = frame, f.visible {
                content(f)
                    .foregroundColor(HudStyle.amber)
                    .padding(18)
            } else {
                Text(frame == nil ? "No route loaded" : "HUD off")
                    .font(.headline)
                    .foregroundColor(HudStyle.amber.opacity(0.35))
            }
        }
        .frame(height: 220)
        .shadow(color: HudStyle.amber.opacity(0.18), radius: 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(_ f: HudFrame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                let sym = HudSymbols.symbol(for: f.arrow)
                Image(systemName: sym.name)
                    .font(.system(size: 60, weight: .bold))
                    .rotationEffect(.degrees(sym.rotation))
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.distanceText)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    if let exit = f.roundaboutExit {
                        Text("exit \(exit)").font(.headline)
                    }
                }
                Spacer(minLength: 0)
            }
            if !f.distanceText.isEmpty && f.distanceText != "now" {
                CountdownBar(fraction: f.distanceFraction)
            }
            HStack {
                Text(f.label)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !f.etaText.isEmpty {
                    Text("ETA \(f.etaText)").font(.subheadline)
                }
            }
            if !f.lanes.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(f.lanes.enumerated()), id: \.offset) { _, hint in
                        Image(systemName: HudSymbols.lane(hint)).font(.callout)
                    }
                }
            }
            if !f.banner.isEmpty {
                Text(f.banner.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(2)
            }
        }
    }
}

struct CountdownBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(HudStyle.amber.opacity(0.25))
                Capsule().fill(HudStyle.amber)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
            }
        }
        .frame(height: 8)
    }
}

struct HudView_Previews: PreviewProvider {
    static var previews: some View {
        HudView(frame: HudFrame(profileName: "G30-HUD", arrow: .turnRight,
                                distanceText: "500 ft", distanceFraction: 0.15,
                                label: "Elm St"))
            .padding()
    }
}
