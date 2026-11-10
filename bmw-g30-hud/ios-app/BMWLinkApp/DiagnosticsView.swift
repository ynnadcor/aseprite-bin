// SPDX-License-Identifier: MIT
import SwiftUI
import BMWLinkKit

struct DiagnosticsView: View {
    @StateObject private var vm = DiagnosticsViewModel()
    @State private var useRealCar = false
    /// Typical NBT EVO link-local address seen on the ENET link; confirm on-car.
    @State private var host = "169.254.199.99"

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Toggle("Use real car (ENET)", isOn: $useRealCar)
                    if useRealCar {
                        TextField("Gateway / head-unit IP", text: $host)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Text("Needs the USB-C Ethernet adapter + ENET cable. Read-only.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("Mock gateway — runs with no car.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Button(vm.isBusy ? "Working…" : "Identify (read-only)") {
                        vm.runIdentify(source: useRealCar ? .enet(host: host) : .mock)
                    }
                    .disabled(vm.isBusy)
                }

                Section("Status") { Text(vm.status).font(.callout) }

                if let info = vm.info {
                    Section("Vehicle") {
                        row("VIN", info.vin)
                        row("ECU name", info.ecuName)
                        row("App SW", info.appSoftwareVersion)
                        row("HW number", info.hardwareNumber)
                        row("Supplier SW", info.supplierSoftware)
                        row("Serial", info.serial)
                    }
                }

                if !vm.liveValues.isEmpty {
                    Section("Live values") {
                        ForEach(vm.liveValues) { v in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(v.name).font(.callout)
                                    if !v.verified {
                                        Text("UNVERIFIED — confirm on car")
                                            .font(.caption2).foregroundColor(.orange)
                                    }
                                }
                                Spacer()
                                Text("\(v.value) \(v.unit)")
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundColor(v.verified ? .primary : .orange)
                            }
                        }
                    }
                }

                if !vm.dtcs.isEmpty {
                    Section("Fault codes (read-only)") {
                        ForEach(vm.dtcs, id: \.self) {
                            Text($0).font(.system(.footnote, design: .monospaced))
                        }
                    }
                }

                Section {
                    Text("This app only ever READS. It cannot write, code, clear, or flash — the UDS layer refuses non-read services. See docs/safety.md.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("BMW Link")
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
        }
        .font(.callout)
    }
}

struct DiagnosticsView_Previews: PreviewProvider {
    static var previews: some View { DiagnosticsView() }
}
