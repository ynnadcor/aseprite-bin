// SPDX-License-Identifier: MIT
// Live gauge sampling: decode a snapshot from the simulated gateway, derive
// boost, and the practice-mode demo generator. Values here are synthetic.
import XCTest
@testable import BMWLinkKit

final class LiveTests: XCTestCase {
    private func makeLink() throws -> (DiagLink, MockGateway) {
        let gw = MockGateway(kind: .hsfz)
        let stream = MockGatewayStream(gateway: gw)
        let link = HSFZLink(stream: stream, timeouts: .uniform(0.3))
        try link.open()
        return (link, gw)
    }

    func testReadSampleFromGateway() throws {
        let (link, _) = try makeLink()
        let s = ReadOnlyDiagClient(link: link).readLiveSample()
        XCTAssertEqual(s.rpm, 820)                     // 0x0CD0 / 4
        XCTAssertEqual(s.coolantC, 90)                 // 130 - 40
        XCTAssertEqual(s.intakeAirC, 30)               // 70 - 40
        XCTAssertEqual(s.manifoldKpa, 101)
        XCTAssertEqual(s.baroKpa, 100)
        XCTAssertEqual(s.loadPct.map { Int($0) }, 20)  // 51 * 100 / 255
        XCTAssertEqual(s.speedKph, 0)
        XCTAssertNil(s.oilC)                           // the mock DME doesn't share F45C
        XCTAssertEqual(s.boostPsi.map { ($0 * 100).rounded() / 100 }, 0.15)
        XCTAssertTrue(s.hasAnything)
    }

    func testBoostDerivation() {
        var s = LiveSample()
        XCTAssertNil(s.boostPsi)                        // no pressures yet
        s.manifoldKpa = 200; s.baroKpa = 100
        XCTAssertEqual(s.boostBar ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(s.boostPsi ?? 0, 14.5, accuracy: 0.05)
    }

    func testDemoIsLivelyAndInRange() {
        var sawBoost = false
        var maxRpm = 0.0
        for i in 0..<400 {
            let s = LiveSample.demo(at: Double(i) * 0.1)
            XCTAssertNotNil(s.rpm); XCTAssertNotNil(s.boostPsi)
            XCTAssertGreaterThanOrEqual(s.rpm ?? 0, 800)
            XCTAssertLessThan(s.rpm ?? 0, 6200)
            XCTAssertGreaterThanOrEqual(s.boostBar ?? -1, -0.01)
            XCTAssertLessThan(s.boostBar ?? 99, 1.1)
            maxRpm = max(maxRpm, s.rpm ?? 0)
            if (s.boostPsi ?? 0) > 5 { sawBoost = true }
        }
        XCTAssertTrue(sawBoost, "demo should build real boost under load")
        XCTAssertGreaterThan(maxRpm, 4000, "demo should rev out")
    }

    func testSampleOnlyReads() throws {
        let (link, gw) = try makeLink()
        _ = ReadOnlyDiagClient(link: link).readLiveSample()
        XCTAssertFalse(gw.udsRequestsSeen.isEmpty)
        XCTAssertTrue(gw.udsRequestsSeen.allSatisfy { $0.first == 0x22 }, "live sampling is RDBI-only")
    }
}
