// SPDX-License-Identifier: MIT
// A simulated BMW gateway for tests and the app's practice mode. It behaves
// like the real thing as far as the read-only client can tell: HSFZ acks and
// NACKs, DoIP routing activation and acks, alive checks, response-pending,
// silent (absent) ECUs, and UDP discovery replies.
import Foundation

public final class MockGateway {
    public struct Behavior {
        /// Send an alive check between the ack and the answer.
        public var aliveCheckBeforeAnswer = false
        /// "Response pending" messages before each real answer.
        public var responsePending = 0
        /// NACK the very first HSFZ request (client must resend once).
        public var nackFirstRequest = false
        /// ECUs that are acknowledged by the gateway but never answer.
        public var silentECUs: Set<UInt16> = [0x3D]
        public init() {}
    }

    public let kind: DiagProtocol
    public var behavior: Behavior
    public let vin: String
    public let mac: String
    /// ECU address -> DID -> data.
    public var dids: [UInt16: [UInt16: [UInt8]]]
    public var dtcs: [UInt16: [(UInt32, UInt8)]]
    public private(set) var aliveResponsesSeen = 0
    public private(set) var udsRequestsSeen: [[UInt8]] = []
    private var routingActive = false
    private var nackedOnce = false
    private let lock = NSLock()

    /// `vin` defaults to synthetic test data, not a real vehicle.
    public init(kind: DiagProtocol, vin: String = "WBAJE7C50JWA00000", mac: String = "001A37C0FFEE",
                behavior: Behavior = Behavior()) {
        self.kind = kind
        self.vin = vin
        self.mac = mac
        self.behavior = behavior
        let v = Array(vin.utf8)
        self.dids = [
            0x10: [0xF190: v, 0xF150: [0x00, 0x01, 0x02, 0x03],
                   0xF101: [0x01, 0x00, 0x01, 0x08, 0x00, 0x00, 0x12, 0x34, 0x01, 0x02, 0x03]],
            0x63: [0xF190: v, 0xF150: [0x00, 0x00, 0x63, 0x01], 0xF18C: Array("SIM-HU-0001".utf8),
                   0xF101: [0x01, 0x00, 0x02, 0x06, 0x00, 0x00, 0xAB, 0xCD, 0x10, 0x20, 0x30]],
            0x60: [0xF150: [0x00, 0x00, 0x60, 0x01]],
        ]
        self.dtcs = [0x63: [(0x4B1C00, 0x08)]]
    }

    // MARK: TCP side

    /// One complete frame in -> frames out.
    public func handle(_ frame: [UInt8]) -> [[UInt8]] {
        lock.lock(); defer { lock.unlock() }
        return kind == .hsfz ? handleHSFZ(frame) : handleDoIP(frame)
    }

    private func handleHSFZ(_ frame: [UInt8]) -> [[UInt8]] {
        guard let msg = try? HSFZ.parse(frame) else { return [] }
        switch msg.control {
        case HSFZ.Control.aliveCheckResponse.rawValue:
            aliveResponsesSeen += 1
            return []
        case HSFZ.Control.diagnostic.rawValue:
            guard msg.payload.count >= 3 else {
                return [HSFZ.frame(control: HSFZ.Control.incorrectFormat.rawValue, payload: [])]
            }
            let tester = msg.payload[0], ecu = msg.payload[1]
            let uds = Array(msg.payload[2...])
            if behavior.nackFirstRequest && !nackedOnce {
                nackedOnce = true
                return [HSFZ.frame(control: HSFZ.Control.nack.rawValue, payload: [])]
            }
            udsRequestsSeen.append(uds)
            // Ack echoes the start of the request (at most 13 bytes in total).
            var out = [HSFZ.frame(control: HSFZ.Control.ack.rawValue,
                                  payload: Array(msg.payload.prefix(HSFZ.maxAckLength - HSFZ.headerLength)))]
            if behavior.silentECUs.contains(UInt16(ecu)) { return out }
            if behavior.aliveCheckBeforeAnswer {
                out.append(HSFZ.frame(control: HSFZ.Control.aliveCheck.rawValue, payload: []))
            }
            for _ in 0..<behavior.responsePending {
                out.append(HSFZ.buildDiagnostic(source: ecu, target: tester,
                                                uds: [UDS.negativeResponseSID, uds[0], 0x78]))
            }
            out.append(HSFZ.buildDiagnostic(source: ecu, target: tester, uds: answer(ecu: UInt16(ecu), uds)))
            return out
        default:
            return []
        }
    }

    private func handleDoIP(_ frame: [UInt8]) -> [[UInt8]] {
        guard let (h, p) = try? DoIP.parseHeader(frame) else { return [] }
        let v = h.version
        switch h.payloadType {
        case DoIP.PayloadType.routingActivationRequest.rawValue:
            let tester = p.count >= 2 ? (UInt16(p[0]) << 8 | UInt16(p[1])) : 0
            routingActive = true
            let body = DoIP.be16(tester) + DoIP.be16(DoIP.zgwAddress) + [DoIP.routingActivationSuccess, 0, 0, 0, 0]
            return [DoIP.frame(.routingActivationResponse, body, version: v)]
        case DoIP.PayloadType.aliveCheckResponse.rawValue:
            aliveResponsesSeen += 1
            return []
        case DoIP.PayloadType.diagnosticMessage.rawValue:
            guard let m = try? DoIP.parseDiagnosticMessage(p), !m.uds.isEmpty else { return [] }
            guard routingActive else {
                return [DoIP.frame(.diagnosticNegativeAck,
                                   DoIP.be16(m.target) + DoIP.be16(m.source) + [0x02], version: v)]
            }
            udsRequestsSeen.append(m.uds)
            var out = [DoIP.frame(.diagnosticPositiveAck,
                                  DoIP.be16(m.target) + DoIP.be16(m.source) + [0x00] + Array(m.uds.prefix(5)),
                                  version: v)]
            if behavior.silentECUs.contains(m.target) { return out }
            if behavior.aliveCheckBeforeAnswer {
                out.append(DoIP.frame(.aliveCheckRequest, [], version: v))
            }
            for _ in 0..<behavior.responsePending {
                out.append(DoIP.buildDiagnosticMessage(source: m.target, target: m.source,
                                                       uds: [UDS.negativeResponseSID, m.uds[0], 0x78], version: v))
            }
            out.append(DoIP.buildDiagnosticMessage(source: m.target, target: m.source,
                                                   uds: answer(ecu: m.target, m.uds), version: v))
            return out
        default:
            return [DoIP.frame(.genericNack, [0x01], version: v)]
        }
    }

    private func answer(ecu: UInt16, _ req: [UInt8]) -> [UInt8] {
        let sid = req[0]
        switch sid {
        case UDS.Service.readDataByIdentifier.rawValue:
            guard req.count >= 3 else { return [UDS.negativeResponseSID, sid, 0x13] }
            let did = UInt16(req[1]) << 8 | UInt16(req[2])
            guard let data = dids[ecu]?[did] else { return [UDS.negativeResponseSID, sid, 0x31] }
            return [sid &+ UDS.positiveOffset, req[1], req[2]] + data
        case UDS.Service.readDTCInformation.rawValue:
            var out: [UInt8] = [sid &+ UDS.positiveOffset, req.count > 1 ? req[1] : 0x02, 0xFF]
            for (dtc, status) in dtcs[ecu] ?? [] {
                out += [UInt8((dtc >> 16) & 0xFF), UInt8((dtc >> 8) & 0xFF), UInt8(dtc & 0xFF), status]
            }
            return out
        case UDS.Service.testerPresent.rawValue:
            return [sid &+ UDS.positiveOffset, 0x00]
        default:
            return [UDS.negativeResponseSID, sid, 0x11]
        }
    }

    // MARK: UDP side (discovery)

    /// Reply to a discovery datagram, if this gateway would answer it.
    public func identReply(to datagram: [UInt8]) -> [UInt8]? {
        switch kind {
        case .hsfz:
            guard datagram == HSFZ.buildIdentRequest() else { return nil }
            return HSFZ.buildIdentReply(diagAddress: 0x10, mac: mac, vin: vin)
        case .doip:
            guard let (h, _) = try? DoIP.parseHeader(datagram),
                  h.payloadType == DoIP.PayloadType.vehicleIdRequest.rawValue else { return nil }
            var p = Array(vin.utf8.prefix(17))
            p += DoIP.be16(DoIP.zgwAddress)
            p += Array([UInt8](hex: mac).prefix(6))   // EID
            p += Array([UInt8](hex: mac).prefix(6))   // GID
            p += [0x00, 0x00]                         // further action, sync status
            return DoIP.frame(.vehicleAnnouncement, p, version: h.version)
        }
    }
}

/// An in-memory ByteStream connected to a MockGateway.
public final class MockGatewayStream: ByteStream {
    public let gateway: MockGateway
    private var reader: FrameReader
    private var outbound: [UInt8] = []
    private var closed = false
    private let lock = NSLock()
    /// Deliver output in pieces of this size, to exercise partial-read handling.
    public var chunkSize: Int

    public init(gateway: MockGateway, chunkSize: Int = 4096) {
        self.gateway = gateway
        self.reader = FrameReader(format: gateway.kind == .hsfz ? .hsfz : .doip)
        self.chunkSize = max(1, chunkSize)
    }

    public func write(_ bytes: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { throw TransportError.closed }
        reader.append(bytes)
        while let f = try reader.nextFrame() {
            for out in gateway.handle(f) { outbound += out }
        }
    }

    public func read(timeout: TimeInterval) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { throw TransportError.closed }
        guard !outbound.isEmpty else { throw TransportError.timeout("mock gateway has nothing to send") }
        let n = min(chunkSize, outbound.count)
        let chunk = Array(outbound[0..<n])
        outbound.removeFirst(n)
        return chunk
    }

    public func close() {
        lock.lock(); closed = true; lock.unlock()
    }
}
