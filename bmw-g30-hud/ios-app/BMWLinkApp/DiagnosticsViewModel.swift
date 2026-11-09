// SPDX-License-Identifier: MIT
import Foundation
import BMWLinkKit

/// Where the read-only session connects.
///  - `.mock` (default): the in-memory gateway; runs anywhere, no car.
///  - `.enet(host:)`: the real DoIP transport over the USB-C Ethernet + ENET cable.
enum DiagSource: Equatable {
    case mock
    case enet(host: String)
}

/// One row in the live-values panel. Top-level (not nested in the @MainActor
/// view model) so it can be built off the main actor.
struct LiveValue: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let unit: String
    let verified: Bool
    let note: String
}

/// Drives the read-only "Identify / Diagnostics" flow.
@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published var status: String = "Idle"
    @Published var info: VehicleInfo?
    @Published var dtcs: [String] = []
    @Published var liveValues: [LiveValue] = []
    @Published var isBusy = false

    /// DIDs read for the live panel. B58 candidates are UNVERIFIED on purpose.
    private let liveDIDs: [UInt16] = [0xDD03, 0xDD04, 0xDD02, 0xDD01, 0xDD05]

    nonisolated static func makeTransport(_ source: DiagSource) -> Transport {
        switch source {
        case .mock:
            return MockEnetServer()
        case .enet(let host):
            #if canImport(Network)
            return ENetTransport(host: host)
            #else
            return MockEnetServer()
            #endif
        }
    }

    func runIdentify(source: DiagSource = .mock) {
        guard !isBusy else { return }
        isBusy = true
        status = "Connecting…"
        let dids = liveDIDs  // capture before leaving the main actor
        Task.detached { [weak self] in
            // Blocking network I/O happens here, off the main actor.
            let transport = DiagnosticsViewModel.makeTransport(source)
            defer { transport.close() }
            do {
                let client = ReadOnlyDiagClient(transport: transport,
                                                targetAddress: DoIP.zgwAddress)
                let info = try client.gatherVehicleInfo()
                _ = try? client.activate()
                let dtcRecords = (try? client.readDTCs())?.records ?? []

                var live: [LiveValue] = []
                for did in dids {
                    guard let raw = try? client.readDIDRaw(did),
                          let meta = DIDCatalogue.lookup(did) else { continue }
                    let decoded = meta.decode?(raw) ?? raw.hexString
                    live.append(LiveValue(name: meta.name, value: decoded, unit: meta.unit,
                                          verified: meta.verified, note: meta.note))
                }
                let codes = dtcRecords.map {
                    "\($0.code)  (status 0x\(String($0.status, radix: 16)))"
                }
                await self?.publish(info: info, dtcs: codes, live: live)
            } catch {
                await self?.fail("\(error)")
            }
        }
    }

    private func publish(info: VehicleInfo, dtcs: [String], live: [LiveValue]) {
        self.info = info
        self.dtcs = dtcs
        self.liveValues = live
        self.status = "Read-only session complete"
        self.isBusy = false
    }

    private func fail(_ msg: String) {
        self.status = "Error: \(msg)"
        self.isBusy = false
    }
}
