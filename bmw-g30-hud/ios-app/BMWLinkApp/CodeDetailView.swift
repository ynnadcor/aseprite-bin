// SPDX-License-Identifier: MIT
// One fault code: what it means, whether to keep driving, likely causes, what
// to check first, what it leads to if ignored, how it combines with the other
// codes in the scan, its exact status, a web search and the owner's notes.
import SwiftUI
import BMWLinkKit

struct CodeDetailView: View {
    let route: CodeRoute
    let scan: CodeScan?
    @State private var note = ""
    @Environment(\.openURL) private var openURL

    private var found: FoundCode? {
        if case .found(let c) = route { return c }
        return nil
    }

    private var explanation: CodeExplanation {
        switch route {
        case .found(let c): return c.explanation
        case .typed(let text): return CodeExplainer.explain(text)
        }
    }

    private var related: [CodeFinding] {
        guard let c = found, let scan else { return [] }
        return CodePatterns.related(to: c, in: scan.findings)
    }

    var body: some View {
        let e = explanation
        ScrollView {
            VStack(spacing: 14) {
                header(e)
                if e.kind == .invalid {
                    Card { Text(e.meaning).font(.callout) }
                } else {
                    Card(title: "What it means", systemImage: "text.book.closed") {
                        Text(e.meaning)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(e.source).font(.caption).foregroundColor(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Card(title: "Can I keep driving?", systemImage: "car") {
                        Label(e.drive, systemImage: Theme.icon(e.severity))
                            .font(.callout)
                            .foregroundColor(e.severity == nil ? Color.primary : Theme.color(e.severity))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !e.causes.isEmpty {
                        Card(title: "Most likely causes", systemImage: "list.number",
                             footer: "Most likely first.") { numbered(e.causes) }
                    }
                    if !e.checks.isEmpty {
                        Card(title: "What to check first", systemImage: "checklist",
                             footer: "Cheapest and quickest checks first, before buying parts.") { numbered(e.checks) }
                    }
                    if let ignored = e.ignored {
                        Card(title: "If you leave it", systemImage: "exclamationmark.triangle") {
                            Text(ignored).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !related.isEmpty {
                        Card(title: "Together with the other codes", systemImage: "lightbulb") {
                            ForEach(related) { FindingRow(finding: $0, scan: scan, current: found) }
                        }
                    }
                    if let c = found { statusCard(c) }
                    lookItUpCard(e)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(e.code)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { note = CodeNotes.load(e.code) }
    }

    // MARK: pieces

    private func header(_ e: CodeExplanation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(e.code)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                SeverityBadge(severity: e.severity)
            }
            Text(e.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !e.system.isEmpty {
                Label(e.system, systemImage: "gearshape.2")
                    .font(.subheadline)
                    .foregroundColor(Theme.secondary)
            }
            if let c = found {
                HStack(spacing: 6) {
                    ForEach(c.states, id: \.self) { StateChip(state: $0) }
                    if c.warningLight {
                        StatusPill(text: "Warning light", systemImage: "exclamationmark.triangle.fill", color: Theme.warn)
                    }
                }
                Text(BMWModules.describe(c.module).name + String(format: " (0x%02X) · ", c.module) + c.source.rawValue)
                    .font(.caption)
                    .foregroundColor(Theme.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.color(e.severity).opacity(0.5)))
    }

    private func numbered(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: 20, height: 20)
                        .background(Theme.accent.opacity(0.2), in: Circle())
                        .foregroundColor(Theme.accent)
                    Text(item)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func statusCard(_ c: FoundCode) -> some View {
        Card(title: "Status", systemImage: "info.circle") {
            ForEach(c.states, id: \.self) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.label).font(.subheadline.weight(.semibold)).foregroundColor(Theme.color(s))
                    Text(s.explanation).font(.caption).foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let status = c.status {
                DisclosureGroup(String(format: "Status byte 0x%02X, bit by bit", status)) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<CodeState.statusBits.count, id: \.self) { i in
                            let bit = CodeState.statusBits[i]
                            Label(bit.meaning, systemImage: status & bit.bit != 0 ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundColor(status & bit.bit != 0 ? Color.primary : Theme.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .font(.subheadline)
                .tint(Theme.secondary)
            } else {
                Text("From the engine computer's standard OBD-II code lists (stored, pending and permanent).")
                    .font(.caption)
                    .foregroundColor(Theme.secondary)
            }
        }
    }

    private func lookItUpCard(_ e: CodeExplanation) -> some View {
        Card(title: "Look it up", systemImage: "magnifyingglass",
             footer: "Notes stay on this phone. Tip: write down what fixed it.") {
            Button {
                if let url = searchURL(e.searchQuery) { openURL(url) }
            } label: {
                Label("Search the web for \(e.code)", systemImage: "safari")
            }
            .buttonStyle(FilledButtonStyle(prominent: false))
            Text("Your notes").font(.caption).foregroundColor(Theme.secondary)
            TextEditor(text: $note)
                .font(.callout)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: note) { CodeNotes.save($0, for: e.code) }
        }
    }

    private func searchURL(_ query: String) -> URL? {
        var parts = URLComponents(string: "https://www.google.com/search")
        parts?.queryItems = [URLQueryItem(name: "q", value: query)]
        return parts?.url
    }
}

/// The owner's notes per code, kept on the phone.
enum CodeNotes {
    private static func key(_ code: String) -> String { "bmwlink.note." + code.uppercased() }

    static func load(_ code: String) -> String { UserDefaults.standard.string(forKey: key(code)) ?? "" }

    static func save(_ text: String, for code: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.removeObject(forKey: key(code))
        } else {
            UserDefaults.standard.set(text, forKey: key(code))
        }
    }
}
