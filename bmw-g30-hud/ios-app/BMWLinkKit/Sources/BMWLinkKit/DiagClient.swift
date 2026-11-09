// SPDX-License-Identifier: MIT
// ReadOnlyDiagClient - orchestrates a safe, read-only session. Mirrors client.py.
import Foundation

public struct VehicleInfo: Equatable, Sendable {
    public var vin: String = ""
    public var entityAddress: UInt16 = 0
    public var ecuName: String = ""
    public var appSoftwareVersion: String = ""
    public var hardwareNumber: String = ""
    public var supplierSoftware: String = ""
    public var serial: String = ""
}

/// Read-only by construction: it only ever calls the read-only UDS builders.
public final class ReadOnlyDiagClient {
    private let transport: Transport
    private let testerAddress: UInt16
    private let targetAddress: UInt16
    private var activated = false

    public init(transport: Transport,
                testerAddress: UInt16 = DoIP.defaultTesterAddress,
                targetAddress: UInt16 = DoIP.headUnitAddress) {
        self.transport = transport
        self.testerAddress = testerAddress
        self.targetAddress = targetAddress
    }

    // MARK: DoIP
    public func identify() throws -> DoIP.VehicleAnnouncement {
        let resp = try transport.request(DoIP.buildVehicleIdentificationRequest())
        let (header, payload) = try DoIP.parseHeader(resp)
        guard header.payloadType == DoIP.PayloadType.vehicleAnnouncement.rawValue else {
            throw DoIP.DoIPError.unexpectedPayloadType(header.payloadType)
        }
        return try DoIP.parseVehicleAnnouncement(payload)
    }

    @discardableResult
    public func activate() throws -> Bool {
        let resp = try transport.request(DoIP.buildRoutingActivationRequest(testerAddress: testerAddress))
        let (header, payload) = try DoIP.parseHeader(resp)
        guard header.payloadType == DoIP.PayloadType.routingActivationResponse.rawValue else {
            throw DoIP.DoIPError.unexpectedPayloadType(header.payloadType)
        }
        let ra = try DoIP.parseRoutingActivationResponse(payload)
        activated = ra.ok
        return ra.ok
    }

    // MARK: UDS (read-only)
    private func udsRoundtrip(_ req: [UInt8]) throws -> [UInt8] {
        let frame = DoIP.buildDiagnosticMessage(source: testerAddress, target: targetAddress, uds: req)
        let resp = try transport.request(frame)
        let (header, payload) = try DoIP.parseHeader(resp)
        if header.payloadType == DoIP.PayloadType.diagnosticNegativeAck.rawValue {
            throw TransportError.notActivated
        }
        guard header.payloadType == DoIP.PayloadType.diagnosticMessage.rawValue else {
            throw DoIP.DoIPError.unexpectedPayloadType(header.payloadType)
        }
        return try DoIP.parseDiagnosticMessage(payload).uds
    }

    public func testerPresent() throws {
        let req = try UDS.buildTesterPresent()
        let resp = try udsRoundtrip(req)
        _ = try UDS.parseResponse(request: req, response: resp)
    }

    public func readDIDRaw(_ did: UInt16) throws -> [UInt8] {
        let req = try UDS.buildReadDataByIdentifier(did)
        let resp = try udsRoundtrip(req)
        let parsed = try UDS.parseResponse(request: req, response: resp)
        if case let .rdbi(r) = parsed { return r.data }
        throw UDS.UDSError.malformed("expected RDBI")
    }

    public func readDTCs(statusMask: UInt8 = 0xFF) throws -> UDS.ReadDTCResponse {
        let req = try UDS.buildReadDTCByStatusMask(statusMask)
        let resp = try udsRoundtrip(req)
        let parsed = try UDS.parseResponse(request: req, response: resp)
        if case let .dtc(r) = parsed { return r }
        throw UDS.UDSError.malformed("expected ReadDTC")
    }

    /// Non-destructive identity sweep for the app's "Identify" screen.
    public func gatherVehicleInfo() throws -> VehicleInfo {
        let ann = try identify()
        var info = VehicleInfo(vin: ann.vin, entityAddress: ann.logicalAddress)
        if !activated { _ = try? activate() }
        func tryAscii(_ did: UInt16) -> String {
            guard let raw = try? readDIDRaw(did) else { return "" }
            return String(bytes: raw, encoding: .ascii)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
        }
        info.ecuName = tryAscii(0xF197)
        info.appSoftwareVersion = tryAscii(0xF195)
        info.hardwareNumber = tryAscii(0xF191)
        info.supplierSoftware = tryAscii(0xF194)
        info.serial = tryAscii(0xF18C)
        return info
    }
}
