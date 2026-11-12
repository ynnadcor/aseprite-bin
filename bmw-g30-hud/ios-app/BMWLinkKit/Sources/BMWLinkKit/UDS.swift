// SPDX-License-Identifier: MIT
// ISO 14229 (UDS) - READ-ONLY services only, plus the legislated OBD-II reads
// (SAE J1979). Mirrors proto/bmwdiag/uds.py.
// The read-only guarantee is a property of this type: there is no builder for a
// write/flash/clear/routine service, and `guard(_:)` refuses any such SID.
// Still refused: UDS 0x14 (clear codes), OBD 0x04 (clear codes), OBD 0x08
// (control of on-board systems), and every write, routine or flash service.
import Foundation

public enum UDS {
    public enum Service: UInt8 {
        case diagnosticSessionControl = 0x10  // only default session (0x01) permitted
        case testerPresent = 0x3E
        case readDTCInformation = 0x19
        case readDataByIdentifier = 0x22
    }

    public static let allowedServices: Set<UInt8> = [
        Service.diagnosticSessionControl.rawValue,
        Service.testerPresent.rawValue,
        Service.readDTCInformation.rawValue,
        Service.readDataByIdentifier.rawValue,
        OBD.Service.currentData.rawValue,
        OBD.Service.storedCodes.rawValue,
        OBD.Service.pendingCodes.rawValue,
        OBD.Service.permanentCodes.rawValue,
    ]

    public static let defaultSession: UInt8 = 0x01
    public static let positiveOffset: UInt8 = 0x40
    public static let negativeResponseSID: UInt8 = 0x7F

    public enum UDSError: Error, Equatable {
        case blockedService(UInt8)          // attempted a non-read-only service
        case invalidSession(UInt8)
        case empty
        case malformed(String)
        case unexpectedSID(got: UInt8, want: UInt8)
        case negativeResponse(requestSID: UInt8, nrc: UInt8)
    }

    private static func guardService(_ sid: UInt8) throws {
        guard allowedServices.contains(sid) else { throw UDSError.blockedService(sid) }
    }

    // MARK: builders

    public static func buildDiagnosticSessionControl(session: UInt8 = defaultSession) throws -> [UInt8] {
        try guardService(Service.diagnosticSessionControl.rawValue)
        guard session == defaultSession else { throw UDSError.invalidSession(session) }
        return [Service.diagnosticSessionControl.rawValue, session]
    }

    public static func buildTesterPresent(suppressResponse: Bool = false) throws -> [UInt8] {
        try guardService(Service.testerPresent.rawValue)
        return [Service.testerPresent.rawValue, suppressResponse ? 0x80 : 0x00]
    }

    public static func buildReadDataByIdentifier(_ did: UInt16) throws -> [UInt8] {
        try guardService(Service.readDataByIdentifier.rawValue)
        return [Service.readDataByIdentifier.rawValue, UInt8(did >> 8), UInt8(did & 0xFF)]
    }

    public static func buildReadDTCByStatusMask(_ mask: UInt8 = 0xFF) throws -> [UInt8] {
        try guardService(Service.readDTCInformation.rawValue)
        return [Service.readDTCInformation.rawValue, 0x02, mask]
    }

    /// Exposed for tests mirroring the Python `_guard`.
    public static func assertReadOnly(_ sid: UInt8) throws { try guardService(sid) }

    /// `7F <sid> 78` - "request correctly received, response pending".
    public static func isResponsePending(_ response: [UInt8], sid: UInt8) -> Bool {
        response.count >= 3 && response[0] == negativeResponseSID && response[1] == sid
            && response[2] == 0x78
    }

    /// Human-readable negative response code.
    public static func nrcName(_ code: UInt8) -> String {
        switch code {
        case 0x10: return "general reject"
        case 0x11: return "service not supported"
        case 0x12: return "sub-function not supported"
        case 0x13: return "incorrect message length or format"
        case 0x14: return "response too long"
        case 0x21: return "busy, repeat request"
        case 0x22: return "conditions not correct"
        case 0x24: return "request sequence error"
        case 0x31: return "request out of range (not supported by this ECU)"
        case 0x33: return "security access denied"
        case 0x78: return "response pending"
        case 0x7E: return "sub-function not supported in active session"
        case 0x7F: return "service not supported in active session"
        default: return String(format: "NRC 0x%02X", code)
        }
    }

    // MARK: parsing

    public struct RDBIResponse: Equatable {
        public let did: UInt16
        public let data: [UInt8]
    }

    public struct DTCRecord: Equatable {
        public let dtc: UInt32
        public let status: UInt8
        public var code: String { String(format: "0x%06X", dtc) }
    }

    public struct ReadDTCResponse: Equatable {
        public let availabilityMask: UInt8
        public let records: [DTCRecord]
    }

    public enum ParsedResponse: Equatable {
        case rdbi(RDBIResponse)
        case dtc(ReadDTCResponse)
        case raw([UInt8])
    }

    public static func parseResponse(request: [UInt8], response: [UInt8]) throws -> ParsedResponse {
        guard let first = response.first else { throw UDSError.empty }
        let reqSID = request.first ?? 0

        if first == negativeResponseSID {
            guard response.count >= 3 else { throw UDSError.malformed("negative response") }
            throw UDSError.negativeResponse(requestSID: response[1], nrc: response[2])
        }

        let expected = reqSID &+ positiveOffset
        guard first == expected else { throw UDSError.unexpectedSID(got: first, want: expected) }

        switch reqSID {
        case Service.readDataByIdentifier.rawValue:
            guard response.count >= 3 else { throw UDSError.malformed("short RDBI") }
            let did = UInt16(response[1]) << 8 | UInt16(response[2])
            return .rdbi(RDBIResponse(did: did, data: Array(response[3...])))
        case Service.readDTCInformation.rawValue:
            guard response.count >= 3 else { throw UDSError.malformed("short ReadDTC") }
            let avail = response[2]
            let body = Array(response[3...])
            var records: [DTCRecord] = []
            var i = 0
            while i + 4 <= body.count {
                let dtc = UInt32(body[i]) << 16 | UInt32(body[i + 1]) << 8 | UInt32(body[i + 2])
                records.append(DTCRecord(dtc: dtc, status: body[i + 3]))
                i += 4
            }
            return .dtc(ReadDTCResponse(availabilityMask: avail, records: records))
        default:
            return .raw(response)
        }
    }
}

/// The legislated OBD-II reads (SAE J1979 / ISO 15031-5) that every generic
/// scanner sends. Only reads: clearing codes (0x04) and controlling on-board
/// systems (0x08) are not here and are refused like any other non-read.
public enum OBD {
    public enum Service: UInt8, CaseIterable, Sendable {
        case currentData = 0x01     // mode 01; PID 01 = engine light + readiness
        case storedCodes = 0x03     // mode 03: confirmed emission-related codes
        case pendingCodes = 0x07    // mode 07
        case permanentCodes = 0x0A  // mode 0A
    }

    public static func buildRequest(_ service: Service, pid: UInt8? = nil) throws -> [UInt8] {
        try UDS.assertReadOnly(service.rawValue)
        if service == .currentData {
            guard let pid else { throw UDS.UDSError.malformed("mode 01 needs a PID") }
            return [service.rawValue, pid]
        }
        return [service.rawValue]
    }

    /// Two OBD bytes -> SAE J2012 code: 0x01 0x71 -> "P0171".
    public static func saeCode(_ hi: UInt8, _ lo: UInt8) -> String {
        let letter = ["P", "C", "B", "U"][Int(hi >> 6)]
        return letter + String((hi >> 4) & 0x3) + String(format: "%X%02X", hi & 0xF, lo)
    }

    /// "P0171" -> (0x01, 0x71); nil when it isn't an SAE code.
    public static func saeBytes(_ code: String) -> (UInt8, UInt8)? {
        let c = Array(code.uppercased())
        let letters: [Character] = ["P", "C", "B", "U"]
        guard c.count == 5, let l = letters.firstIndex(of: c[0]),
              let d1 = c[1].wholeNumberValue, d1 <= 3,
              c[2...].allSatisfy({ $0.isHexDigit }),
              let rest = UInt16(String(c[2...]), radix: 16) else { return nil }
        return (UInt8(l << 6 | d1 << 4) | UInt8(rest >> 8), UInt8(rest & 0xFF))
    }

    /// Codes from a mode 03/07/0A answer. On CAN the answer has a count byte
    /// after the SID; older protocols pad with 00 00 instead. Both are accepted.
    public static func parseCodes(request: [UInt8], response: [UInt8]) throws -> [String] {
        guard let first = response.first else { throw UDS.UDSError.empty }
        let sid = request.first ?? 0
        if first == UDS.negativeResponseSID {
            guard response.count >= 3 else { throw UDS.UDSError.malformed("negative response") }
            throw UDS.UDSError.negativeResponse(requestSID: response[1], nrc: response[2])
        }
        guard first == sid &+ UDS.positiveOffset else {
            throw UDS.UDSError.unexpectedSID(got: first, want: sid &+ UDS.positiveOffset)
        }
        let body = Array(response.dropFirst())
        let pairs: [UInt8]
        if let n = body.first, body.count == 1 + 2 * Int(n) {
            pairs = Array(body.dropFirst())
        } else if body.count % 2 == 0 {
            pairs = body
        } else {
            throw UDS.UDSError.malformed("OBD code list has an odd length")
        }
        var codes: [String] = []
        var i = 0
        while i + 1 < pairs.count {
            if pairs[i] != 0 || pairs[i + 1] != 0 { codes.append(saeCode(pairs[i], pairs[i + 1])) }
            i += 2
        }
        return codes
    }
}
