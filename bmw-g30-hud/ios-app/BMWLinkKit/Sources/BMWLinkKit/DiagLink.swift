// SPDX-License-Identifier: MIT
// A diagnostic link to the car: HSFZ (port 6801) or DoIP (port 13400).
//
// Real gateways don't answer a request with exactly one message. Around the
// actual UDS answer they send acknowledgements, keep-alive checks we must
// reply to, and "response pending" (NRC 0x78) while an ECU is busy. Both links
// below handle all of that, and refuse to send anything that isn't one of the
// read-only UDS services (defence in depth on top of the UDS builders).
import Foundation

public enum DiagProtocol: String, Codable, Sendable, CaseIterable {
    case hsfz
    case doip

    public var tcpPort: UInt16 { self == .hsfz ? HSFZ.diagPort : DoIP.port }
    public var displayName: String { self == .hsfz ? "HSFZ (TCP 6801)" : "DoIP (TCP 13400)" }
}

public struct DiagTimeouts: Sendable {
    public var connect: TimeInterval = 5
    /// Gateway acknowledgement (EdiabasLib uses 5 s).
    public var ack: TimeInterval = 5
    /// First answer from the ECU after the ack.
    public var response: TimeInterval = 6
    /// Extra time granted after each "response pending".
    public var pending: TimeInterval = 10
    public var maxPending: Int = 30

    public init() {}
    public static let standard = DiagTimeouts()
    public static func uniform(_ t: TimeInterval) -> DiagTimeouts {
        var d = DiagTimeouts()
        d.connect = t; d.ack = t; d.response = t; d.pending = t
        return d
    }
}

public enum DiagError: Error, Equatable, CustomStringConvertible {
    case notReadOnly(UInt8)
    case badAddress(UInt16)
    case noAck(String)
    case noResponse(String)
    case gateway(String)
    case routingDenied(String)
    case tooManyPending

    public var description: String {
        switch self {
        case .notReadOnly(let s): return String(format: "refused: UDS service 0x%02X is not read-only", s)
        case .badAddress(let a): return String(format: "address 0x%04X is not valid for this protocol", a)
        case .noAck(let s): return "no acknowledgement from the gateway (\(s))"
        case .noResponse(let s): return "no answer (\(s))"
        case .gateway(let s): return "gateway reported: \(s)"
        case .routingDenied(let s): return "routing activation \(s)"
        case .tooManyPending: return "ECU kept answering 'response pending'"
        }
    }
}

public protocol DiagLink: AnyObject {
    var protocolKind: DiagProtocol { get }
    func open() throws
    /// Send one read-only UDS request to `target`; return its final UDS answer
    /// (which may itself be a negative response, 0x7F ...).
    func request(target: UInt16, uds: [UInt8]) throws -> [UInt8]
    /// Send one read-only request to every module at once (BMW's "all modules"
    /// address) and collect each module's answer.
    func requestFunctional(uds: [UInt8]) throws -> [(address: UInt16, answer: [UInt8])]
    func close()
}

/// Shared plumbing: framing, logging, deadline-based reads.
public class FramedLink {
    let stream: ByteStream
    var reader: FrameReader
    let log: SessionLog?
    let timeouts: DiagTimeouts
    let label: String

    init(stream: ByteStream, format: FrameFormat, log: SessionLog?, timeouts: DiagTimeouts, label: String) {
        self.stream = stream
        self.reader = FrameReader(format: format)
        self.log = log
        self.timeouts = timeouts
        self.label = label
    }

    func send(_ frame: [UInt8], _ what: String) throws {
        log?.tx("\(label) \(what)", frame)
        try stream.write(frame)
    }

    /// Next complete frame before `deadline`; timeouts are reported with `what`.
    func readFrame(until deadline: Date, waitingFor what: String) throws -> [UInt8] {
        while true {
            if let f = try reader.nextFrame() { return f }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw TransportError.timeout(what) }
            do {
                reader.append(try stream.read(timeout: remaining))
            } catch TransportError.timeout {
                throw TransportError.timeout(what)
            }
        }
    }

    func checkReadOnly(_ uds: [UInt8]) throws -> UInt8 {
        guard let sid = uds.first, UDS.allowedServices.contains(sid) else {
            throw DiagError.notReadOnly(uds.first ?? 0)
        }
        return sid
    }

    static func udsLabel(_ uds: [UInt8]) -> String {
        Array(uds.prefix(4)).spacedHex + (uds.count > 4 ? " …" : "")
    }
}

// MARK: - HSFZ

public final class HSFZLink: FramedLink, DiagLink {
    public let protocolKind = DiagProtocol.hsfz
    public let tester: UInt8

    public init(stream: ByteStream, log: SessionLog? = nil, tester: UInt8 = HSFZ.testerAddress,
                timeouts: DiagTimeouts = .standard) {
        self.tester = tester
        super.init(stream: stream, format: .hsfz, log: log, timeouts: timeouts, label: "HSFZ")
    }

    public func open() throws {
        log?.info("HSFZ: no routing activation needed")
    }

    public func request(target: UInt16, uds: [UInt8]) throws -> [UInt8] {
        let sid = try checkReadOnly(uds)
        guard target <= 0xFF else { throw DiagError.badAddress(target) }
        let t = UInt8(target)
        let req = HSFZ.buildDiagnostic(source: tester, target: t, uds: uds)
        let ecu = String(format: "0x%02X", t)
        try send(req, "request → \(ecu): \(Self.udsLabel(uds))")

        var acked = false
        var resent = false
        var pending = 0
        var deadline = Date().addingTimeInterval(timeouts.ack)
        while true {
            let f: [UInt8]
            do {
                f = try readFrame(until: deadline,
                                  waitingFor: acked ? "answer from ECU \(ecu)" : "gateway ack")
            } catch TransportError.timeout(let what) {
                throw acked ? DiagError.noResponse(what) : DiagError.noAck(what)
            }
            let msg = try HSFZ.parse(f)
            switch msg.control {
            case HSFZ.Control.ack.rawValue:
                log?.rx("HSFZ ack", f)
                if !HSFZ.ackMatches(f, request: req) { log?.warn("HSFZ ack does not echo the request") }
                acked = true
                deadline = Date().addingTimeInterval(timeouts.response)

            case HSFZ.Control.nack.rawValue:
                log?.rx("HSFZ NACK", f)
                guard !resent else { throw DiagError.gateway("NACK after resend") }
                resent = true
                try send(req, "resend after NACK")
                deadline = Date().addingTimeInterval(timeouts.ack)

            case HSFZ.Control.aliveCheck.rawValue:
                log?.rx("HSFZ alive check", f)
                try send(HSFZ.buildAliveCheckResponse(tester: tester), "alive check response")

            case HSFZ.Control.diagnostic.rawValue:
                guard msg.payload.count >= 3 else {
                    log?.warn("HSFZ: short diagnostic frame ignored")
                    continue
                }
                let src = msg.payload[0], dst = msg.payload[1]
                let answer = Array(msg.payload[2...])
                log?.rx(String(format: "HSFZ answer ← 0x%02X", src), f)
                guard src == t && dst == tester else {
                    log?.warn("HSFZ: frame for other addresses ignored")
                    continue
                }
                if !acked { log?.warn("HSFZ: answer arrived before the ack") }
                if UDS.isResponsePending(answer, sid: sid) {
                    pending += 1
                    guard pending <= timeouts.maxPending else { throw DiagError.tooManyPending }
                    log?.info("ECU \(ecu) says response pending (\(pending))")
                    deadline = Date().addingTimeInterval(timeouts.pending)
                    continue
                }
                return answer

            case 0x0040...0x0045:
                log?.rx("HSFZ \(HSFZ.controlName(msg.control))", f)
                throw DiagError.gateway(HSFZ.controlName(msg.control))

            default:
                log?.rx("HSFZ \(HSFZ.controlName(msg.control)) (ignored)", f)
            }
        }
    }

    /// One request to BMW's "all modules" address (0xDF); every module answers
    /// once. Collection ends `quiet` seconds after the last answer, or after
    /// `maxTime`.
    public func requestFunctional(uds: [UInt8]) throws -> [(address: UInt16, answer: [UInt8])] {
        try requestFunctional(uds: uds, quiet: 1.5, maxTime: 8)
    }

    public func requestFunctional(uds: [UInt8], quiet: TimeInterval, maxTime: TimeInterval)
        throws -> [(address: UInt16, answer: [UInt8])] {
        let sid = try checkReadOnly(uds)
        let req = HSFZ.buildDiagnostic(source: tester, target: HSFZ.functionalAddress, uds: uds)
        try send(req, String(format: "request → 0x%02X (all modules): ", HSFZ.functionalAddress) + Self.udsLabel(uds))
        var answers: [UInt8: [UInt8]] = [:]
        var resent = false
        let end = Date().addingTimeInterval(maxTime)
        var deadline = min(end, Date().addingTimeInterval(timeouts.ack))
        while true {
            let f: [UInt8]
            do {
                f = try readFrame(until: deadline, waitingFor: "answers from all modules")
            } catch TransportError.timeout {
                break
            }
            let msg = try HSFZ.parse(f)
            switch msg.control {
            case HSFZ.Control.ack.rawValue:
                log?.rx("HSFZ ack", f)
                deadline = min(end, Date().addingTimeInterval(quiet))
            case HSFZ.Control.nack.rawValue:
                log?.rx("HSFZ NACK", f)
                guard !resent else { throw DiagError.gateway("NACK after resend") }
                resent = true
                try send(req, "resend after NACK")
                deadline = min(end, Date().addingTimeInterval(timeouts.ack))
            case HSFZ.Control.aliveCheck.rawValue:
                log?.rx("HSFZ alive check", f)
                try send(HSFZ.buildAliveCheckResponse(tester: tester), "alive check response")
            case HSFZ.Control.diagnostic.rawValue:
                guard msg.payload.count >= 3 else { continue }
                let src = msg.payload[0], dst = msg.payload[1]
                let answer = Array(msg.payload[2...])
                log?.rx(String(format: "HSFZ answer ← 0x%02X", src), f)
                guard dst == tester else { continue }
                if UDS.isResponsePending(answer, sid: sid) {
                    deadline = min(end, Date().addingTimeInterval(timeouts.pending))
                    continue
                }
                if answers[src] == nil { answers[src] = answer }
                deadline = min(end, Date().addingTimeInterval(quiet))
            case 0x0040...0x0045:
                log?.rx("HSFZ \(HSFZ.controlName(msg.control))", f)
                throw DiagError.gateway(HSFZ.controlName(msg.control))
            default:
                log?.rx("HSFZ \(HSFZ.controlName(msg.control)) (ignored)", f)
            }
        }
        log?.info("All-modules request: \(answers.count) answered")
        return answers.keys.sorted().map { (address: UInt16($0), answer: answers[$0]!) }
    }

    public func close() {
        stream.close()
        log?.info("HSFZ connection closed")
    }
}

// MARK: - DoIP

public final class DoIPLink: FramedLink, DiagLink {
    public let protocolKind = DiagProtocol.doip
    public let tester: UInt16
    public let version: UInt8
    public private(set) var activated = false

    public init(stream: ByteStream, log: SessionLog? = nil, tester: UInt16 = DoIP.bmwTesterAddress,
                version: UInt8 = DoIP.bmwProtocolVersion, timeouts: DiagTimeouts = .standard) {
        self.tester = tester
        self.version = version
        super.init(stream: stream, format: .doip, log: log, timeouts: timeouts, label: "DoIP")
    }

    private func replyAlive(_ f: [UInt8]) throws {
        log?.rx("DoIP alive check", f)
        try send(DoIP.buildAliveCheckResponse(sourceAddress: tester, version: version), "alive check response")
    }

    public func open() throws {
        let req = DoIP.buildRoutingActivationRequest(testerAddress: tester, activationType: 0x00,
                                                     oemSpecific: [0, 0, 0, 0], version: version)
        try send(req, String(format: "routing activation (tester 0x%04X)", tester))
        let deadline = Date().addingTimeInterval(timeouts.ack)
        while true {
            let f: [UInt8]
            do {
                f = try readFrame(until: deadline, waitingFor: "routing activation response")
            } catch TransportError.timeout(let what) {
                throw DiagError.noResponse(what)
            }
            let (h, p) = try DoIP.parseHeader(f)
            switch h.payloadType {
            case DoIP.PayloadType.routingActivationResponse.rawValue:
                let r = try DoIP.parseRoutingActivationResponse(p)
                log?.rx("DoIP routing activation: \(DoIP.routingResponseName(r.responseCode))", f)
                guard r.ok else { throw DiagError.routingDenied(DoIP.routingResponseName(r.responseCode)) }
                activated = true
                return
            case DoIP.PayloadType.aliveCheckRequest.rawValue:
                try replyAlive(f)
            case DoIP.PayloadType.genericNack.rawValue:
                log?.rx("DoIP generic NACK", f)
                throw DiagError.gateway("generic NACK: " + DoIP.genericNackName(p.first ?? 0xFF))
            default:
                log?.rx(String(format: "DoIP payload 0x%04X (ignored)", h.payloadType), f)
            }
        }
    }

    public func request(target: UInt16, uds: [UInt8]) throws -> [UInt8] {
        let sid = try checkReadOnly(uds)
        if !activated { try open() }
        let req = DoIP.buildDiagnosticMessage(source: tester, target: target, uds: uds, version: version)
        let ecu = String(format: "0x%04X", target)
        try send(req, "request → \(ecu): \(Self.udsLabel(uds))")

        var acked = false
        var pending = 0
        var deadline = Date().addingTimeInterval(timeouts.ack)
        while true {
            let f: [UInt8]
            do {
                f = try readFrame(until: deadline,
                                  waitingFor: acked ? "answer from ECU \(ecu)" : "gateway ack")
            } catch TransportError.timeout(let what) {
                throw acked ? DiagError.noResponse(what) : DiagError.noAck(what)
            }
            let (h, p) = try DoIP.parseHeader(f)
            switch h.payloadType {
            case DoIP.PayloadType.diagnosticPositiveAck.rawValue:
                log?.rx("DoIP ack", f)
                acked = true
                deadline = Date().addingTimeInterval(timeouts.response)

            case DoIP.PayloadType.diagnosticNegativeAck.rawValue:
                let nack = try DoIP.parseDiagnosticAck(p)
                log?.rx("DoIP NACK: \(DoIP.diagnosticNackName(nack.code))", f)
                throw DiagError.gateway("diagnostic NACK: " + DoIP.diagnosticNackName(nack.code))

            case DoIP.PayloadType.aliveCheckRequest.rawValue:
                try replyAlive(f)

            case DoIP.PayloadType.diagnosticMessage.rawValue:
                let m = try DoIP.parseDiagnosticMessage(p)
                log?.rx(String(format: "DoIP answer ← 0x%04X", m.source), f)
                guard m.source == target && m.target == tester else {
                    log?.warn("DoIP: message for other addresses ignored")
                    continue
                }
                if UDS.isResponsePending(m.uds, sid: sid) {
                    pending += 1
                    guard pending <= timeouts.maxPending else { throw DiagError.tooManyPending }
                    log?.info("ECU \(ecu) says response pending (\(pending))")
                    deadline = Date().addingTimeInterval(timeouts.pending)
                    continue
                }
                return m.uds

            case DoIP.PayloadType.genericNack.rawValue:
                log?.rx("DoIP generic NACK", f)
                throw DiagError.gateway("generic NACK: " + DoIP.genericNackName(p.first ?? 0xFF))

            default:
                log?.rx(String(format: "DoIP payload 0x%04X (ignored)", h.payloadType), f)
            }
        }
    }

    /// Not built for DoIP: the owner's G30 speaks HSFZ.
    public func requestFunctional(uds: [UInt8]) throws -> [(address: UInt16, answer: [UInt8])] {
        _ = try checkReadOnly(uds)
        throw DiagError.gateway("the all-modules scan is only built for HSFZ cars (yours speaks HSFZ)")
    }

    public func close() {
        stream.close()
        log?.info("DoIP connection closed")
    }
}

// MARK: - Connecting

public enum DiagConnector {
    /// Open TCP to a discovered gateway and return a ready (opened) link.
    public static func connect(host: String, protocolKind: DiagProtocol, port: UInt16? = nil,
                               interface: String? = nil, log: SessionLog? = nil,
                               timeouts: DiagTimeouts = .standard) throws -> DiagLink {
        let p = port ?? protocolKind.tcpPort
        log?.info("Connecting to \(host):\(p) using \(protocolKind.displayName)"
                  + (interface.map { " via \($0)" } ?? ""))
        let stream = try TCPStream.connect(host: host, port: p, interface: interface,
                                           timeout: timeouts.connect)
        log?.info("TCP connected")
        let link: DiagLink = protocolKind == .hsfz
            ? HSFZLink(stream: stream, log: log, timeouts: timeouts)
            : DoIPLink(stream: stream, log: log, timeouts: timeouts)
        do {
            try link.open()
        } catch {
            link.close()
            throw error
        }
        return link
    }
}
