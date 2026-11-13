// SPDX-License-Identifier: MIT
// The bundled iDrive customization catalog loads and is well formed.
import XCTest
@testable import BMWLinkKit

final class IDriveTweaksTests: XCTestCase {
    func testCatalogLoads() {
        let c = IDriveCatalog.shared
        XCTAssertEqual(c.version, 1)
        XCTAssertGreaterThanOrEqual(c.tweaks.count, 15)
        XCTAssertFalse(c.categories.isEmpty)
    }

    func testEveryTweakIsComplete() {
        let c = IDriveCatalog.shared
        var ids = Set<String>()
        for t in c.tweaks {
            XCTAssertTrue(ids.insert(t.id).inserted, "duplicate id \(t.id)")
            XCTAssertTrue(c.categories.contains(t.category), "stray category \(t.category)")
            for (name, value) in [("title", t.title), ("what", t.what), ("why", t.why),
                                  ("how", t.how), ("undo", t.undo), ("module", t.module)] {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(t.id) empty \(name)")
            }
            // The "how" tells you where to go in BimmerCode, not that the app writes coding.
            XCTAssertTrue(t.how.contains("BimmerCode"), "\(t.id) how should mention BimmerCode")
            XCTAssertTrue(t.reversible)
        }
    }

    func testFilteringByCategory() {
        let c = IDriveCatalog.shared
        XCTAssertFalse(c.usedCategories.isEmpty)
        for cat in c.usedCategories {
            let inCat = c.tweaks(in: cat)
            XCTAssertFalse(inCat.isEmpty)
            XCTAssertTrue(inCat.allSatisfy { $0.category == cat })
        }
        // usedCategories keeps the catalog's order.
        XCTAssertEqual(c.usedCategories, c.categories.filter { !c.tweaks(in: $0).isEmpty })
    }

    func testSportDisplaysIsPresentAndOnTheHeadUnit() {
        let t = IDriveCatalog.shared.tweak("sport-displays")
        XCTAssertNotNil(t)
        XCTAssertEqual(t?.moduleAddress, 0x63)   // head unit
        XCTAssertEqual(t?.risk, .green)
    }

    func testVideoInMotionIsFlaggedAmber() {
        XCTAssertEqual(IDriveCatalog.shared.tweak("video-in-motion")?.risk, .amber)
        XCTAssertNotNil(IDriveCatalog.shared.tweak("video-in-motion")?.caveat)
    }

    func testModuleAnsweredCrossReference() {
        let t = IDriveCatalog.shared.tweak("sport-displays")!   // head unit, 0x63
        XCTAssertNil(t.moduleAnswered(in: nil))
        // A scan where the head unit answered.
        var scan = CodeScan()
        scan.modules = [CodeScan.Module(address: 0x63, info: BMWModules.describe(0x63))]
        scan.modules[0].answered = true
        XCTAssertEqual(t.moduleAnswered(in: scan), true)
        // A scan without the head unit.
        var other = CodeScan()
        other.modules = [CodeScan.Module(address: 0x60, info: BMWModules.describe(0x60))]
        other.modules[0].answered = true
        XCTAssertEqual(t.moduleAnswered(in: other), false)
    }

    func testCatalogTouchesKnownModulesOnly() {
        // Every module the catalog references is one BMW Link knows by name.
        for address in IDriveCatalog.shared.moduleAddresses {
            XCTAssertNotNil(BMWModules.names[address], String(format: "unknown module 0x%02X", address))
        }
    }
}
