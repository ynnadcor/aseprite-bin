// SPDX-License-Identifier: MIT
// ISO 13400-2 (DoIP) framing - the read-only subset. Mirrors proto/bmwdiag/doip.py.
//
// BMW notes (from the open-source EdiabasLib ENET implementation, used as a
// reference for facts only): BMW tools speak DoIP protocol version 0x03
// (ISO 13400-2:2019), use tester logical address 0x0EF3, the central gateway
// is 0x0010, and the routing activation carries the 4 OEM-specific bytes.
// Older BMWs (F-series, most G-series) use HSFZ instead - see HSFZ.swift.
import Foundation

public enum DoIP {
    /// Version used by the generic builders and the shared golden vectors.
    public static let protocolVersion: UInt8 = 0x02
    /// Version BMW diagnostic tools use.
    public static let bmwProtocolVersion: UInt8 = 0x03
    public static let port: UInt16 = 13400

    public static let defaultTesterAddress: UInt16 = 0x0E00
    public static let bmwTesterAddress: UInt16 = 0x0EF3
    public static let zgwAddress: UInt16 = 0x0010
    public static let headUnitAddress: UInt16 = 0x0063

    public enum PayloadType: UInt16 {
        case genericNack = 0x0000
        case vehicleIdRequest = 0x0001
        case vehicleAnnouncement = 0x0004
        case routingActivationRequest = 0x0005
        case routingActivationResponse = 0x0006
        case aliveCheckRequest = 0x0007
        case aliveCheckResponse = 0x0008
        case diagnosticMessage = 0x8001
        case diagnosticPositiveAck = 0x8002
        case diagnosticNegativeAck = 0x8003
    }

    public static let routingActivationSuccess: UInt8 = 0x10
    public static let headerLength = 8

    public struct Header: Equatable {
        public let payloadType: UInt16
        public let payloadLength: UInt32
        public let version: UInt8
        public init(payloadType: UInt16, payloadLength: UInt32, version: UInt8 = DoIP.protocolVersion) {
            self.payloadType = payloadType
            self.payloadLength = payloadLength
            self.version = version
        }
    }

    public enum DoIPError: Error, Equatable {
        case shortHeader
        case inverseVersionMismatch
        case shortPayload(String)
        case unexpectedPayloadType(UInt16)
    }

    // MARK: framing

    public static func frame(_ type: PayloadType, _ payload: [UInt8],
                             version: UInt8 = DoIP.protocolVersion) -> [UInt8] {
        var out: [UInt8] = [version, ~version]
        out += be16(type.rawValue)
        out += be32(UInt32(payload.count))
        out += payload
        return out
    }

    /// Total frame length (header + payload) once 8 header bytes are available.
    public static func frameLength(header b: [UInt8]) -> Int? {
        guard b.count >= headerLength else { return nil }
        let len = Int(b[4]) << 24 | Int(b[5]) << 16 | Int(b[6]) << 8 | Int(b[7])
        return headerLength + len
    }

    public static func parseHeader(_ data: [UInt8]) throws -> (Header, [UInt8]) {
        guard data.count >= headerLength else { throw DoIPError.shortHeader }
        let version = data[0]
        guard (version ^ data[1]) == 0xFF else { throw DoIPError.inverseVersionMismatch }
        let ptype = UInt16(data[2]) << 8 | UInt16(data[3])
        let plen = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        return (Header(payloadType: ptype, payloadLength: plen, version: version),
                Array(data[headerLength...]))
    }

    // MARK: request builders (read-only safe)

    public static func buildVehicleIdentificationRequest(version: UInt8 = DoIP.protocolVersion) -> [UInt8] {
        frame(.vehicleIdRequest, [], version: version)
    }

    /// Routing activation. `oemSpecific` (4 bytes) is optional per ISO 13400;
    /// BMW tools send it as zeros.
    public static func buildRoutingActivationRequest(
        testerAddress: UInt16 = DoIP.defaultTesterAddress,
        activationType: UInt8 = 0x00,
        oemSpecific: [UInt8]? = nil,
        version: UInt8 = DoIP.protocolVersion
    ) -> [UInt8] {
        var payload = be16(testerAddress)
        payload.append(activationType)
        payload += [0x00, 0x00, 0x00, 0x00]  // ISO reserved
        if let oem = oemSpecific { payload += Array(oem.prefix(4)) + [UInt8](repeating: 0, count: max(0, 4 - oem.count)) }
        return frame(.routingActivationRequest, payload, version: version)
    }

    public static func buildDiagnosticMessage(source: UInt16, target: UInt16, uds: [UInt8],
                                              version: UInt8 = DoIP.protocolVersion) -> [UInt8] {
        frame(.diagnosticMessage, be16(source) + be16(target) + uds, version: version)
    }

    /// Reply to the gateway's alive check so it keeps our connection open.
    public static func buildAliveCheckResponse(sourceAddress: UInt16,
                                               version: UInt8 = DoIP.protocolVersion) -> [UInt8] {
        frame(.aliveCheckResponse, be16(sourceAddress), version: version)
    }

    // MARK: response parsers

    public struct VehicleAnnouncement: Equatable {
        public let vin: String
        public let logicalAddress: UInt16
        public let eid: [UInt8]
        public let gid: [UInt8]
        public let furtherAction: UInt8
    }

    public static func parseVehicleAnnouncement(_ p: [UInt8]) throws -> VehicleAnnouncement {
        guard p.count >= 17 + 2 + 6 + 6 + 1 else { throw DoIPError.shortPayload("announcement") }
        let vin = String(bytes: p[0..<17], encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
        let la = UInt16(p[17]) << 8 | UInt16(p[18])
        return VehicleAnnouncement(vin: vin, logicalAddress: la, eid: Array(p[19..<25]),
                                   gid: Array(p[25..<31]), furtherAction: p[31])
    }

    public struct RoutingActivationResponse: Equatable {
        public let testerAddress: UInt16
        public let entityAddress: UInt16
        public let responseCode: UInt8
        public var ok: Bool { responseCode == DoIP.routingActivationSuccess }
    }

    public static func parseRoutingActivationResponse(_ p: [UInt8]) throws -> RoutingActivationResponse {
        guard p.count >= 5 else { throw DoIPError.shortPayload("routing activation") }
        return RoutingActivationResponse(testerAddress: UInt16(p[0]) << 8 | UInt16(p[1]),
                                         entityAddress: UInt16(p[2]) << 8 | UInt16(p[3]),
                                         responseCode: p[4])
    }

    public struct DiagnosticMessage: Equatable {
        public let source: UInt16
        public let target: UInt16
        public let uds: [UInt8]
    }

    public static func parseDiagnosticMessage(_ p: [UInt8]) throws -> DiagnosticMessage {
        guard p.count >= 4 else { throw DoIPError.shortPayload("diagnostic message") }
        return DiagnosticMessage(source: UInt16(p[0]) << 8 | UInt16(p[1]),
                                 target: UInt16(p[2]) << 8 | UInt16(p[3]),
                                 uds: Array(p[4...]))
    }

    /// 0x8002 / 0x8003 payload: source(2) target(2) code(1) [echo of request...]
    public struct DiagnosticAck: Equatable {
        public let source: UInt16
        public let target: UInt16
        public let code: UInt8
    }

    public static func parseDiagnosticAck(_ p: [UInt8]) throws -> DiagnosticAck {
        guard p.count >= 5 else { throw DoIPError.shortPayload("diagnostic ack") }
        return DiagnosticAck(source: UInt16(p[0]) << 8 | UInt16(p[1]),
                             target: UInt16(p[2]) << 8 | UInt16(p[3]), code: p[4])
    }

    public static func genericNackName(_ code: UInt8) -> String {
        switch code {
        case 0x00: return "incorrect pattern format"
        case 0x01: return "unknown payload type"
        case 0x02: return "message too large"
        case 0x03: return "out of memory"
        case 0x04: return "invalid payload length"
        default: return String(format: "code 0x%02X", code)
        }
    }

    public static func diagnosticNackName(_ code: UInt8) -> String {
        switch code {
        case 0x02: return "invalid source address"
        case 0x03: return "unknown target address"
        case 0x04: return "message too large"
        case 0x05: return "out of memory"
        case 0x06: return "target unreachable"
        case 0x07: return "unknown network"
        case 0x08: return "transport protocol error"
        default: return String(format: "code 0x%02X", code)
        }
    }

    public static func routingResponseName(_ code: UInt8) -> String {
        switch code {
        case 0x00: return "denied: unknown source address"
        case 0x01: return "denied: all sockets in use"
        case 0x02: return "denied: source address mismatch"
        case 0x03: return "denied: source address already active"
        case 0x04: return "denied: missing authentication"
        case 0x05: return "denied: rejected confirmation"
        case 0x06: return "denied: unsupported activation type"
        case 0x10: return "success"
        case 0x11: return "success, confirmation required"
        default: return String(format: "code 0x%02X", code)
        }
    }

    // MARK: helpers
    static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
}

public extension Array where Element == UInt8 {
    /// lowercase hex, for comparing against the shared test vectors
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    /// Uppercase, space-separated - for logs.
    var spacedHex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }

    /// Parse lowercase/uppercase hex. Stops at a trailing odd nibble instead of crashing.
    init(hex: String) {
        var out = [UInt8]()
        var idx = hex.startIndex
        while idx < hex.endIndex,
              let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) {
            out.append(UInt8(hex[idx..<next], radix: 16) ?? 0)
            idx = next
        }
        self = out
    }
}
