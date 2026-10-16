import XCTest
@testable import MacSetupCore

final class BarPreviewTests: XCTestCase {
    func testWorkspacePreviewHasEveryWorkspaceOccupiedAndNoneFocused() {
        let sample = BarPreviewSample(ids: ["ai", "music", "notes"], mixed: false, seed: 1)
        XCTAssertNil(sample.focusedID)
        XCTAssertEqual(sample.occupiedIDs, ["ai", "music", "notes"])
    }

    func testMixedPreviewKeepsOneFocusAndBothOccupancyStatesThroughReordering() {
        let ids = ["ai", "1", "2", "3", "music", "notes"]
        let sample = BarPreviewSample(ids: ids, mixed: true, seed: 42)
        XCTAssertNotNil(sample.focusedID)
        XCTAssertTrue(sample.occupiedIDs.contains(sample.focusedID!))
        XCTAssertGreaterThan(sample.occupiedIDs.count, 1)
        XCTAssertLessThan(sample.occupiedIDs.count, ids.count)
        let reordered = BarPreviewSample(ids: ids.reversed(), mixed: true, seed: 42)
        XCTAssertEqual(sample.focusedID, reordered.focusedID)
        XCTAssertEqual(sample.occupiedIDs, reordered.occupiedIDs)
        XCTAssertNil(BarPreviewSample(ids: [], mixed: true, seed: 1).focusedID)
        XCTAssertEqual(BarPreviewSample(ids: ["only"], mixed: true, seed: 1).occupiedIDs, ["only"])
    }

    func testWallpaperPlacementUsesTheDesktopAspectRatioAndCenteredCrop() {
        let screen = CGSize(width: 1680, height: 1050), image = CGSize(width: 3840, height: 2160)
        let fill = WallpaperPreviewGeometry.imageRect(image: image, screen: screen, fill: true)
        XCTAssertEqual(fill.height, 1050)
        XCTAssertLessThan(fill.minX, 0)
        XCTAssertEqual(fill.minY, 0)
        let fit = WallpaperPreviewGeometry.imageRect(image: image, screen: screen, fill: false)
        XCTAssertEqual(fit.width, 1680)
        XCTAssertGreaterThan(fit.minY, 0)
        XCTAssertEqual(WallpaperPreviewGeometry.imageRect(image: image, screen: screen, fill: true, stretch: true).size, screen)
        XCTAssertEqual(WallpaperPreviewGeometry.imageRect(image: image, screen: screen, fill: false, actualSize: true).size, image)
    }
}
