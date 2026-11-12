// SPDX-License-Identifier: MIT
// The whole-car code scan (read-only):
//   1. find the modules with one request to all of them (BMW's 0xDF),
//   2. read each module's fault memory (ReadDTCInformation 19 02 FF),
//   3. ask the engine computer for its OBD-II codes (modes 03, 07, 0A) and the
//      engine light / inspection readiness (DID F401, else mode 01 PID 01).
// Nothing here clears or changes anything.
import Foundation

/// OBD-II monitor status (PID 01): engine light, code count, readiness.
public struct OBDMonitorStatus: Equatable, Sendable {
    public struct Monitor: Equatable, Sendable {
        public let name: String
        public let ready: Bool
    }

    public let engineLightOn: Bool
    public let storedCodeCount: Int
    public let diesel: Bool
    /// Only the monitors this car supports.
    public let monitors: [Monitor]

    public var notReady: [String] { monitors.filter { !$0.ready }.map(\.name) }

    /// The four data bytes A-D of PID 01.
    public static func parse(_ b: [UInt8]) -> OBDMonitorStatus? {
        guard b.count >= 4 else { return nil }
        let a = b[0], bb = b[1], c = b[2], d = b[3]
        let diesel = bb & 0x08 != 0
        var monitors: [Monitor] = []
        for (bit, name) in [(0, "Misfire"), (1, "Fuel system"), (2, "Components")] where bb & (1 << bit) != 0 {
            monitors.append(Monitor(name: name, ready: bb & (1 << (bit + 4)) == 0))
        }
        let names = diesel
            ? ["NMHC catalyst", "NOx aftertreatment", "", "Boost pressure", "", "Exhaust gas sensor",
               "Particulate filter", "EGR / VVT system"]
            : ["Catalyst", "Heated catalyst", "Evaporative system (EVAP)", "Secondary air",
               "A/C or particulate filter", "Oxygen sensor", "Oxygen sensor heater", "EGR / VVT system"]
        for bit in 0..<8 where c & (1 << bit) != 0 && !names[bit].isEmpty {
            monitors.append(Monitor(name: names[bit], ready: d & (1 << bit) == 0))
        }
        return OBDMonitorStatus(engineLightOn: a & 0x80 != 0, storedCodeCount: Int(a & 0x7F),
                                diesel: diesel, monitors: monitors)
    }

    public var summary: String {
        let light = "engine light \(engineLightOn ? "ON" : "off"), \(storedCodeCount) emission code(s)"
        let ready = notReady.isEmpty
            ? "all \(monitors.count) readiness monitors ready"
            : "\(notReady.count) of \(monitors.count) readiness monitors not ready (\(notReady.joined(separator: ", ")))"
        return light + "; " + ready
    }
}

public struct CodeScan: Sendable {
    public struct Module: Identifiable, Sendable {
        public let address: UInt16
        public let info: ModuleInfo
        public var answered = false
        /// Why there are no results ("no answer", "declined: ...").
        public var note: String?
        /// Real faults only.
        public var codes: [FoundCode] = []
        /// Entries that only say "not tested yet" (normal, hidden).
        public var notTested = 0
        public var id: UInt16 { address }

        public init(address: UInt16, info: ModuleInfo) {
            self.address = address
            self.info = info
        }
    }

    public var modules: [Module] = []
    public var engine: OBDMonitorStatus?
    /// Set when the engine computer gave no OBD-II answers.
    public var obdNote: String?
    public var foundBy = ""
    public var connectionLost = false
    public var cancelled = false
    public var started = Date()
    public var finished = Date()

    public init() {}

    public var faults: [FoundCode] { modules.flatMap(\.codes) }
    public var findings: [CodeFinding] { CodePatterns.analyze(faults) }
    public var hiddenEntries: Int { modules.reduce(0) { $0 + $1.notTested } }
    public var answeredModules: Int { modules.filter(\.answered).count }

    public var summary: String {
        let n = faults.count
        var s = "\(n) fault code\(n == 1 ? "" : "s") in \(answeredModules) module\(answeredModules == 1 ? "" : "s")"
        if hiddenEntries > 0 { s += " (\(hiddenEntries) 'not tested yet' entries hidden)" }
        if connectionLost { s += "; connection lost" }
        if cancelled { s += "; stopped early" }
        return s
    }
}

extension ReadOnlyDiagClient {
    /// One OBD-II code list (mode 03, 07 or 0A) from `target`.
    public func readOBDCodes(_ service: OBD.Service, target: UInt16 = BMWModules.engine) throws -> [String] {
        let req = try OBD.buildRequest(service)
        let resp = try link.request(target: target, uds: req)
        return try OBD.parseCodes(request: req, response: resp)
    }

    /// Engine light and readiness: DID F401 (OBD over UDS), else mode 01 PID 01.
    public func readMonitorStatus(target: UInt16 = BMWModules.engine) throws -> OBDMonitorStatus {
        do {
            if let s = OBDMonitorStatus.parse(try readDID(0xF401, target: target)) { return s }
        } catch UDS.UDSError.negativeResponse(_, _) {
            // Not offered as a UDS identifier: try the classic OBD request below.
        }
        let req = try OBD.buildRequest(.currentData, pid: 0x01)
        let resp = try link.request(target: target, uds: req)
        if resp.first == UDS.negativeResponseSID, resp.count >= 3 {
            throw UDS.UDSError.negativeResponse(requestSID: resp[1], nrc: resp[2])
        }
        guard resp.count >= 6, resp[0] == 0x41, resp[1] == 0x01,
              let s = OBDMonitorStatus.parse(Array(resp[2...])) else {
            throw UDS.UDSError.malformed("unexpected answer to OBD mode 01 PID 01")
        }
        return s
    }

    /// Scan every module's fault memory, then the engine computer's OBD-II codes.
    /// Never throws: what couldn't be read is noted in the result.
    public func scanCodes(isCancelled: () -> Bool = { false },
                          progress: (String) -> Void = { _ in }) -> CodeScan {
        var scan = CodeScan()
        log?.info("Code scan: read-only (fault memory of every module, then OBD-II codes)")

        progress("Finding the modules…")
        var addresses: [UInt16] = []
        do {
            let found = try scanModules()
            addresses = Array(Set(found.map(\.address))).sorted()
            scan.foundBy = "one request to all modules"
        } catch {
            log?.warn("All-modules request failed (\(error)); using the usual module list")
        }
        if addresses.isEmpty {
            addresses = BMWModules.info.keys.sorted()
            scan.foundBy = "the usual module list"
        }

        for address in addresses {
            if isCancelled() { scan.cancelled = true; break }
            var m = CodeScan.Module(address: address, info: BMWModules.describe(address))
            progress("Reading \(m.info.name)…")
            do {
                for record in try readDTCs(target: address).records {
                    let code = FoundCode(module: address, record: record)
                    if code.isFault { m.codes.append(code) } else { m.notTested += 1 }
                }
                m.answered = true
            } catch let UDS.UDSError.negativeResponse(_, nrc) {
                m.answered = true
                m.note = "declined: \(UDS.nrcName(nrc))"
            } catch let e as TransportError {
                m.note = e.description
                if case .closed = e { scan.connectionLost = true }
                if case .io = e { scan.connectionLost = true }
            } catch {
                m.note = (error as? DiagError)?.description ?? "\(error)"
            }
            let what = m.note ?? (m.codes.isEmpty ? "no faults" : m.codes.map { "\($0.code) (\($0.stateText))" }
                .joined(separator: ", "))
            log?.info(String(format: "Fault memory 0x%02X ", address) + "\(m.info.name): \(what)"
                      + (m.notTested > 0 ? "; \(m.notTested) not tested yet" : ""))
            scan.modules.append(m)
            if scan.connectionLost { break }
        }

        if !scan.connectionLost && !scan.cancelled && addresses.contains(BMWModules.engine) {
            progress("Reading the engine computer's OBD-II codes…")
            readOBD(into: &scan)
        }
        scan.finished = Date()
        log?.info("Code scan finished: \(scan.summary)")
        return scan
    }

    private func readOBD(into scan: inout CodeScan) {
        var order: [String] = []
        var states: [String: [CodeState]] = [:]
        var answered = 0
        let lists: [(OBD.Service, CodeState)] = [(.storedCodes, .stored), (.pendingCodes, .pending),
                                                 (.permanentCodes, .permanent)]
        for (service, state) in lists {
            let name = String(format: "OBD mode %02X", service.rawValue)
            do {
                let codes = try readOBDCodes(service)
                answered += 1
                log?.info("\(name) (\(state.label.lowercased())): \(codes.isEmpty ? "none" : codes.joined(separator: ", "))")
                for c in codes {
                    if states[c] == nil { order.append(c) }
                    states[c, default: []].append(state)
                }
            } catch let UDS.UDSError.negativeResponse(_, nrc) {
                log?.info("\(name): declined (\(UDS.nrcName(nrc)))")
            } catch let e as TransportError {
                log?.warn("\(name): \(e.description)")
                if case .closed = e { scan.connectionLost = true }
                if case .io = e { scan.connectionLost = true }
                break
            } catch {
                log?.info("\(name): \(error)")
                // No answer at all: the other OBD requests won't fare better.
                if answered == 0, error is DiagError { break }
            }
        }
        if !scan.connectionLost {
            do {
                scan.engine = try readMonitorStatus()
                log?.info("Engine light and readiness: \(scan.engine!.summary)")
            } catch {
                log?.info("Engine light and readiness: not available (\(error))")
            }
        }
        if answered == 0 {
            scan.obdNote = "The engine computer didn't answer the standard OBD-II code requests over this "
                + "connection. Its BMW codes are listed with the other modules."
        }
        let found = order.map { c in
            FoundCode(module: BMWModules.engine, code: c, isSAE: true, status: nil, states: states[c] ?? [],
                      source: .obd)
        }
        guard !found.isEmpty else { return }
        if let i = scan.modules.firstIndex(where: { $0.address == BMWModules.engine }) {
            scan.modules[i].codes = found + scan.modules[i].codes
            scan.modules[i].answered = true
        } else {
            var m = CodeScan.Module(address: BMWModules.engine, info: BMWModules.describe(BMWModules.engine))
            m.answered = true
            m.codes = found
            scan.modules.append(m)
        }
    }
}
