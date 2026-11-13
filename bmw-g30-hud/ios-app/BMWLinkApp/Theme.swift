// SPDX-License-Identifier: MIT
// Shared look: dark background, rounded cards, one blue accent. Generic
// styling only - no BMW logos or other trademarks.
import SwiftUI
import BMWLinkKit

enum Theme {
    static let accent = Color(red: 0.11, green: 0.41, blue: 0.83)
    static let background = Color(red: 0.035, green: 0.04, blue: 0.05)
    static let card = Color(red: 0.085, green: 0.095, blue: 0.115)
    static let cardBorder = Color.white.opacity(0.07)
    static let secondary = Color.white.opacity(0.62)
    static let good = Color(red: 0.27, green: 0.82, blue: 0.47)
    static let warn = Color(red: 1.0, green: 0.64, blue: 0.22)
    static let bad = Color(red: 1.0, green: 0.38, blue: 0.38)
}

/// A rounded card with an optional numbered step and title.
struct Card<Content: View>: View {
    var step: String? = nil
    var title: String? = nil
    var systemImage: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || step != nil {
                HStack(spacing: 10) {
                    if let step {
                        Text(step)
                            .font(.caption.weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(Theme.accent, in: Circle())
                            .foregroundColor(.white)
                    } else if let systemImage {
                        Image(systemName: systemImage).foregroundColor(Theme.accent)
                    }
                    if let title {
                        Text(title).font(.headline)
                    }
                    Spacer(minLength: 0)
                }
            }
            content()
            if let footer {
                Text(footer).font(.caption).foregroundColor(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardBorder))
    }
}

/// Filled (prominent) or tinted button; dims when disabled.
struct FilledButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        FilledLabel(configuration: configuration, color: color, prominent: prominent)
    }

    private struct FilledLabel: View {
        let configuration: ButtonStyle.Configuration
        let color: Color
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .foregroundColor(prominent ? .white : color)
                .background((prominent ? color : color.opacity(0.16)).opacity(configuration.isPressed ? 0.7 : 1),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// Small capsule with an icon and text.
struct StatusPill: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Label/value row used for results.
struct ValueRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(Theme.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Launch arguments CI uses to take screenshots of each screen with practice data.
enum ScreenshotMode {
    static let arguments = ProcessInfo.processInfo.arguments

    static func value(_ key: String) -> String? {
        guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static var tab: String? { value("-screenshotTab") }
    static var anchor: String? { value("-screenshotAnchor") }
    static var isOn: Bool { tab != nil }
}

// MARK: - fault codes

extension Theme {
    static func color(_ severity: Severity?) -> Color {
        switch severity {
        case .stop?, .now?: return bad
        case .soon?: return warn
        case .info?: return good
        case nil: return secondary
        }
    }

    static func icon(_ severity: Severity?) -> String {
        switch severity {
        case .stop?: return "exclamationmark.octagon.fill"
        case .now?: return "exclamationmark.triangle.fill"
        case .soon?: return "wrench.and.screwdriver"
        case .info?: return "checkmark.circle"
        case nil: return "questionmark.circle"
        }
    }

    static func color(_ state: CodeState) -> Color {
        switch state {
        case .active: return bad
        case .stored: return warn
        case .pending: return accent
        case .permanent, .earlier, .notTested: return secondary
        }
    }
}

/// "Check now", "Not urgent"... in the severity's color.
struct SeverityBadge: View {
    let severity: Severity?

    var body: some View {
        StatusPill(text: severity?.label ?? "Urgency unknown", systemImage: Theme.icon(severity),
                   color: Theme.color(severity))
    }
}

/// Small capsule for a code's state ("Active now", "Stored"...).
struct StateChip: View {
    let state: CodeState

    var body: some View {
        Text(state.label)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundColor(Theme.color(state))
            .background(Theme.color(state).opacity(0.16), in: Capsule())
    }
}

// MARK: - gauges

extension Theme {
    /// Boost colour: green building, amber at a healthy stage-1 level, red near the top.
    static func boostColor(_ psi: Double) -> Color {
        switch psi {
        case ..<8: return good
        case ..<16: return accent
        case ..<20: return warn
        default: return bad
        }
    }

    /// Temperature colour by warn/hot thresholds; grey when the value is missing.
    /// (Thresholds are named `warnAt`/`hotAt` so they don't shadow the colours.)
    static func tempColor(_ value: Int?, warnAt: Int, hotAt: Int) -> Color {
        guard let v = value else { return secondary }
        if v >= hotAt { return bad }
        if v >= warnAt { return warn }
        return good
    }
}
