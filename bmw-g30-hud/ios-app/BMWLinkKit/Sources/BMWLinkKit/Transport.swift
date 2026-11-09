// SPDX-License-Identifier: MIT
// Transport abstraction + in-memory mock gateway. Mirrors proto/bmwdiag/transport.py.
import Foundation

/// One framed DoIP request -> one framed DoIP response.
public protocol Transport {
    func request(_ frame: [UInt8]) throws -> [UInt8]
    func close()
}

public enum TransportError: Error { case closed, notActivated, timeout, io(String) }

/// Deterministic stand-in for a BMW DoIP gateway (read-only subset), so the
/// whole stack is testable with no vehicle. Matches the Python MockEnetServer.
public final class MockEnetServer: Transport {
    public private(set) var vin: String
    public let entityAddress: UInt16
    public private(set) var routingActive = false
    private var didStore: [UInt16: [UInt8]]
    private var dtcs: [(UInt32, UInt8)]
    private var closed = false

    public init(vin: String = "WBAJE7C50JWA00000",
                entityAddress: UInt16 = DoIP.zgwAddress) {
        precondition(vin.count == 17, "VIN must be 17 chars")
        var store = MockEnetServer.defaultDIDs
        store[0xF190] = Array(vin.utf8)
        self.vin = vin
        self.entityAddress = entityAddress
        self.didStore = store
        self.dtcs = [(0x4B1C00, 0x08)]
    }

    public func close() { closed = true }

    public func request(_ frame: [UInt8]) throws -> [UInt8] {
        if closed { throw TransportError.closed }
        let (header, payload) = try DoIP.parseHeader(frame)
        switch DoIP.PayloadType(rawValue: header.payloadType) {
        case .vehicleIdRequest: return announce()
        case .routingActivationRequest: return routingActivation(payload)
        case .diagnosticMessage: return try diag(payload)
        case .aliveCheckRequest:
            return doipFrame(.aliveCheckResponse, DoIP.be16(DoIP.defaultTesterAddress))
        default:
            return doipFrame(.genericNack, [0x00])
        }
    }

    // MARK: handlers
    private func announce() -> [UInt8] {
        var p = Array(vin.utf8)
        if p.count < 17 { p += [UInt8](repeating: 0, count: 17 - p.count) } else { p = Array(p[0..<17]) }
        p += DoIP.be16(entityAddress)
        p += [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01]
        p += [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01]
        p += [0x00]
        return doipFrame(.vehicleAnnouncement, p)
    }

    private func routingActivation(_ payload: [UInt8]) -> [UInt8] {
        let tester = payload.count >= 2 ? (UInt16(payload[0]) << 8 | UInt16(payload[1])) : 0
        routingActive = true
        var body = DoIP.be16(tester) + DoIP.be16(entityAddress) + [DoIP.routingActivationSuccess]
        body += [0x00, 0x00, 0x00, 0x00]
        return doipFrame(.routingActivationResponse, body)
    }

    private func diag(_ payload: [UInt8]) throws -> [UInt8] {
        let msg = try DoIP.parseDiagnosticMessage(payload)
        guard routingActive else {
            let body = DoIP.be16(msg.target) + DoIP.be16(msg.source) + [0x06]
            return doipFrame(.diagnosticNegativeAck, body)
        }
        let resp = handleUDS(msg.uds)
        return DoIP.buildDiagnosticMessage(source: msg.target, target: msg.source, uds: resp)
    }

    private func handleUDS(_ req: [UInt8]) -> [UInt8] {
        guard let sid = req.first else {
            return [UDS.negativeResponseSID, 0x00, 0x13]
        }
        switch sid {
        case UDS.Service.testerPresent.rawValue:
            return [sid &+ UDS.positiveOffset, 0x00]
        case UDS.Service.diagnosticSessionControl.rawValue:
            let session = req.count > 1 ? req[1] : 0x01
            return [sid &+ UDS.positiveOffset, session, 0x00, 0x32, 0x01, 0xF4]
        case UDS.Service.readDataByIdentifier.rawValue:
            guard req.count >= 3 else { return [UDS.negativeResponseSID, sid, 0x13] }
            let did = UInt16(req[1]) << 8 | UInt16(req[2])
            guard let data = didStore[did] else { return [UDS.negativeResponseSID, sid, 0x31] }
            return [sid &+ UDS.positiveOffset, req[1], req[2]] + data
        case UDS.Service.readDTCInformation.rawValue:
            let sub = req.count > 1 ? req[1] : 0x02
            var out: [UInt8] = [sid &+ UDS.positiveOffset, sub, 0xFF]
            for (dtc, status) in dtcs {
                out += [UInt8((dtc >> 16) & 0xFF), UInt8((dtc >> 8) & 0xFF), UInt8(dtc & 0xFF), status]
            }
            return out
        default:
            return [UDS.negativeResponseSID, sid, 0x11]  // serviceNotSupported
        }
    }

    private func doipFrame(_ type: DoIP.PayloadType, _ payload: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [DoIP.protocolVersion, ~DoIP.protocolVersion]
        out += DoIP.be16(type.rawValue)
        out += DoIP.be32(UInt32(payload.count))
        out += payload
        return out
    }

    static let defaultDIDs: [UInt16: [UInt8]] = [
        0xF18C: Array("SN-0001-ABCDEF".utf8),
        0xF191: Array("HW-6WA-01".utf8),
        0xF194: Array("SW-03.19.22".utf8),
        0xF195: Array("NBTevo_Y24073J".utf8),
        0xF197: Array("HeadUnitHigh2".utf8),
        0xDD01: [UInt8(40 + 88)],
        0xDD02: [UInt8(40 + 31)],
        0xDD03: [UInt8(40 + 104)],
        0xDD04: [UInt8(1500 >> 8), UInt8(1500 & 0xFF)],
        0xDD05: [UInt8(Int(0.62 * 255))],
    ]
}
