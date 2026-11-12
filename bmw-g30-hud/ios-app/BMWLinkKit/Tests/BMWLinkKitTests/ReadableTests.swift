// SPDX-License-Identifier: MIT
// Mirrors DecodeTests in tests/test_car_test_tool.py. Values are synthetic;
// the shapes match what a real 2018 G30 returned.
import XCTest
@testable import BMWLinkKit

final class ReadableTests: XCTestCase {
    func testSoftwareList() throws {
        let data = MockGateway.syntheticSVK([(0x01, 0x0ABC, [1, 0, 4]), (0x02, 0x0BAD, [0xFF, 0xFF, 0xFF]),
                                             (0x06, 0x1001, [12, 34, 5]), (0x08, 0x1002, [12, 34, 5]),
                                             (0x04, 0x1003, [3, 2, 1])], date: [0x22, 0x07, 0x19])
        let svk = try XCTUnwrap(SoftwareList.parse(data))
        XCTAssertEqual(svk.date, "2022-07-19")
        XCTAssertTrue(svk.dependenciesOK)
        XCTAssertEqual(svk.parts[1], SoftwareList.Part(processClass: "HWAP", id: "00000BAD", version: "-"))
        XCTAssertEqual(svk.parts[3], SoftwareList.Part(processClass: "SWFL", id: "00001002", version: "12.34.5"))
        XCTAssertEqual(svk.summary, "programmed 2022-07-19; 5 parts; software 12.34.5; gateway table 3.2.1")
        XCTAssertTrue(svk.full.contains("HWEL 00000ABC 1.0.4"))
    }

    func testSoftwareListFallsBackToHex() {
        XCTAssertEqual(SoftwareList.describe([0x01, 0x02, 0x03]), "01 02 03")
        XCTAssertNil(SoftwareList.parse([1, 0, 1, 8, 0, 0, 0x12, 0x34, 1, 2, 3]))
    }

    func testFaultMemory() {
        XCTAssertEqual(FaultMemory.summary([]), "none stored")
        let untested = [UDS.DTCRecord(dtc: 0xB7F805, status: 0x50), UDS.DTCRecord(dtc: 0xB7F806, status: 0x50),
                        UDS.DTCRecord(dtc: 0xB7F807, status: 0x50), UDS.DTCRecord(dtc: 0xB7F87F, status: 0x40)]
        XCTAssertEqual(FaultMemory.summary(untested), "no faults (4 entries, all just 'not tested yet')")
        let mixed = [UDS.DTCRecord(dtc: 0x123456, status: 0x09), UDS.DTCRecord(dtc: 0x654321, status: 0x50)]
        XCTAssertEqual(FaultMemory.summary(mixed),
                       "1 fault(s): 123456 (active now, stored); 1 other entries not tested yet")
        XCTAssertEqual(FaultMemory.statusText(0x04), "pending")
        XCTAssertEqual(FaultMemory.statusText(0x20), "failed earlier")
        XCTAssertEqual(FaultMemory.statusText(0x50), "not tested yet")
    }

    func testSerialMaskedEverywhere() {
        let log = SessionLog()
        log.info("serial SIM-HU-0001")
        log.rx("answer", Array("SIM-HU-0001".utf8))
        let text = log.export(secrets: [LogRedactor.Secret("SIM-HU-0001", keepPrefix: 0)])
        XCTAssertFalse(text.contains("SIM-HU-0001"))
        XCTAssertFalse(text.contains(Array("SIM-HU-0001".utf8).spacedHex))
        XCTAssertTrue(text.contains("***********"))
    }
}
