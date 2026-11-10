// SPDX-License-Identifier: MIT
// BMW HSFZ ("High Speed Fahrzeug Zugang") framing - the ENET protocol of
// F-series and most G-series BMWs. Facts cross-checked against public
// references (Quantex HSFZ notes, scapy's HSFZ layer, EdiabasLib):
//
//   TCP 6801 = diagnostics, UDP 6811 = vehicle identification (discovery).
//   Frame = length(4, big-endian, bytes AFTER the 6-byte header)
//         + control word(2) + payload.
//   Diagnostic payload = source(1) + target(1) + UDS bytes.
//   No routing activation (unlike DoIP). Tester address 0xF4.
//   Each request is acknowledged with control 0x0002 echoing the start of the
//   request (at most 13 bytes); a bare 0x00FF frame is a NACK (resend once).
//   The gateway may send an alive check (0x0012); answer 0x0013 [0x00, tester].
import Foundation

public enum HSFZ {
    public static let diagPort: UInt16 = 6801
    public static let identPort: UInt16 = 6811
    public static let headerLength = 6
    public static let testerAddress: UInt8 = 0xF4
    /// Largest acknowledgement frame the gateway echoes back (header + 7).
    public static let maxAckLength = 13

    public enum Control: UInt16 {
        case diagnostic = 0x0001
        case ack = 0x0002
        case terminal15 = 0x0010
        case vehicleIdent = 0x0011
        case aliveCheck = 0x0012
        case aliveCheckResponse = 0x0013
        case incorrectTesterAddress = 0x0040
        case incorrectControlWord = 0x0041
        case incorrectFormat = 0x0042
        case incorrectDestination = 0x0043
        case messageTooLarge = 0x0044
        case diagAppNotReady = 0x0045
        case nack = 0x00FF
    }

    public static func controlName(_ c: UInt16) -> String {
        switch Control(rawValue: c) {
        case .diagnostic: return "diagnostic"
        case .ack: return "ack"
        case .terminal15: return "terminal 15"
        case .vehicleIdent: return "vehicle ident"
        case .aliveCheck: return "alive check"
        case .aliveCheckResponse: return "alive check response"
        case .incorrectTesterAddress: return "error: incorrect tester address"
        case .incorrectControlWord: return "error: incorrect control word"
        case .incorrectFormat: return "error: incorrect format"
        case .incorrectDestination: return "error: incorrect destination address"
        case .messageTooLarge: return "error: message too large"
        case .diagAppNotReady: return "error: diagnostic application not ready"
        case .nack: return "nack"
        case .none: return String(format: "control 0x%04X", c)
        }
    }

    public struct Message: Equatable {
        public let control: UInt16
        public let payload: [UInt8]
    }

    public enum HSFZError: Error, Equatable {
        case shortFrame
        case lengthMismatch
    }

    // MARK: framing

    public static func frame(control: UInt16, payload: [UInt8]) -> [UInt8] {
        DoIP.be32(UInt32(payload.count)) + DoIP.be16(control) + payload
    }

    /// Total frame length once the 6 header bytes are available.
    public static func frameLength(header b: [UInt8]) -> Int? {
        guard b.count >= headerLength else { return nil }
        let len = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        return headerLength + len
    }

    public static func parse(_ f: [UInt8]) throws -> Message {
        guard let total = frameLength(header: f) else { throw HSFZError.shortFrame }
        guard f.count == total else { throw HSFZError.lengthMismatch }
        return Message(control: UInt16(f[4]) << 8 | UInt16(f[5]), payload: Array(f[headerLength...]))
    }

    // MARK: builders

    /// UDP 6811 discovery request: empty payload, control 0x0011.
    public static func buildIdentRequest() -> [UInt8] {
        frame(control: Control.vehicleIdent.rawValue, payload: [])
    }

    public static func buildDiagnostic(source: UInt8, target: UInt8, uds: [UInt8]) -> [UInt8] {
        frame(control: Control.diagnostic.rawValue, payload: [source, target] + uds)
    }

    public static func buildAliveCheckResponse(tester: UInt8 = HSFZ.testerAddress) -> [UInt8] {
        frame(control: Control.aliveCheckResponse.rawValue, payload: [0x00, tester])
    }

    /// Does `ack` (an 0x0002 frame) echo the start of `request`?
    public static func ackMatches(_ ack: [UInt8], request: [UInt8]) -> Bool {
        guard ack.count >= headerLength, ack.count <= request.count,
              ack.count <= maxAckLength else { return false }
        // Compare everything after the control word (addresses + first UDS bytes).
        return Array(ack[headerLength...]) == Array(request[headerLength..<ack.count])
    }

    // MARK: discovery reply

    public struct Ident: Equatable {
        public let diagAddress: UInt8
        public let mac: String
        public let vin: String
    }

    /// Parse the ASCII ident reply: "DIAGADR10BMWMAC<12 hex>BMWVIN<17 chars>".
    public static func parseIdentReply(_ frame: [UInt8]) -> Ident? {
        guard frame.count > headerLength,
              let msg = try? parse(frame), msg.control == Control.vehicleIdent.rawValue,
              let text = String(bytes: msg.payload, encoding: .ascii) else { return nil }
        guard let diagRange = text.range(of: "DIAGADR") else { return nil }
        let afterDiag = text[diagRange.upperBound...]
        let addrText = afterDiag.prefix { $0.isHexDigit }
        guard let addr = UInt8(addrText.prefix(2), radix: 16) else { return nil }
        var mac = ""
        if let r = text.range(of: "BMWMAC") {
            mac = String(text[r.upperBound...].prefix(12))
        }
        var vin = ""
        if let r = text.range(of: "BMWVIN") {
            vin = String(text[r.upperBound...].prefix(17))
        }
        return Ident(diagAddress: addr, mac: mac, vin: vin)
    }

    /// The reply a gateway sends to an ident request (used by the mock gateway).
    public static func buildIdentReply(diagAddress: UInt8, mac: String, vin: String) -> [UInt8] {
        let text = "DIAGADR" + String(format: "%02X", diagAddress) + "BMWMAC" + mac + "BMWVIN" + vin
        return frame(control: Control.vehicleIdent.rawValue, payload: Array(text.utf8))
    }
}
