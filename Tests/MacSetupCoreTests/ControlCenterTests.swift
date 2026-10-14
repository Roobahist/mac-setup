import XCTest
@testable import MacSetupCore

final class ControlCenterTests: XCTestCase {
    func testTweakIdentifiersAreUnique() {
        let ids = TweakRegistry.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertFalse(ids.isEmpty)
    }

    func testEverySettingHasBrowsableMetadata() {
        for tweak in TweakRegistry.all {
            XCTAssertFalse(tweak.category.isEmpty)
            XCTAssertFalse(tweak.title.isEmpty)
            XCTAssertFalse(tweak.summary.isEmpty)
            XCTAssertFalse(tweak.domain.isEmpty)
            XCTAssertFalse(tweak.key.isEmpty)
        }
    }

    func testSearchMatchesTitlesAndDescriptions() {
        XCTAssertTrue(TweakRegistry.filtered("hover").contains { $0.id == "dock.hoverDelay" })
        XCTAssertTrue(TweakRegistry.filtered("seconds").contains { $0.id == "clock.seconds" })
        XCTAssertTrue(TweakRegistry.filtered("hidden", category: "Finder").contains {
            $0.id == "finder.hidden"
        })
        XCTAssertFalse(TweakRegistry.filtered("dock", category: "Finder").contains {
            $0.category == "Dock"
        })
    }

    func testSelectionsHaveDistinctOptionsAndValidDefaults() {
        for tweak in TweakRegistry.all {
            if case let .selection(choices) = tweak.kind {
                XCTAssertEqual(choices.count, Set(choices.map(\.id)).count)
                XCTAssertTrue(choices.contains { $0.value == tweak.fallback.intValue })
            }
        }
    }

    func testNumericSliderRangesAreValid() {
        for tweak in TweakRegistry.all {
            if case let .slider(minimum, maximum, step) = tweak.kind {
                XCTAssertLessThan(minimum, maximum)
                XCTAssertGreaterThan(step, 0)
                XCTAssertGreaterThanOrEqual(tweak.fallback.doubleValue, minimum)
                XCTAssertLessThanOrEqual(tweak.fallback.doubleValue, maximum)
            }
        }
    }

    func testVersionComparisonUsesNumericComponents() {
        XCTAssertTrue(MacSetupVersion.isNewer("v0.10.0", than: "0.9.9"))
        XCTAssertTrue(MacSetupVersion.isNewer("v1.0.0", than: "0.9.9"))
        XCTAssertFalse(MacSetupVersion.isNewer("v0.5.0", than: "0.5.0"))
        XCTAssertFalse(MacSetupVersion.isNewer("v0.4.1", than: "0.5.0"))
    }
}
