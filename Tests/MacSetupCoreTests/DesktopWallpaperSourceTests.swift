import Foundation
import XCTest
@testable import MacSetupCore

final class DesktopWallpaperSourceTests: XCTestCase {
    private let fallback = URL(fileURLWithPath: DesktopWallpaperSource.systemFallback)
    private let photo = URL(fileURLWithPath: "/tmp/my wallpaper.png")

    private func desktop(_ url: URL, set: TimeInterval) throws -> [String: Any] {
        let value: [String: Any] = ["type": "imageFile", "url": ["relative": url.absoluteString]]
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        return ["Desktop": ["LastSet": Date(timeIntervalSince1970: set), "Content": ["Choices": [
            ["Provider": "com.apple.wallpaper.choice.image", "Configuration": data]
        ]]]]
    }

    private func spaces(uuid: String = "desktop", type: Int = 0) -> [String: Any] {
        ["SpacesDisplayConfiguration": ["Management Data": ["Monitors": [
            ["Display Identifier": "Main", "Current Space": ["uuid": uuid, "type": type]]
        ]]]]
    }

    func testSystemFallbackResolvesToConfiguredPhotoInsteadOfChangingAccent() throws {
        XCTAssertEqual(try DesktopWallpaperSource.resolve(reported: fallback, configured: photo), photo)
    }

    func testUnconfirmedFallbackIsUnavailableRatherThanAnImageSelection() {
        XCTAssertThrowsError(try DesktopWallpaperSource.resolve(reported: fallback, configured: nil))
        XCTAssertThrowsError(try DesktopWallpaperSource.resolve(reported: nil, configured: nil))
    }

    func testIntentionalSystemDefaultRemainsSupported() throws {
        XCTAssertEqual(try DesktopWallpaperSource.resolve(reported: fallback, configured: fallback), fallback)
    }

    func testRegularReportedWallpaperNeedsNoPreferenceFiles() throws {
        XCTAssertEqual(try DesktopWallpaperSource.resolve(reported: photo, configured: nil), photo)
    }

    func testCurrentDesktopSelectionSupersedesOldDisplayRecord() throws {
        let old = try desktop(URL(fileURLWithPath: "/tmp/old.jpg"), set: 1)
        let selected = try desktop(photo, set: 2)
        let store: [String: Any] = ["Spaces": ["desktop": ["Default": selected,
            "Displays": ["screen": old]], "historical": ["Default": try desktop(fallback, set: 999)]]]
        XCTAssertEqual(DesktopWallpaperSource.configuredImage(wallpapers: store, spaces: spaces(),
            displayUUID: "screen", isPrimary: true), photo)
    }

    func testDifferentDisplayDoesNotOverrideSelection() throws {
        let store: [String: Any] = ["Spaces": ["desktop": ["Default": try desktop(photo, set: 1),
            "Displays": ["other": try desktop(fallback, set: 999)]]]]
        XCTAssertEqual(DesktopWallpaperSource.configuredImage(wallpapers: store, spaces: spaces(),
            displayUUID: "screen", isPrimary: true), photo)
        XCTAssertNil(DesktopWallpaperSource.configuredImage(wallpapers: store, spaces: spaces(),
            displayUUID: "other", isPrimary: false))
    }

    func testFullscreenOrUnknownSpaceDoesNotBorrowHistoricalSelection() throws {
        let store: [String: Any] = ["Spaces": ["desktop": ["Default": try desktop(photo, set: 1)]]]
        for state in [spaces(type: 4), spaces(uuid: "missing"), [:]] {
            XCTAssertNil(DesktopWallpaperSource.configuredImage(wallpapers: store, spaces: state,
                displayUUID: "screen", isPrimary: true))
        }
    }

    func testNewDynamicSelectionDoesNotReviveOlderPhoto() throws {
        let dynamic: [String: Any] = ["Desktop": ["LastSet": Date(timeIntervalSince1970: 2),
            "Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.aerials"]]]]]
        let store: [String: Any] = ["Spaces": ["desktop": ["Default": dynamic,
            "Displays": ["screen": try desktop(photo, set: 1)]]]]
        XCTAssertNil(DesktopWallpaperSource.configuredImage(wallpapers: store, spaces: spaces(),
            displayUUID: "screen", isPrimary: true))
    }
}
