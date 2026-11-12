// SPDX-License-Identifier: MIT
import SwiftUI
import BMWLinkKit

/// The guided, read-only car test (docs/car-test-procedure.md) plus Test 2.
/// Same information as the earlier form, laid out as cards.
struct DiagnosticsView: View {
    @StateObject private var vm = DiagnosticsViewModel()
    @State private var didRunDemo = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        headerCard
                        if vm.mode == .car { cableCard }
                        findCard
                        identifyCard
                        if let report = vm.report { resultsCard(report).id("results") }
                        test2Card.id("test2")
                        logCard.id("log")
                        Text("Read-only. This app can't write, code, clear fault codes or flash anything: non-read requests are refused in code before they reach the car.")
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
                .navigationTitle("Car")
                .overlay(alignment: .bottom) { statusBanner }
                .onAppear {
                    guard ScreenshotMode.tab == "car", !didRunDemo else { return }
                    didRunDemo = true
                    vm.runScreenshotDemo()
                    if let anchor = ScreenshotMode.anchor {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    // MARK: header

    private var headerCard: some View {
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
            Text(vm.mode == .car
                 ? "Parked, ignition on. ENET cable in the OBD port, USB‑C Ethernet adapter in the iPhone."
                 : "Practice the steps with a simulated car. Nothing goes on the network.")
                .font(.caption)
                .foregroundColor(Theme.secondary)
        }
    }

    private var connectionPill: StatusPill {
        if vm.isBusy { return StatusPill(text: "Working…", systemImage: "hourglass", color: Theme.accent) }
        if let r = vm.report, r.answeredCount > 0 {
            return StatusPill(text: "Car read", systemImage: "checkmark.circle.fill", color: Theme.good)
        }
        if let g = vm.selected { return StatusPill(text: "Car at \(g.host)", systemImage: "car.fill", color: Theme.good) }
        if vm.mode == .car && vm.wired == nil {
            return StatusPill(text: "No cable", systemImage: "cable.connector", color: Theme.warn)
        }
        return StatusPill(text: "Not connected", systemImage: "circle.dashed", color: Theme.secondary)
    }

    // MARK: 1. cable

    private var cableCard: some View {
        Card(step: "1", title: "Cable") {
            if let w = vm.wired {
                Label("\(w.name)  \(w.address)", systemImage: "cable.connector")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Theme.good)
                if !w.isLinkLocal {
                    Text("This address isn't 169.254.x.x. If the car isn't found, check the adapter is the one with the ENET cable.")
                        .font(.caption)
                        .foregroundColor(Theme.warn)
                }
            } else {
                Label("No wired Ethernet yet", systemImage: "exclamationmark.triangle")
                    .foregroundColor(Theme.warn)
                Text("Plug in the adapter and ENET cable, switch the ignition on, wait about 10 seconds, then tap Refresh.")
                    .font(.caption)
                    .foregroundColor(Theme.secondary)
            }
            Button("Refresh") { vm.refreshInterfaces() }
                .buttonStyle(FilledButtonStyle(prominent: false))
                .disabled(vm.isBusy)
            DisclosureGroup("All network interfaces (\(vm.interfaces.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(vm.interfaces) { i in
                        Text("\(i.name)  \(i.address)/\(i.netmask)\(i.isUp ? "" : "  (down)")")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.subheadline)
            .tint(Theme.secondary)
        }
    }

    // MARK: 2. find

    private var findCard: some View {
        Card(step: "2", title: "Find the car",
             footer: "Automatic search needs an Apple entitlement this build may not have; if it's refused, use Check with a known address, or Search the cable. The address that works is remembered.") {
            Button("Automatic search") { vm.autoFind() }
                .buttonStyle(FilledButtonStyle())
                .disabled(vm.isBusy)

            HStack(spacing: 8) {
                TextField("Gateway IP, e.g. 169.254.12.34", text: $vm.manualHost)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.callout, design: .monospaced))
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Button("Check") { vm.checkHost() }
                    .buttonStyle(FilledButtonStyle(prominent: false))
                    .frame(width: 92)
                    .disabled(vm.isBusy || vm.manualHost.isEmpty)
            }

            if let p = vm.sweepProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: p).tint(Theme.accent)
                    HStack {
                        Text("\(Int(p * 100))% of the cable's addresses checked").font(.caption)
                        Spacer()
                        Button("Stop", role: .cancel) { vm.cancel() }
                            .font(.caption.weight(.semibold))
                    }
                }
            } else {
                Button("Search the cable (slow, up to ~4 min)") { vm.startSweep() }
                    .buttonStyle(FilledButtonStyle(prominent: false))
                    .disabled(vm.isBusy)
            }

            ForEach(vm.gateways) { g in
                Button { vm.selected = g } label: {
                    HStack(spacing: 10) {
                        Image(systemName: vm.selected == g ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(vm.selected == g ? Theme.accent : Theme.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.host).font(.body.monospacedDigit()).foregroundColor(.primary)
                            Text("\(g.protocolKind.displayName)  ·  VIN \(vm.displayVIN(g.vin))")
                                .font(.caption)
                                .foregroundColor(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color.white.opacity(vm.selected == g ? 0.08 : 0.03),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if vm.gateways.contains(where: { !$0.vin.isEmpty }) {
                Toggle("Show full VIN on screen", isOn: $vm.revealVIN)
            }
        }
    }

    // MARK: 3. identify

    private var identifyCard: some View {
        Card(step: "3", title: "Read identification",
             footer: "Reads VIN and identification records from the gateway, head unit, cluster and HUD, plus the head unit's fault codes. About 10 read-only requests.") {
            if let g = vm.selected {
                Text("\(g.host) · \(g.protocolKind.displayName)").font(.callout.monospacedDigit())
            } else {
                Text("Find the car first.").foregroundColor(Theme.secondary)
            }
            if vm.busy?.hasPrefix("Reading identification") == true {
                Button("Stop after the current request", role: .cancel) { vm.cancel() }
                    .buttonStyle(FilledButtonStyle(color: Theme.bad, prominent: false))
            } else {
                Button("Run read-only identify") { vm.runIdentify() }
                    .buttonStyle(FilledButtonStyle())
                    .disabled(vm.isBusy || vm.selected == nil)
            }
        }
    }

    // MARK: results

    private struct ECUGroup {
        let name: String
        let address: UInt16
        var items: [IdentifyItem]
    }

    private func groups(_ items: [IdentifyItem]) -> [ECUGroup] {
        var out: [ECUGroup] = []
        for item in items {
            if let last = out.last, last.name == item.ecu {
                out[out.count - 1].items.append(item)
            } else {
                out.append(ECUGroup(name: item.ecu, address: item.address, items: [item]))
            }
        }
        return out
    }

    private func counts(_ r: IdentifyReport) -> (declined: Int, failed: Int) {
        var declined = 0, failed = 0
        for item in r.items {
            switch item.outcome {
            case .negative: declined += 1
            case .failed: failed += 1
            default: break
            }
        }
        return (declined, failed)
    }

    private func resultsCard(_ r: IdentifyReport) -> some View {
        let c = counts(r)
        return Card(title: "Results", systemImage: "list.bullet.rectangle") {
            HStack(spacing: 6) {
                StatusPill(text: "\(r.answeredCount) answered", systemImage: "checkmark", color: Theme.good)
                StatusPill(text: "\(c.declined) declined", systemImage: "minus.circle", color: Theme.warn)
                StatusPill(text: "\(c.failed) no answer", systemImage: "xmark", color: Theme.bad)
            }
            ForEach(groups(r.items), id: \.name) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(group.name) · \(String(format: "0x%02X", group.address))")
                        .font(.subheadline.weight(.semibold))
                    ForEach(group.items) { item in
                        ValueRow(label: item.label, value: outcomeText(item.outcome), color: outcomeColor(item.outcome))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func outcomeText(_ o: IdentifyItem.Outcome) -> String {
        switch o {
        case .value(let v): return v.contains("WBA") && v.count == 17 ? vm.displayVIN(v) : v
        case .negative(let s): return "ECU declined: \(s)"
        case .failed(let s): return "No answer: \(s)"
        case .skipped(let s): return "Skipped: \(s)"
        }
    }

    private func outcomeColor(_ o: IdentifyItem.Outcome) -> Color {
        switch o {
        case .value: return .primary
        case .negative: return Theme.warn
        case .failed: return Theme.bad
        case .skipped: return Theme.secondary
        }
    }

    // MARK: Test 2

    private var test2Card: some View {
        Card(title: "Test 2 · Modules and engine", systemImage: "cpu",
             footer: "Both only read. Find every module sends one request that all modules answer, the same one BMW tools send first. Engine values reads standard OBD values from the DME; with the engine idling (parked, in P) they're live. Your MHD tune is not touched.") {
            HStack(spacing: 10) {
                Button("Find every module") { vm.scanModules() }
                    .buttonStyle(FilledButtonStyle(prominent: false))
                    .disabled(vm.isBusy || vm.selected == nil)
                Button("Read engine values") { vm.readEngineValues() }
                    .buttonStyle(FilledButtonStyle(prominent: false))
                    .disabled(vm.isBusy || vm.selected == nil)
            }
            if !vm.modules.isEmpty {
                Text("\(vm.modules.count) modules answered").font(.subheadline.weight(.semibold))
                ForEach(vm.modules) { m in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(format: "0x%02X", m.address))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).font(.footnote).foregroundColor(m.isKnown ? .primary : Theme.warn)
                            Text(m.outcome == .answered ? m.detail : "\(m.outcome.rawValue): \(m.detail)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(Theme.secondary)
                        }
                    }
                }
                if let hint = vm.hudHint {
                    Text(hint).font(.caption).foregroundColor(Theme.secondary)
                }
            }
            if let e = vm.engineReport {
                Text("Engine computer (DME)").font(.subheadline.weight(.semibold))
                ForEach(e.items) { item in
                    ValueRow(label: item.label, value: outcomeText(item.outcome), color: outcomeColor(item.outcome))
                }
                if let b = vm.boost {
                    ValueRow(label: "Boost (manifold minus outside air)", value: b, color: Theme.good)
                }
                Text(e.summary).font(.caption).foregroundColor(Theme.secondary)
            }
        }
    }

    // MARK: log

    private var logCard: some View {
        Card(title: "Session log", systemImage: "doc.text",
             footer: "Send this file back after a test. The VIN, the car's network MAC and ECU serial numbers are masked.") {
            HStack(spacing: 10) {
                if let url = vm.exportURL {
                    ShareLink(item: url) {
                        Label("Share log (VIN hidden)", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(FilledButtonStyle())
                }
                Button { vm.copyLog() } label: {
                    Label("Copy log", systemImage: "doc.on.doc")
                }
                .buttonStyle(FilledButtonStyle(prominent: false))
            }
            DisclosureGroup("Show log (\(vm.logLines.count) lines)") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(vm.logLines.suffix(80).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.subheadline)
            .tint(Theme.secondary)
            Button("Clear log", role: .destructive) { vm.clearLog() }
                .buttonStyle(FilledButtonStyle(color: Theme.bad, prominent: false))
                .disabled(vm.isBusy)
        }
    }

    // MARK: status

    @ViewBuilder
    private var statusBanner: some View {
        if let busy = vm.busy {
            HStack(spacing: 10) {
                ProgressView()
                Text(busy).font(.footnote)
            }
            .padding(12)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 8)
        } else if !vm.message.isEmpty {
            Text(vm.message)
                .font(.footnote)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }
}

struct DiagnosticsView_Previews: PreviewProvider {
    static var previews: some View { DiagnosticsView().preferredColorScheme(.dark) }
}
