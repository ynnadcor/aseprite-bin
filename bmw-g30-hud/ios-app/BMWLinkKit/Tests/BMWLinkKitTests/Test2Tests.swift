// SPDX-License-Identifier: MIT
// Test 2 (module scan + engine values) and the G-meter math. Mirrors
// Test2Tests in tests/test_car_test_tool.py.
import XCTest
@testable import BMWLinkKit

final class Test2Tests: XCTestCase {
    private func makeLink(_ kind: DiagProtocol) throws -> (DiagLink, MockGateway) {
        let gw = MockGateway(kind: kind)
        let stream = MockGatewayStream(gateway: gw)
        let link: DiagLink = kind == .hsfz
            ? HSFZLink(stream: stream, timeouts: .uniform(0.3))
            : DoIPLink(stream: stream, timeouts: .uniform(0.3))
        try link.open()
        return (link, gw)
    }

    func testModuleScanIsOneRead() throws {
        let (link, gw) = try makeLink(.hsfz)
        let modules = try ReadOnlyDiagClient(link: link).scanModules()
        XCTAssertEqual(modules.map(\.address), [0x10, 0x12, 0x29, 0x40, 0x60, 0x63])
        XCTAssertEqual(modules[1].name, "Engine computer (DME)")
        XCTAssertEqual(modules[1].outcome, .answered)
        XCTAssertEqual(modules[1].detail, "00 00 12 01")
        XCTAssertEqual(gw.udsRequestsSeen, [[0x22, 0xF1, 0x50]])   // a single read, nothing else
    }

    func testModuleScanRefusesWrites() throws {
        let (link, gw) = try makeLink(.hsfz)
        for uds: [UInt8] in [[0x2E, 0xF1, 0x50, 0x00], [0x14, 0xFF, 0xFF, 0xFF], [0x31, 0x01, 0x02, 0x03]] {
            XCTAssertThrowsError(try link.requestFunctional(uds: uds)) { error in
                XCTAssertEqual(error as? DiagError, .notReadOnly(uds[0]))
            }
        }
        XCTAssertTrue(gw.udsRequestsSeen.isEmpty)
    }

    func testDoIPScanNotBuilt() throws {
        let (link, _) = try makeLink(.doip)
        XCTAssertThrowsError(try ReadOnlyDiagClient(link: link).scanModules())
    }

    func testEngineValues() throws {
        let (link, _) = try makeLink(.hsfz)
        let report = ReadOnlyDiagClient(link: link).runIdentify(plan: .engine, host: "sim")
        func value(_ label: String) -> IdentifyItem.Outcome? { report.items.first { $0.label == label }?.outcome }
        XCTAssertEqual(value("Engine speed (OBD 0C) F40C"), .value("820 rpm"))
        XCTAssertEqual(value("Coolant temperature (OBD 05) F405"), .value("90 °C"))
        XCTAssertEqual(value("Engine load (OBD 04) F404"), .value("20 %"))
        if case .negative = value("Oil temperature (OBD 5C) F45C") {} else { XCTFail("oil temperature should be declined") }
        XCTAssertEqual(EngineValues.boost(from: report), "0.1 psi (1 kPa above outside air)")
        XCTAssertEqual(report.summary, "9 answered, 1 declined, 0 no answer")
    }

    func testModuleScanOverRealSockets() throws {
        let server = try LoopbackGateway(kind: .hsfz)
        defer { server.stop() }
        let link = try DiagConnector.connect(host: "127.0.0.1", protocolKind: .hsfz, port: server.tcpPort,
                                             timeouts: .uniform(1.0))
        defer { link.close() }
        let modules = try ReadOnlyDiagClient(link: link).scanModules()
        XCTAssertEqual(modules.count, 6)
        XCTAssertTrue(server.gateway.udsRequestsSeen.allSatisfy { $0.first == 0x22 })
    }
}

final class GForceTests: XCTestCase {
    func testUprightPhoneFacingDriver() throws {
        // Portrait, screen toward the driver: gravity points along -Y.
        let axes = try XCTUnwrap(CarAxes.calibrate(gravity: Vector3(0, -1, 0)))
        XCTAssertEqual(axes.forward, Vector3(0, 0, -1))
        XCTAssertEqual(axes.right, Vector3(1, 0, 0))
        let felt = axes.felt(Vector3(0, 0, -0.5))      // pushed toward the car's front
        XCTAssertEqual(felt.longitudinal, 0.5, accuracy: 1e-9)   // braking
        XCTAssertEqual(felt.lateral, 0, accuracy: 1e-9)
    }

    func testFlatPhoneTopForward() throws {
        let axes = try XCTUnwrap(CarAxes.calibrate(gravity: Vector3(0, 0, -1)))
        XCTAssertEqual(axes.forward, Vector3(0, 1, 0))
        XCTAssertEqual(axes.right, Vector3(1, 0, 0))
        XCTAssertEqual(axes.felt(Vector3(0.3, 0, 0)).lateral, 0.3, accuracy: 1e-9)
    }

    func testNoCalibrationWithoutGravity() {
        XCTAssertNil(CarAxes.calibrate(gravity: Vector3(0, 0, 0)))
    }

    func testTrackerPeaksAndTrail() {
        var t = GForceTracker(smoothing: 1, trailLength: 3)
        t.add(lateral: 0.4, longitudinal: -0.3)   // turning left, accelerating
        t.add(lateral: -0.6, longitudinal: 0.8)   // turning right, braking
        t.add(lateral: 0, longitudinal: 0)
        t.add(lateral: 0, longitudinal: 0)
        XCTAssertEqual(t.peakLeftTurn, 0.4, accuracy: 1e-9)
        XCTAssertEqual(t.peakRightTurn, 0.6, accuracy: 1e-9)
        XCTAssertEqual(t.peakAccelerating, 0.3, accuracy: 1e-9)
        XCTAssertEqual(t.peakBraking, 0.8, accuracy: 1e-9)
        XCTAssertEqual(t.peakTotal, 1.0, accuracy: 1e-9)
        XCTAssertEqual(t.trail.count, 3)
        t.resetPeaks()
        XCTAssertEqual(t.peakTotal, 0)
        XCTAssertTrue(t.trail.isEmpty)
    }

    func testSmoothing() {
        var t = GForceTracker(smoothing: 0.5)
        t.add(lateral: 1, longitudinal: 0)
        XCTAssertEqual(t.current.lateral, 0.5, accuracy: 1e-9)
    }
}
