// SPDX-License-Identifier: MIT
// The code reader: OBD-II reads (shared vectors with tests/test_uds.py), the
// code library, explanations, combination findings and the whole-car scan
// against the simulated gateway. All codes and data here are made up.
import XCTest
@testable import BMWLinkKit

final class CodeTests: XCTestCase {
    private func vectors() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        url.appendPathComponent("test-vectors/doip_uds_vectors.json")
        let all = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return all["obd"] as! [String: Any]
    }

    private func makeLink(_ kind: DiagProtocol = .hsfz, _ edit: (MockGateway) -> Void = { _ in })
        throws -> (DiagLink, MockGateway) {
        let gw = MockGateway(kind: kind)
        edit(gw)
        let stream = MockGatewayStream(gateway: gw)
        let link: DiagLink = kind == .hsfz
            ? HSFZLink(stream: stream, timeouts: .uniform(0.3))
            : DoIPLink(stream: stream, timeouts: .uniform(0.3))
        try link.open()
        return (link, gw)
    }

    private func code(_ c: String, module: UInt16 = 0x12, states: [CodeState] = [.stored]) -> FoundCode {
        let sae = OBD.saeBytes(c) != nil
        return FoundCode(module: module, code: c, isSAE: sae, status: sae ? nil : 0x28, states: states,
                         source: sae ? .obd : .faultMemory)
    }

    // MARK: OBD-II reads

    func testOBDBuildersMatchSharedVectors() throws {
        let v = try vectors()
        let builds: [(String, OBD.Service)] = [("build_stored", .storedCodes), ("build_pending", .pendingCodes),
                                               ("build_permanent", .permanentCodes)]
        for (key, service) in builds {
            let want = (v[key] as! [String: Any])["expect_hex"] as! String
            XCTAssertEqual(try OBD.buildRequest(service).hexString, want, key)
        }
        let m = v["build_monitor_status"] as! [String: Any]
        XCTAssertEqual(try OBD.buildRequest(.currentData, pid: UInt8(m["pid"] as! Int)).hexString,
                       m["expect_hex"] as! String)
        XCTAssertThrowsError(try OBD.buildRequest(.currentData))
    }

    func testOBDCodeListsMatchSharedVectors() throws {
        for case let v as [String: Any] in try vectors()["dtc_responses"] as! [Any] {
            let req = [UInt8(v["request_sid"] as! Int)]
            let got = try OBD.parseCodes(request: req, response: [UInt8](hex: v["response_hex"] as! String))
            XCTAssertEqual(got, v["codes"] as! [String], v["response_hex"] as! String)
        }
        let neg = try vectors()["negative"] as! [String: Any]
        XCTAssertThrowsError(try OBD.parseCodes(request: [0x03], response: [UInt8](hex: neg["response_hex"] as! String))) {
            XCTAssertEqual($0 as? UDS.UDSError, .negativeResponse(requestSID: 0x03, nrc: UInt8(neg["expect_nrc"] as! Int)))
        }
        XCTAssertThrowsError(try OBD.parseCodes(request: [0x03], response: [0x43, 0x02, 0x01, 0x71]))
        XCTAssertThrowsError(try OBD.parseCodes(request: [0x03], response: [0x47, 0x00]))
    }

    func testReadOnlySetStillRefusesClearsAndControl() throws {
        for sid: UInt8 in [0x04, 0x08, 0x14, 0x2E, 0x31] {
            XCTAssertThrowsError(try UDS.assertReadOnly(sid), String(format: "0x%02X", sid))
        }
        let (link, gw) = try makeLink()
        for uds: [UInt8] in [[0x04], [0x08, 0x01], [0x14, 0xFF, 0xFF, 0xFF]] {
            XCTAssertThrowsError(try link.request(target: 0x12, uds: uds)) {
                XCTAssertEqual($0 as? DiagError, .notReadOnly(uds[0]))
            }
        }
        XCTAssertTrue(gw.udsRequestsSeen.isEmpty)
    }

    func testSAECodesRoundTrip() {
        for c in ["P0171", "P0302", "C021A", "B0123", "U0100", "U3003", "P2191", "P1300"] {
            guard let b = OBD.saeBytes(c) else { return XCTFail(c) }
            XCTAssertEqual(OBD.saeCode(b.0, b.1), c)
        }
        for bad in ["P4171", "X0171", "P017", "P01G1", "P0+1A", ""] { XCTAssertNil(OBD.saeBytes(bad), bad) }
    }

    // MARK: library and explanations

    func testLibraryLoads() {
        let lib = CodeLibrary.shared
        XCTAssertEqual(lib.version, 1)
        XCTAssertGreaterThan(lib.entries.count, 150)
        XCTAssertEqual(lib.info("p0171")?.title, "System too lean (bank 1)")
        XCTAssertEqual(lib.info("P0524")?.severity, .stop)
    }

    func testExplainKnownCode() {
        let e = CodeExplainer.explain("p 0302")
        XCTAssertEqual(e.code, "P0302")
        XCTAssertEqual(e.kind, .known)
        XCTAssertEqual(e.severity, .now)
        XCTAssertTrue(e.causes.first?.contains("coil") ?? false)
        XCTAssertNotNil(e.ignored)
    }

    func testExplainUnlistedAndManufacturerCodes() {
        let generic = CodeExplainer.explain("P0799")
        XCTAssertEqual(generic.kind, .category)
        XCTAssertEqual(generic.system, "Transmission")
        XCTAssertNil(generic.severity)
        let maker = CodeExplainer.explain("P1234")
        XCTAssertEqual(maker.kind, .category)
        XCTAssertTrue(maker.meaning.contains("manufacturer-specific"))
        XCTAssertEqual(CodeExplainer.explain("U0423").system, "Network: invalid data from a module")
        XCTAssertTrue(CodeExplainer.explain("C1234").title.contains("Manufacturer"))
    }

    func testExplainBMWCode() {
        let hu = CodeExplainer.explain("0x4b1c00", module: 0x63, states: [.stored])
        XCTAssertEqual(hu.kind, .bmw)
        XCTAssertEqual(hu.code, "4B1C00")
        XCTAssertEqual(hu.severity, .info)
        XCTAssertTrue(hu.meaning.contains("Head unit"))
        XCTAssertEqual(hu.searchQuery, "BMW HU fault code 4B1C00")
        XCTAssertEqual(CodeExplainer.explain("480A20", module: 0x29, states: [.active]).severity, .now)
        XCTAssertEqual(CodeExplainer.explain("480A20", module: 0x29, states: [.stored]).severity, .soon)
        XCTAssertNil(CodeExplainer.explain("480A20").severity)       // typed in: urgency unknown
        XCTAssertEqual(CodeExplainer.explain("hello").kind, .invalid)
    }

    func testStatesFromStatusByte() {
        XCTAssertEqual(CodeState.states(fromStatus: 0x08), [.stored])
        XCTAssertEqual(CodeState.states(fromStatus: 0x2F), [.active, .stored, .pending])
        XCTAssertEqual(CodeState.states(fromStatus: 0x20), [.earlier])
        XCTAssertEqual(CodeState.states(fromStatus: 0x50), [.notTested])
        let c = FoundCode(module: 0x12, record: UDS.DTCRecord(dtc: 0x2A1B00, status: 0xA8))
        XCTAssertEqual(c.code, "2A1B00")
        XCTAssertTrue(c.warningLight)
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(c.stateText, "Stored")
    }

    func testMonitorStatus() throws {
        let s = try XCTUnwrap(OBDMonitorStatus.parse([0x82, 0x07, 0x65, 0x01]))
        XCTAssertTrue(s.engineLightOn)
        XCTAssertEqual(s.storedCodeCount, 2)
        XCTAssertEqual(s.monitors.map(\.name), ["Misfire", "Fuel system", "Components", "Catalyst",
                                                "Evaporative system (EVAP)", "Oxygen sensor", "Oxygen sensor heater"])
        XCTAssertEqual(s.notReady, ["Catalyst"])
        XCTAssertNil(OBDMonitorStatus.parse([0x00]))
        let clean = try XCTUnwrap(OBDMonitorStatus.parse([0x00, 0x07, 0x65, 0x00]))
        XCTAssertEqual(clean.summary, "engine light off, 0 emission code(s); all 7 readiness monitors ready")
    }

    // MARK: combinations

    func testMisfireWithCoilPointsAtTheCoil() {
        let f = CodePatterns.analyze([code("P0302"), code("P0352")])
        XCTAssertEqual(f.map(\.id), ["cyl2-coil"])
        XCTAssertEqual(f[0].codes, ["P0302", "P0352"])
        XCTAssertEqual(f[0].severity, .now)
    }

    func testSeveralMisfiresLookForSharedCause() {
        let ids = CodePatterns.analyze([code("P0301"), code("P0304"), code("P0420")]).map(\.id)
        XCTAssertEqual(ids, ["multi-misfire", "misfire-catalyst"])
        XCTAssertEqual(CodePatterns.analyze([code("P0303")]).map(\.id), ["cyl3"])
    }

    func testMixtureFuelAndBoostCombinations() {
        XCTAssertEqual(CodePatterns.analyze([code("P2187"), code("P0171")]).map(\.id), ["lean-idle"])
        XCTAssertEqual(CodePatterns.analyze([code("P2191")]).map(\.id), ["lean-load"])
        XCTAssertEqual(Set(CodePatterns.analyze([code("P0087"), code("P0171")]).map(\.id)), ["lean-fuel"])
        XCTAssertEqual(CodePatterns.analyze([code("P0299"), code("P2279")]).map(\.id), ["boost-leak"])
        XCTAssertEqual(CodePatterns.analyze([code("P0011"), code("P0014")]).map(\.id), ["cam"])
        XCTAssertEqual(CodePatterns.analyze([code("P0420"), code("P0138")]).map(\.id), ["catalyst-o2"])
        XCTAssertEqual(CodePatterns.analyze([code("P0128"), code("P0597")]).map(\.id), ["thermostat"])
    }

    func testMostUrgentFirst() {
        let ids = CodePatterns.analyze([code("P0562"), code("P0217"), code("P0302"), code("P0352")]).map(\.id)
        XCTAssertEqual(ids, ["engine-protection", "cyl2-coil", "voltage"])
    }

    func testModuleFindings() {
        let lost = [code("U0121", module: 0x30), code("U0121", module: 0x18)]
        XCTAssertEqual(CodePatterns.analyze(lost).map(\.id), ["lost-U0121", "safety-48"])
        let history = [code("111111", module: 0x40), code("222222", module: 0x60), code("333333", module: 0x63)]
        XCTAssertEqual(CodePatterns.analyze(history).map(\.id), ["history"])
        let dsc = CodePatterns.analyze([code("444444", module: 0x29, states: [.active])])
        XCTAssertEqual(dsc.map(\.id), ["safety-41"])
        XCTAssertEqual(dsc[0].severity, .now)
        // Not-tested entries never count.
        XCTAssertTrue(CodePatterns.analyze([code("555555", module: 0x29, states: [.notTested])]).isEmpty)
    }

    // MARK: whole-car scan

    func testScanPracticeCar() throws {
        let (link, gw) = try makeLink()
        let log = SessionLog()
        let scan = ReadOnlyDiagClient(link: link, log: log).scanCodes()
        XCTAssertEqual(scan.foundBy, "one request to all modules")
        XCTAssertEqual(scan.modules.map(\.address), [0x10, 0x12, 0x29, 0x40, 0x60, 0x63])
        XCTAssertTrue(scan.modules.allSatisfy(\.answered))
        let dme = try XCTUnwrap(scan.modules.first { $0.address == 0x12 })
        XCTAssertEqual(dme.codes.map(\.code), ["P0302", "P0352", "P0456", "2A1B00"])
        XCTAssertEqual(dme.codes[0].states, [.stored, .permanent])
        XCTAssertEqual(dme.codes[2].states, [.pending])
        XCTAssertEqual(dme.notTested, 1)
        XCTAssertEqual(scan.engine?.notReady, ["Catalyst"])
        XCTAssertNil(scan.obdNote)
        XCTAssertEqual(scan.faults.count, 8)
        XCTAssertEqual(scan.hiddenEntries, 4)
        XCTAssertEqual(scan.findings.map(\.id), ["cyl2-coil", "safety-41", "history"])
        XCTAssertEqual(scan.summary, "8 fault codes in 6 modules (4 'not tested yet' entries hidden)")
        // Only reads went to the car.
        let sids = Set(gw.udsRequestsSeen.compactMap(\.first))
        XCTAssertTrue(sids.isSubset(of: UDS.allowedServices), "\(sids)")
        XCTAssertFalse(sids.contains(0x04) || sids.contains(0x14))
        XCTAssertTrue(log.all.map(log.format).joined(separator: "\n").contains("Code scan finished"))
    }

    func testScanWhenTheEngineComputerSkipsOBD() throws {
        let (link, _) = try makeLink { gw in
            gw.obdCodes = [:]
            gw.dids[0x12]?[0xF401] = nil       // readiness then comes from mode 01 PID 01
        }
        let scan = ReadOnlyDiagClient(link: link).scanCodes()
        XCTAssertNotNil(scan.obdNote)
        XCTAssertEqual(scan.engine?.storedCodeCount, 2)
        XCTAssertEqual(scan.modules.first { $0.address == 0x12 }?.codes.map(\.code), ["2A1B00"])
    }

    func testScanFallsBackToKnownModules() throws {
        // DoIP has no all-modules request here, so the usual module list is used.
        let (link, _) = try makeLink(.doip)
        let scan = ReadOnlyDiagClient(link: link).scanCodes()
        XCTAssertEqual(scan.foundBy, "the usual module list")
        XCTAssertEqual(scan.modules.map(\.address), BMWModules.info.keys.sorted())
        XCTAssertTrue(scan.faults.contains { $0.code == "P0302" })
    }

    func testScanStopsWhenCancelled() throws {
        let (link, _) = try makeLink()
        var calls = 0
        let scan = ReadOnlyDiagClient(link: link).scanCodes(isCancelled: { calls += 1; return calls > 2 })
        XCTAssertTrue(scan.cancelled)
        XCTAssertEqual(scan.modules.count, 2)
        XCTAssertNil(scan.engine)
    }
}
