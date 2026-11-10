// SPDX-License-Identifier: MIT
import Foundation
import UIKit
import BMWLinkKit

/// Thread-safe cancel flag shared with background work.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// Drives the guided, read-only car test:
///   1. cable  - is the USB Ethernet adapter up with an address?
///   2. find   - locate the car's gateway (broadcast / typed address / sweep)
///   3. read   - read-only identify sweep
/// Everything is recorded in a session log that can be shared (VIN/MAC hidden).
@MainActor
final class DiagnosticsViewModel: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        case car = "My car (ENET)"
        case practice = "Simulated car"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .car {
        didSet { if oldValue != mode { modeChanged() } }
    }
    @Published private(set) var interfaces: [NetInterface] = []
    @Published private(set) var wired: NetInterface?
    @Published private(set) var gateways: [DiscoveredGateway] = []
    @Published var selected: DiscoveredGateway?
    @Published var manualHost = ""
    @Published private(set) var busy: String?
    @Published private(set) var sweepProgress: Double?
    @Published private(set) var message = ""
    @Published private(set) var report: IdentifyReport?
    @Published private(set) var logLines: [String] = []
    @Published private(set) var exportURL: URL?
    @Published var revealVIN = false

    let log = SessionLog()
    private var cancelFlag = CancelFlag()
    private let defaults = UserDefaults.standard
    private static let hostKey = "bmwlink.lastGatewayHost"
    private static let protocolKey = "bmwlink.lastGatewayProtocol"

    static let practiceGateway = DiscoveredGateway(host: "simulated car", protocolKind: .hsfz,
                                                   vin: "WBAJE7C50JWA00000", mac: "001A37C0FFEE")

    init() {
        log.info("BMW Link session started (read-only)")
        if let host = defaults.string(forKey: Self.hostKey),
           let raw = defaults.string(forKey: Self.protocolKey),
           let kind = DiagProtocol(rawValue: raw) {
            let remembered = DiscoveredGateway(host: host, protocolKind: kind)
            gateways = [remembered]
            selected = remembered
            manualHost = host
            log.info("Remembered gateway \(host) (\(kind.displayName))")
        }
        refreshInterfaces()
    }

    var isBusy: Bool { busy != nil }

    // MARK: - display helpers

    func displayVIN(_ v: String) -> String {
        guard !v.isEmpty else { return "—" }
        return revealVIN ? v : LogRedactor.shortVIN(v)
    }

    private func refreshLog() {
        logLines = log.all.suffix(300).map(log.format)
        writeLogFile()
    }

    private func modeChanged() {
        cancel()
        report = nil
        message = ""
        if mode == .practice {
            gateways = []
            selected = nil
            log.info("Switched to the simulated car (no network)")
        } else {
            log.info("Switched to the real car")
            refreshInterfaces()
        }
        refreshLog()
    }

    // MARK: - 1. cable

    func refreshInterfaces() {
        interfaces = NetInterfaces.list()
        wired = NetInterfaces.wiredCandidate(interfaces)
        let summary = interfaces.map { "\($0.name)=\($0.address)\($0.isUp ? "" : "(down)")" }
            .joined(separator: ", ")
        log.info("Interfaces: \(summary.isEmpty ? "none" : summary)")
        if let w = wired {
            log.info("Wired candidate: \(w.name) \(w.address)/\(w.netmask)")
        } else {
            log.warn("No wired Ethernet interface with an address yet")
        }
        refreshLog()
    }

    // MARK: - 2. find the car

    func autoFind() {
        guard !isBusy else { return }
        if mode == .practice {
            finishFind(.success([Self.practiceGateway]), how: "Automatic search")
            return
        }
        busy = "Searching the cable for the car…"
        let iface = wired
        let log = self.log
        Task.detached { [weak self] in
            let result = Result { try GatewayDiscovery(log: log).broadcast(interface: iface) }
            await self?.finishFind(result, how: "Automatic search")
        }
    }

    func checkHost() {
        guard !isBusy else { return }
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        if mode == .practice {
            finishFind(.success([Self.practiceGateway]), how: "Address check")
            return
        }
        guard GatewayDiscovery.ipValue(host) != nil else {
            message = "“\(host)” isn't an IPv4 address like 169.254.12.34."
            return
        }
        busy = "Checking \(host)…"
        let iface = wired
        let log = self.log
        Task.detached { [weak self] in
            let result = Result { try GatewayDiscovery(log: log).probe(host: host, interface: iface) }
            await self?.finishFind(result, how: "Address check")
        }
    }

    func startSweep() {
        guard !isBusy else { return }
        cancelFlag = CancelFlag()
        let flag = cancelFlag
        busy = "Searching every address on the cable…"
        sweepProgress = 0
        if mode == .practice {
            Task { [weak self] in
                for step in 1...20 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if flag.isCancelled { break }
                    self?.sweepProgress = Double(step) / 20
                }
                let result: Result<[DiscoveredGateway], Error> =
                    flag.isCancelled ? .success([]) : .success([Self.practiceGateway])
                self?.finishFind(result, how: "Cable search")
            }
            return
        }
        guard let iface = wired else {
            busy = nil
            sweepProgress = nil
            message = "No wired Ethernet interface found. Plug in the adapter and cable, wait 10 seconds, then tap Refresh."
            return
        }
        let log = self.log
        Task.detached { [weak self] in
            var lastShown = -1
            let result = Result { () throws -> [DiscoveredGateway] in
                let gw = try GatewayDiscovery(log: log).sweep(
                    interface: iface,
                    isCancelled: { flag.isCancelled },
                    progress: { done, total in
                        let pct = done * 100 / max(1, total)
                        if pct != lastShown {
                            lastShown = pct
                            Task { @MainActor in self?.sweepProgress = Double(done) / Double(max(1, total)) }
                        }
                    })
                return gw.map { [$0] } ?? []
            }
            await self?.finishFind(result, how: "Cable search")
        }
    }

    func cancel() {
        cancelFlag.cancel()
    }

    private func finishFind(_ result: Result<[DiscoveredGateway], Error>, how: String) {
        busy = nil
        sweepProgress = nil
        switch result {
        case .success(let found) where !found.isEmpty:
            for g in found where !gateways.contains(g) { gateways.insert(g, at: 0) }
            selected = found.first
            message = "\(how): found \(found.count == 1 ? "the car" : "\(found.count) gateways") - "
                + "\(found[0].protocolKind.displayName) at \(found[0].host)."
            log.info(message)
        case .success:
            message = "\(how): nothing answered. Is the ignition on and the cable plugged in? "
                + "If iOS asked for Local Network access, allow it and try again."
            log.warn(message)
        case .failure(let error):
            message = "\(how) failed: \(error)"
            log.error(message)
        }
        refreshLog()
    }

    // MARK: - 3. read-only identify

    func runIdentify() {
        guard !isBusy, let gw = selected else { return }
        cancelFlag = CancelFlag()
        let flag = cancelFlag
        let mode = self.mode
        let iface = wired?.name
        let log = self.log
        report = nil
        busy = "Reading identification data (read-only)…"
        Task.detached { [weak self] in
            let outcome: Result<IdentifyReport, Error>
            do {
                let link: DiagLink
                if mode == .practice {
                    let stream = MockGatewayStream(gateway: MockGateway(kind: gw.protocolKind))
                    link = gw.protocolKind == .hsfz
                        ? HSFZLink(stream: stream, log: log, timeouts: .uniform(1))
                        : DoIPLink(stream: stream, log: log, timeouts: .uniform(1))
                    try link.open()
                } else {
                    link = try DiagConnector.connect(host: gw.host, protocolKind: gw.protocolKind,
                                                     interface: iface, log: log)
                }
                defer { link.close() }
                let client = ReadOnlyDiagClient(link: link, log: log)
                outcome = .success(client.runIdentify(plan: .g30, host: gw.host,
                                                      isCancelled: { flag.isCancelled }))
            } catch {
                outcome = .failure(error)
            }
            await self?.finishIdentify(outcome, gateway: gw)
        }
    }

    private func finishIdentify(_ outcome: Result<IdentifyReport, Error>, gateway: DiscoveredGateway) {
        busy = nil
        switch outcome {
        case .success(let r):
            report = r
            message = "Identify finished: \(r.summary)."
            if mode == .car && r.answeredCount > 0 {
                defaults.set(gateway.host, forKey: Self.hostKey)
                defaults.set(gateway.protocolKind.rawValue, forKey: Self.protocolKey)
                log.info("Remembering \(gateway.host) for next time")
            }
        case .failure(let error):
            message = "Couldn't talk to the car: \(error)"
            log.error(message)
        }
        refreshLog()
    }

    // MARK: - log export

    private var secrets: [LogRedactor.Secret] {
        var s: [LogRedactor.Secret] = []
        for g in gateways {
            if !g.vin.isEmpty { s.append(LogRedactor.vin(g.vin)) }
            if !g.mac.isEmpty { s.append(LogRedactor.mac(g.mac)) }
        }
        if let v = report?.vin { s.append(LogRedactor.vin(v)) }
        return s
    }

    func exportText() -> String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String ?? "?")
            + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
        var header = [
            "BMW Link session log - read-only diagnostics",
            "Created: \(ISO8601DateFormatter().string(from: Date()))",
            "App: \(version)  iOS: \(UIDevice.current.systemVersion)  Device: \(UIDevice.current.model)",
            "Mode: \(mode.rawValue)",
            "Wired interface: " + (wired.map { "\($0.name) \($0.address)/\($0.netmask)" } ?? "none"),
            "Selected gateway: " + (selected.map { "\($0.host) \($0.protocolKind.displayName)" } ?? "none"),
            "VIN and MAC are masked in this file.",
        ]
        if let r = report { header.append("Identify: \(r.summary)") }
        return log.export(header: header, secrets: secrets)
    }

    private func writeLogFile() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BMWLink-log-\(stamp).txt")
        do {
            if let old = exportURL { try? FileManager.default.removeItem(at: old) }
            try exportText().write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    func copyLog() {
        UIPasteboard.general.string = exportText()
        message = "Log copied (VIN and MAC masked)."
    }

    func clearLog() {
        log.clear()
        log.info("Log cleared")
        refreshLog()
    }
}
