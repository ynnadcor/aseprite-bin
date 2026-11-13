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
    /// Status toast; it fades after a few seconds (the same text is in the log).
    @Published private(set) var message = "" {
        didSet { scheduleMessageClear() }
    }
    private var messageClear: Task<Void, Never>?

    private func scheduleMessageClear() {
        messageClear?.cancel()
        guard !message.isEmpty else { return }
        let shown = message
        messageClear = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled && self.message == shown { self.message = "" }
        }
    }
    @Published private(set) var report: IdentifyReport?
    @Published private(set) var logLines: [String] = []
    @Published private(set) var exportURL: URL?
    @Published var revealVIN = false
    // Test 2
    @Published private(set) var modules: [ModuleScanResult] = []
    @Published private(set) var engineReport: IdentifyReport?
    @Published private(set) var boost: String?
    // Codes tab
    @Published private(set) var codeScan: CodeScan?
    /// Which module the code scan is reading (shown while busy).
    @Published private(set) var codeProgress: String?
    // Gauges tab (live dashboard)
    @Published private(set) var live: LiveSample?
    @Published private(set) var liveRunning = false
    @Published private(set) var peakBoostPsi = 0.0
    /// Measured update rate, samples per second.
    @Published private(set) var liveHz: Double?
    @Published private(set) var liveMessage: String?
    private var liveTask: Task<Void, Never>?
    private var liveSamples = 0
    private var liveStart = Date()

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
        modules = []
        engineReport = nil
        boost = nil
        codeScan = nil
        stopGauges()
        live = nil
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
        guard !isBusy, selected != nil else { return }
        cancelFlag = CancelFlag()
        let flag = cancelFlag
        report = nil
        Task { await identify(flag: flag) }
    }

    func identify(flag: CancelFlag) async {
        guard let gw = selected else { return }
        let outcome = await withLink("Reading identification data (read-only)…", gateway: gw) { link, log in
            ReadOnlyDiagClient(link: link, log: log)
                .runIdentify(plan: .g30, host: gw.host, isCancelled: { flag.isCancelled })
        }
        finishIdentify(outcome, gateway: gw)
    }

    private func finishIdentify(_ outcome: Result<IdentifyReport, Error>, gateway: DiscoveredGateway) {
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

    // MARK: - Test 2 (read-only): every module, engine values

    func scanModules() {
        guard !isBusy, selected != nil else { return }
        Task { await scan() }
    }

    func scan() async {
        guard let gw = selected else { return }
        modules = []
        let outcome = await withLink("Asking every module (one read-only request)…", gateway: gw) { link, log in
            try ReadOnlyDiagClient(link: link, log: log).scanModules()
        }
        switch outcome {
        case .success(let list):
            modules = list
            message = "Module scan: \(list.count) modules answered."
            log.info(message + " " + list.map { String(format: "0x%02X", $0.address) }.joined(separator: ", "))
        case .failure(let error):
            message = "Module scan failed: \(error)"
            log.error(message)
        }
        refreshLog()
    }

    /// Where the HUD probably is, after a module scan.
    var hudHint: String? {
        guard !modules.isEmpty else { return nil }
        if modules.contains(where: { $0.address == 0x3D }) {
            return "Something answered at 0x3D, the usual HUD address."
        }
        let unknown = modules.filter { !$0.isKnown }.count
        if unknown > 0 {
            return "Nothing at 0x3D, so the HUD is probably one of the \(unknown) unknown modules."
        }
        return "Nothing at 0x3D and no unknown modules: the HUD may not answer this read."
    }

    func readEngineValues() {
        guard !isBusy, selected != nil else { return }
        Task { await engine() }
    }

    func engine() async {
        guard let gw = selected else { return }
        engineReport = nil
        boost = nil
        let outcome = await withLink("Reading engine values from the DME (read-only)…", gateway: gw) { link, log in
            ReadOnlyDiagClient(link: link, log: log).runIdentify(plan: .engine, host: gw.host)
        }
        switch outcome {
        case .success(let r):
            engineReport = r
            boost = EngineValues.boost(from: r)
            message = "Engine values: \(r.summary)." + (boost.map { " Boost \($0)." } ?? "")
            log.info(message)
        case .failure(let error):
            message = "Couldn't read engine values: \(error)"
            log.error(message)
        }
        refreshLog()
    }

    // MARK: - Codes tab: whole-car code scan (read-only)

    var canScanCodes: Bool { !isBusy && (selected != nil || mode == .practice) }

    func scanCodes() {
        guard !isBusy else { return }
        if mode == .practice && selected == nil {
            gateways = [Self.practiceGateway]
            selected = Self.practiceGateway
        }
        guard selected != nil else {
            message = "Find the car first: Car tab, steps 1 and 2."
            return
        }
        cancelFlag = CancelFlag()
        let flag = cancelFlag
        Task { await codes(flag: flag) }
    }

    func codes(flag: CancelFlag) async {
        guard let gw = selected else { return }
        codeScan = nil
        codeProgress = nil
        let outcome = await withLink("Scanning every module for fault codes (read-only)…", gateway: gw) { [weak self] link, log in
            ReadOnlyDiagClient(link: link, log: log).scanCodes(
                isCancelled: { flag.isCancelled },
                progress: { text in Task { @MainActor in self?.codeProgress = text } })
        }
        codeProgress = nil
        switch outcome {
        case .success(let scan):
            codeScan = scan
            message = "Code scan: \(scan.summary)."
            if mode == .car && scan.answeredModules > 0 {
                defaults.set(gw.host, forKey: Self.hostKey)
                defaults.set(gw.protocolKind.rawValue, forKey: Self.protocolKey)
            }
        case .failure(let error):
            message = "Couldn't scan the car: \(error)"
            log.error(message)
        }
        refreshLog()
    }

    /// CI screenshots of the Codes tab: scan the simulated car.
    func runCodesScreenshotDemo() {
        mode = .practice
        scanCodes()
    }

    // MARK: - Gauges tab: live dashboard (read-only, polled)

    var canRunGauges: Bool { mode == .practice || selected != nil }

    func startGauges() {
        guard liveTask == nil else { return }
        liveMessage = nil
        peakBoostPsi = 0
        liveSamples = 0
        liveStart = Date()
        liveRunning = true

        if mode == .practice {
            let start = Date()
            liveTask = Task { [weak self] in
                while !Task.isCancelled {
                    let t = Date().timeIntervalSince(start)
                    _ = self?.apply(LiveSample.demo(at: t))
                    try? await Task.sleep(nanoseconds: 120_000_000)   // ~8 Hz
                }
            }
            return
        }
        guard let gw = selected else {
            liveMessage = "Find the car on the Car tab first."
            liveRunning = false
            return
        }
        let modeV = mode, iface = wired?.name, log = self.log
        liveTask = Task.detached { [weak self] in
            let link: DiagLink
            do {
                link = try DiagnosticsViewModel.openLink(mode: modeV, gateway: gw, interface: iface, log: log)
            } catch {
                await self?.failGauges("Couldn't open a connection: \(error)")
                return
            }
            defer { link.close() }
            let client = ReadOnlyDiagClient(link: link)
            while !Task.isCancelled {
                let sample = client.readLiveSample()
                if Task.isCancelled { break }
                let stop = await self?.apply(sample) ?? true
                if stop { break }
                try? await Task.sleep(nanoseconds: 60_000_000)   // be gentle: cap ~12 Hz
            }
            await self?.finishGauges()
        }
    }

    func stopGauges() {
        liveTask?.cancel()
        liveTask = nil
        liveRunning = false
    }

    func resetPeak() { peakBoostPsi = 0 }

    /// Apply a sample on the main actor; returns true if the loop should stop.
    @discardableResult
    private func apply(_ s: LiveSample) -> Bool {
        live = s
        liveSamples += 1
        let elapsed = Date().timeIntervalSince(liveStart)
        if elapsed > 0.2 { liveHz = Double(liveSamples) / elapsed }
        if let b = s.boostPsi { peakBoostPsi = max(peakBoostPsi, b) }
        liveRunning = true
        if !s.hasAnything {
            liveMessage = "The engine computer isn't sharing live values over this connection."
            return true
        }
        return false
    }

    private func failGauges(_ text: String) {
        liveMessage = text
        liveRunning = false
    }

    private func finishGauges() {
        liveRunning = false
    }

    // MARK: - connections

    /// Open a link to `gw` off the main thread, run `work`, close it.
    private func withLink<T: Sendable>(_ busyText: String, gateway gw: DiscoveredGateway,
                                       _ work: @escaping @Sendable (DiagLink, SessionLog) throws -> T) async
        -> Result<T, Error> {
        busy = busyText
        let mode = self.mode
        let iface = wired?.name
        let log = self.log
        let result = await Task.detached { () -> Result<T, Error> in
            Result {
                let link = try DiagnosticsViewModel.openLink(mode: mode, gateway: gw, interface: iface, log: log)
                defer { link.close() }
                return try work(link, log)
            }
        }.value
        busy = nil
        return result
    }

    nonisolated static func openLink(mode: Mode, gateway gw: DiscoveredGateway, interface: String?,
                                     log: SessionLog) throws -> DiagLink {
        if mode == .practice {
            let stream = MockGatewayStream(gateway: MockGateway(kind: gw.protocolKind))
            let link: DiagLink = gw.protocolKind == .hsfz
                ? HSFZLink(stream: stream, log: log, timeouts: .uniform(1))
                : DoIPLink(stream: stream, log: log, timeouts: .uniform(1))
            try link.open()
            return link
        }
        return try DiagConnector.connect(host: gw.host, protocolKind: gw.protocolKind, interface: interface, log: log)
    }

    /// CI screenshots: run the whole flow against the simulated car.
    func runScreenshotDemo() {
        mode = .practice
        Task {
            autoFind()
            await identify(flag: CancelFlag())
            await scan()
            await engine()
        }
    }

    // MARK: - log export

    private var secrets: [LogRedactor.Secret] {
        var s: [LogRedactor.Secret] = []
        for g in gateways {
            if !g.vin.isEmpty { s.append(LogRedactor.vin(g.vin)) }
            if !g.mac.isEmpty { s.append(LogRedactor.mac(g.mac)) }
        }
        if let v = report?.vin { s.append(LogRedactor.vin(v)) }
        for serial in report?.serials ?? [] { s.append(LogRedactor.Secret(serial, keepPrefix: 0)) }
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
            "VIN, MAC and ECU serial numbers are masked in this file.",
        ]
        if let r = report { header.append("Identify: \(r.summary)") }
        if !modules.isEmpty {
            header.append("Module scan: \(modules.count) answered: "
                          + modules.map { String(format: "0x%02X", $0.address) }.joined(separator: ", "))
        }
        if let e = engineReport {
            header.append("Engine values: \(e.summary)" + (boost.map { "; boost \($0)" } ?? ""))
        }
        if let s = codeScan {
            header.append("Code scan: \(s.summary)" + (s.engine.map { "; \($0.summary)" } ?? ""))
            if !s.faults.isEmpty {
                header.append("Codes: " + s.faults.map { String(format: "0x%02X ", $0.module) + "\($0.code) (\($0.stateText))" }
                    .joined(separator: ", "))
            }
            if !s.findings.isEmpty { header.append("Points to: " + s.findings.map(\.title).joined(separator: "; ")) }
        }
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
