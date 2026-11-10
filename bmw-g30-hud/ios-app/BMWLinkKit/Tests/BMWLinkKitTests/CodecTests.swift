// SPDX-License-Identifier: MIT
// Mirrors tests/test_doip.py + test_uds.py + test_client_mock.py, asserting
// against the SAME test-vectors/doip_uds_vectors.json so Swift and Python stay
// byte-identical on the wire.
import XCTest
@testable import BMWLinkKit

final class CodecTests: XCTestCase {

    // Locate the shared vectors relative to this source file (repo is 5 dirs up).
    func loadVectors() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        url.appendPathComponent("test-vectors/doip_uds_vectors.json")
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func doip() throws -> [String: Any] { try (loadVectors()["doip"] as! [String: Any]) }
    func uds() throws -> [String: Any] { try (loadVectors()["uds"] as! [String: Any]) }

    // MARK: DoIP framing
    func testVehicleIdentificationRequestVector() throws {
        let v = try doip()["vehicle_identification_request"] as! [String: Any]
        XCTAssertEqual(DoIP.buildVehicleIdentificationRequest().hexString, v["frame_hex"] as! String)
    }

    func testRoutingActivationRequestVector() throws {
        let v = try doip()["routing_activation_request_default"] as! [String: Any]
        let tester = UInt16(v["tester_address"] as! Int)
        XCTAssertEqual(DoIP.buildRoutingActivationRequest(testerAddress: tester).hexString,
                       v["frame_hex"] as! String)
    }

    func testDiagnosticMessageVector() throws {
        let v = try doip()["diagnostic_message_tester_present"] as! [String: Any]
        let frame = DoIP.buildDiagnosticMessage(
            source: UInt16(v["source"] as! Int),
            target: UInt16(v["target"] as! Int),
            uds: [UInt8](hex: v["uds_hex"] as! String))
        XCTAssertEqual(frame.hexString, v["frame_hex"] as! String)
    }

    func testBadInverseVersionRejected() {
        var frame = DoIP.buildVehicleIdentificationRequest()
        frame[1] ^= 0xFF
        XCTAssertThrowsError(try DoIP.parseHeader(frame))
    }

    // MARK: UDS builders
    func testBuildRDBIVector() throws {
        let v = try uds()["build_rdbi_vin"] as! [String: Any]
        let did = UInt16(v["did"] as! Int)
        XCTAssertEqual(try UDS.buildReadDataByIdentifier(did).hexString, v["request_hex"] as! String)
    }

    func testBuildReadDTCVector() throws {
        let v = try uds()["build_read_dtc"] as! [String: Any]
        XCTAssertEqual(try UDS.buildReadDTCByStatusMask(UInt8(v["status_mask"] as! Int)).hexString,
                       v["request_hex"] as! String)
    }

    func testBuildTesterPresentVector() throws {
        let v = try uds()["build_tester_present"] as! [String: Any]
        XCTAssertEqual(try UDS.buildTesterPresent(suppressResponse: v["suppress"] as! Bool).hexString,
                       v["request_hex"] as! String)
    }

    func testSessionControlOnlyDefault() throws {
        XCTAssertEqual(try UDS.buildDiagnosticSessionControl(session: 0x01).hexString, "1001")
        XCTAssertThrowsError(try UDS.buildDiagnosticSessionControl(session: 0x03))
        XCTAssertThrowsError(try UDS.buildDiagnosticSessionControl(session: 0x02))
    }

    // MARK: UDS parsing
    func testParseRDBIVin() throws {
        let v = try uds()["parse_rdbi_vin"] as! [String: Any]
        let parsed = try UDS.parseResponse(request: [UInt8](hex: v["request_hex"] as! String),
                                           response: [UInt8](hex: v["response_hex"] as! String))
        guard case let .rdbi(r) = parsed else { return XCTFail("expected rdbi") }
        XCTAssertEqual(Int(r.did), v["expect_did"] as! Int)
        let expectedVin = v["expect_ascii"] as! String
        XCTAssertEqual(String(bytes: r.data, encoding: .ascii), expectedVin)
    }

    func testParseReadDTC() throws {
        let v = try uds()["parse_read_dtc"] as! [String: Any]
        let parsed = try UDS.parseResponse(request: [UInt8](hex: v["request_hex"] as! String),
                                           response: [UInt8](hex: v["response_hex"] as! String))
        guard case let .dtc(r) = parsed else { return XCTFail("expected dtc") }
        let expected = v["expect_records"] as! [[String: Any]]
        XCTAssertEqual(r.records.count, expected.count)
        XCTAssertEqual(r.records[0].code, expected[0]["dtc"] as! String)
        XCTAssertEqual(Int(r.records[0].status), expected[0]["status"] as! Int)
    }

    func testParseNegativeResponseThrows() throws {
        let v = try uds()["parse_negative_response"] as! [String: Any]
        let request = [UInt8](hex: v["request_hex"] as! String)
        let response = [UInt8](hex: v["response_hex"] as! String)
        XCTAssertThrowsError(try UDS.parseResponse(request: request, response: response)) { err in
            guard let udsErr = err as? UDS.UDSError,
                  case let .negativeResponse(sid, nrc) = udsErr else {
                return XCTFail("wrong error \(err)")
            }
            XCTAssertEqual(Int(sid), v["expect_request_sid"] as! Int)
            XCTAssertEqual(Int(nrc), v["expect_nrc"] as! Int)
        }
    }

    // MARK: read-only enforcement
    func testBlockedServicesRefuse() throws {
        let blocked = try loadVectors()["blocked_services_must_refuse"] as! [String]
        for hex in blocked {
            let sid = UInt8(hex.replacingOccurrences(of: "0x", with: ""), radix: 16)!
            XCTAssertThrowsError(try UDS.assertReadOnly(sid), "SID \(hex) should be blocked")
        }
    }

    func testAllowedServicesExactlyReadOnly() {
        XCTAssertEqual(UDS.allowedServices, [0x10, 0x3E, 0x19, 0x22])
    }

    // MARK: client against mock
    func testClientAgainstMock() throws {
        let vin = "WBAJE7C50JWA00000"
        let server = MockEnetServer(vin: vin)
        let client = ReadOnlyDiagClient(transport: server, targetAddress: DoIP.zgwAddress)

        XCTAssertEqual(try client.identify().vin, vin)
        // diag before activation must fail
        XCTAssertThrowsError(try client.readDIDRaw(0xF190))
        XCTAssertTrue(try client.activate())
        let vinRaw = try client.readDIDRaw(0xF190)
        XCTAssertEqual(String(bytes: vinRaw, encoding: .ascii), vin)

        let info = try client.gatherVehicleInfo()
        XCTAssertEqual(info.ecuName, "HeadUnitHigh2")
        XCTAssertEqual(info.appSoftwareVersion, "NBTevo_Y24073J")

        let dtcs = try client.readDTCs()
        XCTAssertEqual(dtcs.records.first?.code, "0x4B1C00")
    }

    func testUnknownDIDIsNegativeResponse() throws {
        let client = ReadOnlyDiagClient(transport: MockEnetServer(), targetAddress: DoIP.zgwAddress)
        try client.activate()
        XCTAssertThrowsError(try client.readDIDRaw(0x1234)) { err in
            guard let udsErr = err as? UDS.UDSError,
                  case let .negativeResponse(_, nrc) = udsErr else {
                return XCTFail("wrong error \(err)")
            }
            XCTAssertEqual(nrc, 0x31)  // requestOutOfRange
        }
    }

    func testCandidateLiveValuesDecodeButStayUnverified() throws {
        let client = ReadOnlyDiagClient(transport: MockEnetServer(), targetAddress: DoIP.zgwAddress)
        try client.activate()
        let raw = try client.readDIDRaw(0xDD03)
        let meta = try XCTUnwrap(DIDCatalogue.lookup(0xDD03))
        XCTAssertEqual(meta.decode?(raw), "104")
        XCTAssertFalse(meta.verified)
    }

    func testHexHelperIgnoresTrailingNibble() {
        XCTAssertEqual([UInt8](hex: "0a0b0"), [0x0A, 0x0B])
        XCTAssertEqual([UInt8](hex: ""), [])
    }
}
