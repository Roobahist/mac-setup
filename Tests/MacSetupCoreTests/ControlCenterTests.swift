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

    func testDefaultBlueUsesAnAbsentOverrideInsteadOfWritingFour() throws {
        let accent = try XCTUnwrap(TweakRegistry.all.first { $0.id == "appearance.accent" })
        XCTAssertTrue(TweakService.usesSystemDefault(accent, value: NSNumber(value: 4)))
        XCTAssertFalse(TweakService.usesSystemDefault(accent, value: NSNumber(value: 6)))
        let recent = try XCTUnwrap(TweakRegistry.all.first { $0.id == "dock.recents" })
        XCTAssertFalse(TweakService.usesSystemDefault(recent, value: NSNumber(value: 4)))
    }

    func testVersionComparisonUsesNumericComponents() {
        XCTAssertTrue(MacSetupVersion.isNewer("v0.10.0", than: "0.9.9"))
        XCTAssertTrue(MacSetupVersion.isNewer("v1.0.0", than: "0.9.9"))
        XCTAssertFalse(MacSetupVersion.isNewer("v0.5.0", than: "0.5.0"))
        XCTAssertFalse(MacSetupVersion.isNewer("v0.4.1", than: "0.5.0"))
    }

    private struct ArchitectureRunner: CommandRunning {
        func run(_ executable: String, _ arguments: [String], interactive: Bool,
                 input: Data?) throws -> CommandResult {
            guard executable == "/usr/bin/uname", arguments == ["-m"] else {
                throw SetupError("Unexpected command")
            }
            return CommandResult(status: 0, output: Data("arm64".utf8))
        }
    }

    func testReleaseDiscoveryChoosesMatchingArchitectureAndChecksum() throws {
        let json = """
        {
          "tag_name": "v0.6.0",
          "assets": [
            {"name": "mac-setup-v0.6.0-macos-x86_64.tar.gz",
             "browser_download_url": "https://github.com/Roobahist/mac-setup/releases/download/v0.6.0/mac-setup-v0.6.0-macos-x86_64.tar.gz"},
            {"name": "mac-setup-v0.6.0-macos-arm64.tar.gz",
             "browser_download_url": "https://github.com/Roobahist/mac-setup/releases/download/v0.6.0/mac-setup-v0.6.0-macos-arm64.tar.gz"},
            {"name": "mac-setup-v0.6.0-macos-arm64.tar.gz.sha256",
             "browser_download_url": "https://github.com/Roobahist/mac-setup/releases/download/v0.6.0/mac-setup-v0.6.0-macos-arm64.tar.gz.sha256"}
          ]
        }
        """
        let updater = ReleaseUpdater(runner: ArchitectureRunner(), fetch: { _ in Data(json.utf8) })
        let found = try updater.latestRelease()
        XCTAssertEqual(found.version, "0.6.0")
        XCTAssertTrue(found.archive.absoluteString.contains("macos-arm64.tar.gz"))
        XCTAssertTrue(found.checksum.absoluteString.hasSuffix(".sha256"))
    }

    func testReleaseDiscoveryRejectsUntrustedDownloadHosts() {
        let json = """
        {
          "tag_name": "v0.6.0",
          "assets": [
            {"name": "mac-setup-v0.6.0-macos-arm64.tar.gz",
             "browser_download_url": "https://example.com/untrusted.tar.gz"},
            {"name": "mac-setup-v0.6.0-macos-arm64.tar.gz.sha256",
             "browser_download_url": "https://example.com/untrusted.sha256"}
          ]
        }
        """
        let updater = ReleaseUpdater(runner: ArchitectureRunner(), fetch: { _ in Data(json.utf8) })
        XCTAssertThrowsError(try updater.latestRelease())
    }
}
