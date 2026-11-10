// SPDX-License-Identifier: MIT
import SwiftUI
import BMWLinkKit

/// The guided, read-only car test. See docs/car-test-procedure.md.
struct DiagnosticsView: View {
    @StateObject private var vm = DiagnosticsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Connect to", selection: $vm.mode) {
                        ForEach(DiagnosticsViewModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(vm.mode == .car
                         ? "Parked, ignition on. ENET cable in the OBD port, USB‑C Ethernet adapter in the iPhone."
                         : "Practice the steps with a simulated car. Nothing goes on the network.")
                }

                if vm.mode == .car { cableSection }
                findSection
                identifySection
                if let report = vm.report { resultsSection(report) }
                logSection

                Section {
                    Text("Read-only. This app can't write, code, clear fault codes or flash anything: non-read requests are refused in code before they reach the car.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Car test")
            .overlay(alignment: .bottom) { statusBanner }
        }
    }

    // MARK: 1. cable

    private var cableSection: some View {
        Section {
            if let w = vm.wired {
                Label("\(w.name)  \(w.address)", systemImage: "cable.connector")
                    .foregroundColor(.green)
                if !w.isLinkLocal {
                    Text("This address isn't 169.254.x.x. If the car isn't found, check the adapter is the one with the ENET cable.")
                        .font(.caption).foregroundColor(.orange)
                }
            } else {
                Label("No wired Ethernet yet", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text("Plug in the adapter and ENET cable, switch the ignition on, wait about 10 seconds, then tap Refresh.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Button("Refresh") { vm.refreshInterfaces() }
                .disabled(vm.isBusy)
            DisclosureGroup("All network interfaces (\(vm.interfaces.count))") {
                ForEach(vm.interfaces) { i in
                    Text("\(i.name)  \(i.address)/\(i.netmask)\(i.isUp ? "" : "  (down)")")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        } header: {
            Text("1 · Cable")
        }
    }

    // MARK: 2. find

    private var findSection: some View {
        Section {
            Button("Automatic search") { vm.autoFind() }
                .disabled(vm.isBusy)

            HStack {
                TextField("Gateway IP, e.g. 169.254.12.34", text: $vm.manualHost)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Check") { vm.checkHost() }
                    .disabled(vm.isBusy || vm.manualHost.isEmpty)
            }

            if let p = vm.sweepProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: p)
                    HStack {
                        Text("\(Int(p * 100))% of the cable's addresses checked")
                            .font(.caption)
                        Spacer()
                        Button("Stop", role: .cancel) { vm.cancel() }
                    }
                }
            } else {
                Button("Search the cable (slow, up to ~4 min)") { vm.startSweep() }
                    .disabled(vm.isBusy)
            }

            ForEach(vm.gateways) { g in
                Button {
                    vm.selected = g
                } label: {
                    HStack {
                        Image(systemName: vm.selected == g ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading) {
                            Text("\(g.host)").font(.body.monospacedDigit())
                            Text("\(g.protocolKind.displayName)  ·  VIN \(vm.displayVIN(g.vin))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            if vm.gateways.contains(where: { !$0.vin.isEmpty }) {
                Toggle("Show full VIN on screen", isOn: $vm.revealVIN)
            }
        } header: {
            Text("2 · Find the car")
        } footer: {
            Text("Automatic search needs an Apple entitlement this build may not have; if it's refused, use Check with a known address, or Search the cable. The address that works is remembered.")
        }
    }

    // MARK: 3. identify

    private var identifySection: some View {
        Section {
            if let g = vm.selected {
                Text("\(g.host) · \(g.protocolKind.displayName)")
                    .font(.callout)
            } else {
                Text("Find the car first.").foregroundColor(.secondary)
            }
            if vm.isBusy && vm.sweepProgress == nil && vm.busy?.hasPrefix("Reading") == true {
                Button("Stop after the current request", role: .cancel) { vm.cancel() }
            } else {
                Button("Run read-only identify") { vm.runIdentify() }
                    .disabled(vm.isBusy || vm.selected == nil)
            }
        } header: {
            Text("3 · Read identification")
        } footer: {
            Text("Reads VIN and identification records from the gateway, head unit, cluster and HUD, plus the head unit's fault codes. About 10 read-only requests.")
        }
    }

    // MARK: results

    private func resultsSection(_ r: IdentifyReport) -> some View {
        Section {
            Text(r.summary).font(.callout)
            ForEach(r.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.ecu) · \(item.label)")
                        .font(.caption).foregroundColor(.secondary)
                    Text(outcomeText(item.outcome))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(outcomeColor(item.outcome))
                        .lineLimit(4)
                }
            }
        } header: {
            Text("Results")
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
        case .negative: return .orange
        case .failed: return .red
        case .skipped: return .secondary
        }
    }

    // MARK: log

    private var logSection: some View {
        Section {
            if let url = vm.exportURL {
                ShareLink(item: url) {
                    Label("Share log (VIN hidden)", systemImage: "square.and.arrow.up")
                }
            }
            Button("Copy log") { vm.copyLog() }
            DisclosureGroup("Show log (\(vm.logLines.count) lines)") {
                ForEach(Array(vm.logLines.suffix(80).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Button("Clear log", role: .destructive) { vm.clearLog() }
                .disabled(vm.isBusy)
        } header: {
            Text("Session log")
        } footer: {
            Text("Send this file back after a test. VIN and the car's network MAC are masked.")
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
    static var previews: some View { DiagnosticsView() }
}
