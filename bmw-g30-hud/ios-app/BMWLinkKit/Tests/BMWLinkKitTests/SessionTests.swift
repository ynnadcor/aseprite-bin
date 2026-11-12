// SPDX-License-Identifier: MIT
// HSFZ/DoIP links against a simulated gateway that behaves like a real one:
// acks, NACK + resend, alive checks, response pending, silent ECUs, split reads.
import XCTest
@testable import BMWLinkKit

private func loadVectors() throws -> [String: Any] {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    url.appendPathComponent("test-vectors/doip_uds_vectors.json")
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
}

private let syntheticVIN = "WBAJE7C50JWA00000"   // test data, not a real vehicle
private let fast = DiagTimeouts.uniform(0.2)

final class HSFZFramingTests: XCTestCase {
    func testSharedVectors() throws {
        let h = try loadVectors()["hsfz"] as! [String: Any]
        XCTAssertEqual(HSFZ.buildIdentRequest().hexString, h["ident_request_hex"] as! String)

        let d = h["diagnostic_rdbi_vin"] as! [String: Any]
        let frame = HSFZ.buildDiagnostic(source: UInt8(d["source"] as! Int), target: UInt8(d["target"] as! Int),
                                         uds: [UInt8](hex: d["uds_hex"] as! String))
        XCTAssertEqual(frame.hexString, d["frame_hex"] as! String)

        let ack = [UInt8](hex: h["ack_for_rdbi_vin_hex"] as! String)
        XCTAssertTrue(HSFZ.ackMatches(ack, request: frame))
        XCTAssertEqual(HSFZ.buildAliveCheckResponse().hexString, h["alive_check_response_hex"] as! String)

        let r = h["ident_reply"] as! [String: Any]
        let reply = HSFZ.buildIdentReply(diagAddress: UInt8(r["diag_address"] as! Int),
                                         mac: r["mac"] as! String, vin: r["vin"] as! String)
        XCTAssertEqual(reply.hexString, r["frame_hex"] as! String)
        XCTAssertEqual(HSFZ.parseIdentReply(reply),
                       HSFZ.Ident(diagAddress: 0x10, mac: r["mac"] as! String, vin: r["vin"] as! String))
    }

    func testBMWDoIPVectors() throws {
        let d = try loadVectors()["doip_bmw"] as! [String: Any]
        XCTAssertEqual(DoIP.buildRoutingActivationRequest(testerAddress: DoIP.bmwTesterAddress,
                                                          oemSpecific: [0, 0, 0, 0],
                                                          version: DoIP.bmwProtocolVersion).hexString,
                       d["routing_activation_hex"] as! String)
        XCTAssertEqual(DoIP.buildVehicleIdentificationRequest(version: 3).hexString,
                       d["vehicle_identification_request_hex"] as! String)
        XCTAssertEqual(DoIP.buildAliveCheckResponse(sourceAddress: 0x0EF3, version: 3).hexString,
                       d["alive_check_response_hex"] as! String)
    }

    func testFrameReaderHandlesSplitAndMergedFrames() throws {
        let a = HSFZ.buildDiagnostic(source: 0x10, target: 0xF4, uds: [0x62, 0xF1, 0x90, 1, 2, 3])
        let b = HSFZ.frame(control: HSFZ.Control.aliveCheck.rawValue, payload: [])
        var reader = FrameReader(format: .hsfz)
        // a arrives one byte at a time
        for (i, byte) in a.enumerated() {
            reader.append([byte])
            let f = try reader.nextFrame()
            XCTAssertEqual(f != nil, i == a.count - 1)
            if let f = f { XCTAssertEqual(f, a) }
        }
        // b and a merged in one read
        reader.append(b + a)
        XCTAssertEqual(try reader.nextFrame(), b)
        XCTAssertEqual(try reader.nextFrame(), a)
        XCTAssertNil(try reader.nextFrame())
    }

    func testFrameReaderRejectsAbsurdLengthAndBadDoIPHeader() {
        var r = FrameReader(format: .hsfz, maxFrameBytes: 100)
        r.append([0x7F, 0xFF, 0xFF, 0xFF, 0x00, 0x01])
        XCTAssertThrowsError(try r.nextFrame())
        var d = FrameReader(format: .doip)
        d.append([0x03, 0x03, 0x80, 0x01])   // inverse version byte wrong
        XCTAssertThrowsError(try d.nextFrame())
    }

    func testIdentReplyParsingIsRobust() {
        XCTAssertNil(HSFZ.parseIdentReply([0, 0, 0, 0, 0, 0x11]))
        XCTAssertNil(HSFZ.parseIdentReply(HSFZ.frame(control: 0x11, payload: Array("hello".utf8))))
        let noVIN = HSFZ.frame(control: 0x11, payload: Array("DIAGADR10BMWMAC001A37C0FFEE".utf8))
        XCTAssertEqual(HSFZ.parseIdentReply(noVIN)?.vin, "")
    }
}

final class LinkTests: XCTestCase {

    func link(_ kind: DiagProtocol, _ behavior: MockGateway.Behavior = MockGateway.Behavior(),
              chunk: Int = 4096) -> (DiagLink, MockGateway) {
        let gw = MockGateway(kind: kind, vin: syntheticVIN, behavior: behavior)
        let stream = MockGatewayStream(gateway: gw, chunkSize: chunk)
        let l: DiagLink = kind == .hsfz
            ? HSFZLink(stream: stream, timeouts: fast)
            : DoIPLink(stream: stream, timeouts: fast)
        return (l, gw)
    }

    func testReadVINOverBothProtocols() throws {
        for kind in DiagProtocol.allCases {
            let (l, _) = link(kind)
            try l.open()
            let client = ReadOnlyDiagClient(link: l)
            XCTAssertEqual(String(bytes: try client.readDID(0xF190, target: 0x10), encoding: .ascii),
                           syntheticVIN, "\(kind)")
        }
    }

    func testAcksAliveChecksPendingAndSplitReads() throws {
        var b = MockGateway.Behavior()
        b.aliveCheckBeforeAnswer = true
        b.responsePending = 3
        for kind in DiagProtocol.allCases {
            let (l, gw) = link(kind, b, chunk: 1)   // every byte arrives separately
            try l.open()
            let data = try ReadOnlyDiagClient(link: l).readDID(0xF190, target: 0x63)
            XCTAssertEqual(String(bytes: data, encoding: .ascii), syntheticVIN, "\(kind)")
            XCTAssertEqual(gw.aliveResponsesSeen, 1, "\(kind): must answer the alive check")
        }
    }

    func testHSFZResendsOnceAfterNACK() throws {
        var b = MockGateway.Behavior()
        b.nackFirstRequest = true
        let (l, gw) = link(.hsfz, b)
        let data = try ReadOnlyDiagClient(link: l).readDID(0xF190, target: 0x10)
        XCTAssertEqual(data.count, 17)
        XCTAssertEqual(gw.udsRequestsSeen.count, 1)   // the NACKed one isn't counted
    }

    func testSilentECUTimesOutWithNoResponseError() throws {
        for kind in DiagProtocol.allCases {
            let (l, _) = link(kind)
            try l.open()
            XCTAssertThrowsError(try ReadOnlyDiagClient(link: l).readDID(0xF150, target: 0x3D)) { e in
                guard case DiagError.noResponse = e else { return XCTFail("\(kind): got \(e)") }
            }
        }
    }

    func testUnsupportedDIDIsANegativeAnswer() throws {
        let (l, _) = link(.hsfz)
        XCTAssertThrowsError(try ReadOnlyDiagClient(link: l).readDID(0x1234, target: 0x10)) { e in
            guard case let UDS.UDSError.negativeResponse(_, nrc) = e else { return XCTFail("got \(e)") }
            XCTAssertEqual(nrc, 0x31)
        }
    }

    func testLinksRefuseNonReadOnlyServices() throws {
        // Even if someone bypassed the UDS builders, the links won't send writes.
        for kind in DiagProtocol.allCases {
            let (l, gw) = link(kind)
            try l.open()
            for sid: UInt8 in [0x2E, 0x14, 0x31, 0x11, 0x27, 0x34, 0x10 + 0x00] where sid != 0x10 {
                XCTAssertThrowsError(try l.request(target: 0x10, uds: [sid, 0x01, 0x02])) { e in
                    XCTAssertEqual(e as? DiagError, .notReadOnly(sid))
                }
            }
            XCTAssertTrue(gw.udsRequestsSeen.isEmpty, "\(kind): nothing may reach the car")
        }
    }

    func testDoIPRequiresAndPerformsRoutingActivation() throws {
        let gw = MockGateway(kind: .doip, vin: syntheticVIN)
        let l = DoIPLink(stream: MockGatewayStream(gateway: gw), timeouts: fast)
        XCTAssertFalse(l.activated)
        // request() activates on demand
        _ = try ReadOnlyDiagClient(link: l).readDID(0xF190, target: 0x10)
        XCTAssertTrue(l.activated)
    }

    func testIdentifyReportOverMock() throws {
        let log = SessionLog()
        for kind in DiagProtocol.allCases {
            let (l, _) = link(kind)
            try l.open()
            let report = ReadOnlyDiagClient(link: l, log: log).runIdentify(plan: .g30, host: "sim")
            XCTAssertEqual(report.vin, syntheticVIN)
            XCTAssertEqual(report.protocolKind, kind)
            // HUD (0x3D) is silent in the mock: first read fails, second is skipped.
            let hud = report.items.filter { $0.address == 0x3D }
            XCTAssertEqual(hud.count, 2)
            if case .failed = hud[0].outcome {} else { XCTFail("HUD first read should fail") }
            if case .skipped = hud[1].outcome {} else { XCTFail("HUD second read should be skipped") }
            // Head unit fault codes were read.
            XCTAssertTrue(report.items.contains { $0.address == 0x63 && $0.label.hasPrefix("Fault codes")
                && $0.outcome == .value("1 fault(s): 4B1C00 (stored); 2 other entries not tested yet") })
            XCTAssertTrue(report.items.contains { $0.address == 0x63 && $0.label == "BMW software list, SVK (F101)"
                && $0.outcome == .value("programmed 2024-01-15; 4 parts; software 7.1.0; coding 2.0.9") })
            XCTAssertEqual(report.serials, ["SIM-HU-0001"])
            XCTAssertGreaterThan(report.answeredCount, 6)
        }
        XCTAssertFalse(log.all.isEmpty)
    }
}

final class SessionLogTests: XCTestCase {
    func testExportRedactsVINAndMACInTextAndHex() {
        let log = SessionLog()
        let mac = "001A37C0FFEE"
        log.info("Found gateway, VIN \(syntheticVIN), MAC \(mac)")
        log.rx("HSFZ ident", HSFZ.buildIdentReply(diagAddress: 0x10, mac: mac, vin: syntheticVIN))
        let out = log.export(header: ["BMW Link test log"],
                             secrets: [LogRedactor.vin(syntheticVIN), LogRedactor.mac(mac)])
        // ASCII forms
        XCTAssertFalse(out.contains(syntheticVIN))
        XCTAssertFalse(out.contains(mac))
        XCTAssertTrue(out.contains("WBA**************"))
        XCTAssertTrue(out.contains("001A37******"))
        // hex-dump forms ("57 42 41 ..."), keeping only the non-identifying prefix
        XCTAssertFalse(out.contains(Array(syntheticVIN.utf8).spacedHex))
        XCTAssertFalse(out.contains(Array(mac.utf8).spacedHex))
        XCTAssertTrue(out.contains("57 42 41 ** ** **"))
        XCTAssertTrue(out.contains("30 30 31 41 33 37 ** ** ** ** ** **"))
        XCTAssertTrue(out.hasPrefix("BMW Link test log"))
    }

    func testShortVIN() {
        XCTAssertEqual(LogRedactor.shortVIN(syntheticVIN), "WBA…0000")
        XCTAssertEqual(LogRedactor.shortVIN("short"), "short")
    }
}

final class DiscoveryParsingTests: XCTestCase {
    func testParseRepliesByPort() {
        let hs = HSFZ.buildIdentReply(diagAddress: 0x10, mac: "001A37C0FFEE", vin: syntheticVIN)
        let gw = GatewayDiscovery.parseReply(hs, host: "169.254.10.20", port: 6811)
        XCTAssertEqual(gw, DiscoveredGateway(host: "169.254.10.20", protocolKind: .hsfz, vin: syntheticVIN,
                                             mac: "001A37C0FFEE", logicalAddress: 0x10))
        // The same bytes from an unexpected port are ignored.
        XCTAssertNil(GatewayDiscovery.parseReply(hs, host: "169.254.10.20", port: 9999))

        let doip = MockGateway(kind: .doip, vin: syntheticVIN)
            .identReply(to: DoIP.buildVehicleIdentificationRequest(version: 3))!
        let d = GatewayDiscovery.parseReply(doip, host: "169.254.1.2", port: 13400)
        XCTAssertEqual(d?.protocolKind, .doip)
        XCTAssertEqual(d?.vin, syntheticVIN)
        XCTAssertEqual(d?.logicalAddress, 0x0010)
    }

    func testIPHelpersAndRange() {
        XCTAssertEqual(GatewayDiscovery.ipString(0xA9FE_0100), "169.254.1.0")
        XCTAssertEqual(GatewayDiscovery.ipValue("169.254.254.255"), 0xA9FE_FEFF)
        XCTAssertNil(GatewayDiscovery.ipValue("169.254.1"))
        XCTAssertNil(GatewayDiscovery.ipValue("300.1.1.1"))
        XCTAssertEqual(GatewayDiscovery.linkLocalRange.count, 65_024)
    }

    func testWiredInterfacePicking() {
        let wifi = NetInterface(name: "en0", address: "192.168.1.20", netmask: "255.255.255.0",
                                broadcast: "192.168.1.255", isUp: true, isLoopback: false)
        let usb = NetInterface(name: "en7", address: "169.254.33.4", netmask: "255.255.0.0",
                               broadcast: "169.254.255.255", isUp: true, isLoopback: false)
        let lo = NetInterface(name: "lo0", address: "127.0.0.1", netmask: "255.0.0.0",
                              broadcast: nil, isUp: true, isLoopback: true)
        XCTAssertEqual(NetInterfaces.wiredCandidate([lo, wifi, usb]), usb)
        XCTAssertNil(NetInterfaces.wiredCandidate([lo, wifi]))
        XCTAssertFalse(NetInterfaces.list().isEmpty, "getifaddrs should list at least loopback")
    }
}
