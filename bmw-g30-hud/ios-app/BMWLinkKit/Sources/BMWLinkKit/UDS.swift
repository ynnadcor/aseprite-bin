// SPDX-License-Identifier: MIT
// ISO 14229 (UDS) - READ-ONLY services only. Mirrors proto/bmwdiag/uds.py.
// The read-only guarantee is a property of this type: there is no builder for a
// write/flash/clear/routine service, and `guard(_:)` refuses any such SID.
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
