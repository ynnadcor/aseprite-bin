// SPDX-License-Identifier: MIT
// Codes tab: scan the whole car for fault codes (read-only), see what they
// point to together, and tap a code for its meaning, causes and checks.
// "Look up a code" works without the car.
import SwiftUI
import BMWLinkKit

enum CodeRoute: Hashable {
    case found(FoundCode)
    case typed(String)
}

struct CodesView: View {
    @ObservedObject var vm: DiagnosticsViewModel
    @State private var path: [CodeRoute] = []
    @State private var typed = ""
    @State private var didRunDemo = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        scanCard
                        if let scan = vm.codeScan {
                            summaryCard(scan)
                            if !scan.findings.isEmpty { findingsCard(scan).id("findings") }
                            moduleCards(scan).id("modules")
                        }
                        lookupCard.id("lookup")
                        Text("Read-only: BMW Link reads codes but can't clear them or change anything in the car. Explanations are general guidance, not a diagnosis; have safety-related faults checked by a workshop.")
                            .font(.caption)
                            .foregroundColor(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 70)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Codes")
                .navigationDestination(for: CodeRoute.self) { route in
                    CodeDetailView(route: route, scan: vm.codeScan)
                }
                .overlay(alignment: .bottom) { banner }
                .onAppear { runScreenshotDemo(proxy) }
            }
        }
    }

    // MARK: scan

    private var scanCard: some View {
        Card {
            HStack {
                connectionPill
                Spacer()
                StatusPill(text: "Read-only", systemImage: "lock.shield", color: Theme.good)
            }
            Picker("Connect to", selection: $vm.mode) {
                ForEach(DiagnosticsViewModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if vm.mode == .car && vm.selected == nil {
                Label("Find the car first: Car tab, steps 1 and 2. The address is remembered after that.",
                      systemImage: "arrow.left.circle")
                    .font(.caption)
                    .foregroundColor(Theme.warn)
            }
            if vm.isBusy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(vm.codeProgress ?? vm.busy ?? "Working…").font(.footnote)
                    Spacer(minLength: 0)
                }
                Button("Stop after this module", role: .cancel) { vm.cancel() }
                    .buttonStyle(FilledButtonStyle(color: Theme.bad, prominent: false))
            } else {
                Button { vm.scanCodes() } label: {
                    Label(vm.codeScan == nil ? "Scan all modules" : "Scan again", systemImage: "stethoscope")
                }
                .buttonStyle(FilledButtonStyle())
                .disabled(!vm.canScanCodes)
            }
            Text(vm.mode == .car
                 ? "Parked, ignition on, ENET cable connected. Reads every module's fault memory and the engine's standard OBD-II codes, about a minute. Nothing is cleared or changed."
                 : "Practice with a simulated car that has a few made-up faults. Nothing goes on the network.")
                .font(.caption)
                .foregroundColor(Theme.secondary)
        }
    }

    private var connectionPill: StatusPill {
        if vm.isBusy { return StatusPill(text: "Scanning…", systemImage: "hourglass", color: Theme.accent) }
        if vm.mode == .practice { return StatusPill(text: "Simulated car", systemImage: "car", color: Theme.accent) }
        if let g = vm.selected { return StatusPill(text: "Car at \(g.host)", systemImage: "car.fill", color: Theme.good) }
        return StatusPill(text: "Not connected", systemImage: "circle.dashed", color: Theme.secondary)
    }

    // MARK: results

    private func summaryCard(_ scan: CodeScan) -> some View {
        let attention = scan.faults.filter { ($0.explanation.severity ?? .soon) >= .soon }.count
        return Card(title: "Scan results", systemImage: "list.bullet.rectangle") {
            HStack(spacing: 6) {
                StatusPill(text: "\(attention) need attention", systemImage: "exclamationmark.circle",
                           color: attention > 0 ? Theme.warn : Theme.good)
                StatusPill(text: "\(scan.faults.count) codes", systemImage: "number", color: Theme.accent)
                StatusPill(text: "\(scan.answeredModules) modules", systemImage: "cpu", color: Theme.secondary)
            }
            if let e = scan.engine {
                ValueRow(label: "Engine light (OBD-II)",
                         value: e.engineLightOn ? "ON · \(e.storedCodeCount) emission code(s)" : "Off",
                         color: e.engineLightOn ? Theme.warn : Theme.good)
                ValueRow(label: "Inspection readiness",
                         value: e.notReady.isEmpty ? "All \(e.monitors.count) monitors ready"
                             : "Not ready: " + e.notReady.joined(separator: ", "),
                         color: e.notReady.isEmpty ? Theme.good : Theme.warn)
                if !e.notReady.isEmpty {
                    Text("Monitors read 'not ready' for a few drives after codes are cleared or the battery is disconnected. An emissions inspection may not pass until they're ready.")
                        .font(.caption)
                        .foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let note = scan.obdNote {
                Text(note).font(.caption).foregroundColor(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if scan.connectionLost {
                Label("The connection dropped during the scan, so some modules weren't read.",
                      systemImage: "bolt.horizontal.circle")
                    .font(.caption)
                    .foregroundColor(Theme.bad)
            }
            if scan.cancelled {
                Text("Stopped early: not every module was read.").font(.caption).foregroundColor(Theme.warn)
            }
            if scan.hiddenEntries > 0 {
                Text("\(scan.hiddenEntries) entries only say \u{201C}not tested yet\u{201D}. That's normal, so they're hidden.")
                    .font(.caption)
                    .foregroundColor(Theme.secondary)
            }
        }
    }

    private func findingsCard(_ scan: CodeScan) -> some View {
        Card(title: "What the codes point to", systemImage: "lightbulb",
             footer: "Codes are read together: shared causes, what to fix first and what happens if ignored.") {
            ForEach(scan.findings) { f in
                FindingRow(finding: f, scan: scan)
            }
        }
    }

    private func moduleCards(_ scan: CodeScan) -> some View {
        let withCodes = scan.modules.filter { !$0.codes.isEmpty }.sorted { a, b in
            let sa = worst(a), sb = worst(b)
            return sa != sb ? sa > sb : a.address < b.address
        }
        let clean = scan.modules.filter { $0.codes.isEmpty && $0.answered && $0.note == nil }
        let silent = scan.modules.filter { $0.codes.isEmpty && $0.note != nil }
        return VStack(spacing: 14) {
            ForEach(withCodes) { m in
                Card(title: m.info.name, systemImage: icon(m.info.kind),
                     footer: m.info.kind == .unknown ? nil : "Handles " + m.info.role) {
                    ForEach(m.codes) { c in
                        NavigationLink(value: CodeRoute.found(c)) { CodeRow(code: c) }
                            .buttonStyle(.plain)
                    }
                    if m.notTested > 0 {
                        Text("+ \(m.notTested) \u{201C}not tested yet\u{201D} entries (normal, hidden)")
                            .font(.caption)
                            .foregroundColor(Theme.secondary)
                    }
                }
            }
            if !clean.isEmpty {
                Card(title: "No faults", systemImage: "checkmark.seal") {
                    ForEach(clean) { m in
                        Label(m.info.name + (m.notTested > 0 ? "  (\(m.notTested) not tested yet)" : ""),
                              systemImage: "checkmark")
                            .font(.footnote)
                            .foregroundColor(Theme.good)
                    }
                }
            }
            if !silent.isEmpty {
                Card(title: "Couldn't read", systemImage: "questionmark.circle") {
                    ForEach(silent) { m in
                        ValueRow(label: m.info.name, value: m.note ?? "", color: Theme.secondary)
                    }
                }
            }
        }
    }

    private func worst(_ m: CodeScan.Module) -> Severity {
        m.codes.compactMap { $0.explanation.severity }.max() ?? .info
    }

    private func icon(_ kind: ModuleInfo.Kind) -> String {
        switch kind {
        case .safety: return "shield.lefthalf.filled"
        case .drivetrain: return "gearshape.2"
        case .network: return "point.3.connected.trianglepath.dotted"
        case .body: return "car.side"
        case .cluster: return "gauge"
        case .infotainment: return "display"
        case .unknown: return "cpu"
        }
    }

    // MARK: look up

    private var lookupCard: some View {
        Card(title: "Look up a code", systemImage: "magnifyingglass",
             footer: "Works without the car: type a code from any scanner, MHD or BimmerLink.") {
            HStack(spacing: 8) {
                TextField("P0171 or 4B1C00", text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(explainTyped)
                    .font(.system(.callout, design: .monospaced))
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Button("Explain", action: explainTyped)
                    .buttonStyle(FilledButtonStyle(prominent: false))
                    .frame(width: 100)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func explainTyped() {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        path.append(.typed(text))
    }

    // MARK: status and screenshots

    @ViewBuilder
    private var banner: some View {
        if !vm.isBusy && !vm.message.isEmpty {
            Text(vm.message)
                .font(.footnote)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    /// CI: `-screenshotTab codes` scans the simulated car; `-screenshotCode P0302`
    /// then opens that code; `-screenshotAnchor modules` scrolls.
    private func runScreenshotDemo(_ proxy: ScrollViewProxy) {
        guard ScreenshotMode.tab == "codes", !didRunDemo else { return }
        didRunDemo = true
        vm.runCodesScreenshotDemo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if let wanted = ScreenshotMode.value("-screenshotCode") {
                if let c = vm.codeScan?.faults.first(where: { $0.code == wanted }) {
                    path.append(.found(c))
                } else {
                    path.append(.typed(wanted))
                }
            } else if let anchor = ScreenshotMode.anchor {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }
}

/// One code in a list.
struct CodeRow: View {
    let code: FoundCode

    var body: some View {
        let e = code.explanation
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.color(e.severity))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(code.code)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(.primary)
                    ForEach(code.states, id: \.self) { StateChip(state: $0) }
                    if code.warningLight {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(Theme.warn)
                    }
                }
                Text(e.kind == .bmw ? "BMW code: description not public" : e.title)
                    .font(.footnote)
                    .foregroundColor(Theme.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// One "what the codes point to" finding, with its codes as links.
struct FindingRow: View {
    let finding: CodeFinding
    let scan: CodeScan?
    var current: FoundCode? = nil

    private var involved: [FoundCode] {
        finding.codeIDs.compactMap { id in scan?.faults.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Theme.icon(finding.severity))
                    .foregroundColor(Theme.color(finding.severity))
                Text(finding.title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            Text(finding.detail)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if !finding.checkFirst.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(finding.checkFirst, id: \.self) { step in
                        Label(step, systemImage: "arrow.right.circle")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let leads = finding.leadsTo {
                Label("If ignored: " + leads, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(involved) { c in
                        if c.id == current?.id {
                            chip(c.code, highlighted: true)
                        } else {
                            NavigationLink(value: CodeRoute.found(c)) { chip(c.code, highlighted: false) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chip(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundColor(highlighted ? .white : Theme.accent)
            .background(highlighted ? Theme.accent : Theme.accent.opacity(0.16), in: Capsule())
    }
}
