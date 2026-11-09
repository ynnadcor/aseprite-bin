// SPDX-License-Identifier: MIT
// ISO 13400-2 (DoIP) - read-only subset. Mirrors proto/bmwdiag/doip.py.
import Foundation

public enum DoIP {
    public static let protocolVersion: UInt8 = 0x02
    public static let defaultTesterAddress: UInt16 = 0x0E00
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

    public struct Header {
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

    private static func frame(_ type: PayloadType, _ payload: [UInt8]) -> [UInt8] {
        let v = protocolVersion
        let inv = ~v
        let len = UInt32(payload.count)
        var out: [UInt8] = [v, inv]
        out += be16(type.rawValue)
        out += be32(len)
        out += payload
        return out
    }

    public static func parseHeader(_ data: [UInt8]) throws -> (Header, [UInt8]) {
        guard data.count >= 8 else { throw DoIPError.shortHeader }
        let version = data[0]
        let inv = data[1]
        guard (version ^ inv) == 0xFF else { throw DoIPError.inverseVersionMismatch }
        let ptype = UInt16(data[2]) << 8 | UInt16(data[3])
        let plen = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        let rest = Array(data[8...])
        return (Header(payloadType: ptype, payloadLength: plen, version: version), rest)
    }

    // MARK: request builders (read-only safe)

    public static func buildVehicleIdentificationRequest() -> [UInt8] {
        frame(.vehicleIdRequest, [])
    }

    public static func buildRoutingActivationRequest(
        testerAddress: UInt16 = DoIP.defaultTesterAddress,
        activationType: UInt8 = 0x00
    ) -> [UInt8] {
        var payload = be16(testerAddress)
        payload.append(activationType)
        payload += [0x00, 0x00, 0x00, 0x00]  // reserved
        return frame(.routingActivationRequest, payload)
    }

    public static func buildDiagnosticMessage(
        source: UInt16, target: UInt16, uds: [UInt8]
    ) -> [UInt8] {
        var payload = be16(source) + be16(target)
        payload += uds
        return frame(.diagnosticMessage, payload)
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
        let vinBytes = Array(p[0..<17])
        let vin = String(bytes: vinBytes, encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
        let la = UInt16(p[17]) << 8 | UInt16(p[18])
        return VehicleAnnouncement(
            vin: vin, logicalAddress: la,
            eid: Array(p[19..<25]), gid: Array(p[25..<31]), furtherAction: p[31]
        )
    }

    public struct RoutingActivationResponse: Equatable {
        public let testerAddress: UInt16
        public let entityAddress: UInt16
        public let responseCode: UInt8
        public var ok: Bool { responseCode == DoIP.routingActivationSuccess }
    }

    public static func parseRoutingActivationResponse(_ p: [UInt8]) throws -> RoutingActivationResponse {
        guard p.count >= 5 else { throw DoIPError.shortPayload("routing activation") }
        let tester = UInt16(p[0]) << 8 | UInt16(p[1])
        let entity = UInt16(p[2]) << 8 | UInt16(p[3])
        return RoutingActivationResponse(testerAddress: tester, entityAddress: entity, responseCode: p[4])
    }

    public struct DiagnosticMessage: Equatable {
        public let source: UInt16
        public let target: UInt16
        public let uds: [UInt8]
    }

    public static func parseDiagnosticMessage(_ p: [UInt8]) throws -> DiagnosticMessage {
        guard p.count >= 4 else { throw DoIPError.shortPayload("diagnostic message") }
        let src = UInt16(p[0]) << 8 | UInt16(p[1])
        let tgt = UInt16(p[2]) << 8 | UInt16(p[3])
        return DiagnosticMessage(source: src, target: tgt, uds: Array(p[4...]))
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
