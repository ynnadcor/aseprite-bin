// SPDX-License-Identifier: MIT
// Read-only diagnostic client + the "Identify" sweep used for the first car test.
import Foundation

public struct ECUTarget: Equatable, Sendable {
    public let name: String
    public let address: UInt16
    /// Whether this ECU's diagnostic address on a G30 is confirmed by a source.
    public let addressConfirmed: Bool
    public let dids: [UInt16]
    public let readDTCs: Bool

    public init(name: String, address: UInt16, addressConfirmed: Bool, dids: [UInt16], readDTCs: Bool) {
        self.name = name
        self.address = address
        self.addressConfirmed = addressConfirmed
        self.dids = dids
        self.readDTCs = readDTCs
    }
}

/// What the first car test reads. Every request is ReadDataByIdentifier or
/// ReadDTCInformation - nothing that changes state.
public struct IdentifyPlan: Equatable, Sendable {
    public let targets: [ECUTarget]

    public init(targets: [ECUTarget]) { self.targets = targets }

    /// ZGW 0x10 and head unit 0x63 are confirmed (EdiabasLib's gateway default;
    /// community reports of "ECU 63" for NBT EVO). KOMBI 0x60 and HUD 0x3D are
    /// the usual BMW addresses but unconfirmed for this car: if they don't
    /// answer, that is logged and the sweep moves on.
    public static let g30 = IdentifyPlan(targets: [
        ECUTarget(name: "Central gateway (ZGW)", address: 0x10, addressConfirmed: true,
                  dids: [0xF190, 0xF150, 0xF101], readDTCs: false),
        ECUTarget(name: "Head unit (NBT EVO)", address: 0x63, addressConfirmed: true,
                  dids: [0xF190, 0xF150, 0xF101, 0xF18C], readDTCs: true),
        ECUTarget(name: "Instrument cluster (KOMBI)", address: 0x60, addressConfirmed: false,
                  dids: [0xF150, 0xF101], readDTCs: false),
        ECUTarget(name: "Head-up display (HUD)", address: 0x3D, addressConfirmed: false,
                  dids: [0xF150, 0xF101], readDTCs: false),
    ])
}

public struct IdentifyItem: Identifiable, Sendable {
    public enum Outcome: Sendable, Equatable {
        case value(String)
        case negative(String)   // the ECU answered "no" (e.g. not supported)
        case failed(String)     // no answer / transport problem
        case skipped(String)
    }

    public let id: Int
    public let ecu: String
    public let address: UInt16
    public let label: String
    public let outcome: Outcome
}

public struct IdentifyReport: Sendable {
    public var protocolKind: DiagProtocol
    public var host: String
    public var items: [IdentifyItem] = []
    public var vin: String?
    public var started = Date()
    public var finished = Date()

    public var answeredCount: Int {
        items.filter { if case .value = $0.outcome { return true }; return false }.count
    }

    public var summary: String {
        let neg = items.filter { if case .negative = $0.outcome { return true }; return false }.count
        let fail = items.filter { if case .failed = $0.outcome { return true }; return false }.count
        return "\(answeredCount) answered, \(neg) declined, \(fail) no answer"
    }
}

public final class ReadOnlyDiagClient {
    public let link: DiagLink
    private let log: SessionLog?

    public init(link: DiagLink, log: SessionLog? = nil) {
        self.link = link
        self.log = log
    }

    public func readDID(_ did: UInt16, target: UInt16) throws -> [UInt8] {
        let req = try UDS.buildReadDataByIdentifier(did)
        let resp = try link.request(target: target, uds: req)
        guard case let .rdbi(r) = try UDS.parseResponse(request: req, response: resp) else {
            throw UDS.UDSError.malformed("expected ReadDataByIdentifier answer")
        }
        guard r.did == did else { throw UDS.UDSError.malformed("answer is for a different DID") }
        return r.data
    }

    public func readDTCs(target: UInt16, statusMask: UInt8 = 0xFF) throws -> UDS.ReadDTCResponse {
        let req = try UDS.buildReadDTCByStatusMask(statusMask)
        let resp = try link.request(target: target, uds: req)
        guard case let .dtc(r) = try UDS.parseResponse(request: req, response: resp) else {
            throw UDS.UDSError.malformed("expected ReadDTCInformation answer")
        }
        return r
    }

    /// Run every read in `plan`, recording each outcome. Never throws: one ECU
    /// not answering doesn't stop the others. A dropped connection ends the run.
    public func runIdentify(plan: IdentifyPlan = .g30, host: String,
                            isCancelled: () -> Bool = { false }) -> IdentifyReport {
        var report = IdentifyReport(protocolKind: link.protocolKind, host: host)
        var nextId = 0
        var connectionLost = false
        func add(_ t: ECUTarget, _ label: String, _ o: IdentifyItem.Outcome) {
            report.items.append(IdentifyItem(id: nextId, ecu: t.name, address: t.address, label: label, outcome: o))
            nextId += 1
        }

        log?.info("Identify: \(plan.targets.count) ECUs, read-only requests only")
        for target in plan.targets {
            var ecuSilent = false
            var reads: [(String, () throws -> String)] = []
            for did in target.dids {
                let meta = DIDCatalogue.lookup(did)
                let label = (meta?.name ?? "DID") + " " + String(format: "%04X", did)
                reads.append((label, { [self] in
                    let data = try readDID(did, target: target.address)
                    if did == 0xF190 {
                        let v = DIDCatalogue.ascii(data)
                        if v.count == 17 { report.vin = v }
                    }
                    return meta?.decode?(data) ?? data.spacedHex
                }))
            }
            if target.readDTCs {
                reads.append(("Fault codes (19 02 FF)", { [self] in
                    let r = try readDTCs(target: target.address)
                    if r.records.isEmpty { return "none stored" }
                    let shown = r.records.prefix(20).map { rec in
                        rec.code + "/" + String(format: "%02X", rec.status)
                    }
                    return "\(r.records.count): " + shown.joined(separator: " ")
                }))
            }

            for (label, read) in reads {
                if isCancelled() { add(target, label, .skipped("cancelled")); continue }
                if connectionLost { add(target, label, .skipped("connection lost")); continue }
                if ecuSilent { add(target, label, .skipped("ECU did not answer earlier")); continue }
                do {
                    let value = try read()
                    add(target, label, .value(value))
                } catch let UDS.UDSError.negativeResponse(_, nrc) {
                    add(target, label, .negative(UDS.nrcName(nrc)))
                } catch let e as DiagError {
                    add(target, label, .failed(e.description))
                    if case .noResponse = e { ecuSilent = true }
                    if case .noAck = e { ecuSilent = true }
                } catch let e as TransportError {
                    add(target, label, .failed(e.description))
                    if case .closed = e { connectionLost = true }
                    if case .io = e { connectionLost = true }
                } catch {
                    add(target, label, .failed(String(describing: error)))
                }
            }
        }
        report.finished = Date()
        log?.info("Identify finished: \(report.summary)")
        return report
    }
}
