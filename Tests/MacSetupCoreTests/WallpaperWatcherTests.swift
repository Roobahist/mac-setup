import Foundation
import XCTest
@testable import MacSetupCore

final class WallpaperWatcherTests: XCTestCase {
    private typealias Observation = WallpaperWatcher.Observation

    private func image(_ name: String, version: Int = 1) -> Observation {
        let url = URL(fileURLWithPath: "/tmp/wallpapers/\(name).jpg")
        let stamp = WallpaperWatcher.WallpaperStamp(
            path: url.path, size: Int64(2048 + version),
            modified: Date(timeIntervalSince1970: TimeInterval(version))
        )
        return Observation(url: url, stamp: stamp)
    }

    func testThreeConsecutiveWallpaperChangesAreAllApplied() throws {
        let a = image("A"), b = image("B"), c = image("C")
        let observations = [a, a, b, b, c, c]
        var index = 0
        var applied: [String] = []
        var reports: [String] = []

        try WallpaperWatcher.monitor(
            maxPolls: 3,
            observe: {
                defer { index += 1 }
                return observations[index]
            },
            apply: { applied.append($0.lastPathComponent) },
            wait: { _ in },
            report: { reports.append($0) }
        )

        XCTAssertEqual(applied, ["A.jpg", "B.jpg", "C.jpg"])
        XCTAssertEqual(index, 6)
        XCTAssertEqual(reports.filter { $0.hasPrefix("Accent updated:") }.count, 3)
    }

    func testChangeDuringDebounceUsesNewWallpaperInsteadOfStaleOne() throws {
        let a = image("A"), b = image("B"), c = image("C")
        let observations = [a, b, b, b, c, c]
        var index = 0
        var applied: [String] = []
        var messages: [String] = []

        try WallpaperWatcher.monitor(
            maxPolls: 3,
            observe: {
                defer { index += 1 }
                return observations[index]
            },
            apply: { applied.append($0.lastPathComponent) },
            wait: { _ in },
            report: { messages.append($0) }
        )

        XCTAssertEqual(applied, ["B.jpg", "C.jpg"])
        XCTAssertTrue(messages.contains { $0.contains("changed during debounce") })
    }

    func testSameFileWithUpdatedMetadataTriggersAnotherRefresh() throws {
        let first = image("cached", version: 1)
        let second = image("cached", version: 2)
        let values = [first, first, second, second]
        var index = 0
        var refreshed = 0

        try WallpaperWatcher.monitor(
            maxPolls: 2,
            observe: {
                defer { index += 1 }
                return values[index]
            },
            apply: { _ in refreshed += 1 },
            wait: { _ in },
            report: { _ in }
        )
        XCTAssertEqual(refreshed, 2)
    }

    func testFailedChangeRetriesOnlyAfterCooldown() throws {
        let original = image("A"), updated = image("B")
        let values = [original, original, updated, updated, updated, updated, updated, updated]
        var index = 0
        var seconds: TimeInterval = 0
        var attempts: [String] = []
        var reports: [String] = []

        try WallpaperWatcher.monitor(
            maxPolls: 5,
            observe: {
                defer { index += 1 }
                return values[min(index, values.count - 1)]
            },
            apply: { url in
                attempts.append(url.lastPathComponent)
                if url.lastPathComponent == "B.jpg" && attempts.filter({ $0 == "B.jpg" }).count == 1 {
                    throw NSError(domain: "test", code: 12)
                }
            },
            wait: { seconds += $0; if seconds == 8 { seconds += 65 } },
            now: { Date(timeIntervalSince1970: seconds) },
            report: { reports.append($0) }
        )
        XCTAssertEqual(attempts, ["A.jpg", "B.jpg", "B.jpg"])
        XCTAssertEqual(reports.filter { $0.hasPrefix("Accent update failed:") }.count, 1)
    }

    func testOneShotPropagatesRefreshFailure() throws {
        XCTAssertThrowsError(try WallpaperWatcher.monitor(
            once: true,
            observe: { image("A") },
            apply: { _ in throw NSError(domain: "test", code: 99) },
            wait: { _ in XCTFail("One-shot should not wait") },
            report: { _ in }
        ))
    }

    func testEventWaitPumpsRunLoopInsteadOfSleepingThread() {
        var fired = false
        let timer = Timer(timeInterval: 0.025, repeats: false) { _ in fired = true }
        RunLoop.current.add(timer, forMode: .default)
        WallpaperWatcher.waitForDesktopEvents(0.12)
        XCTAssertTrue(fired, "Main-thread polling must deliver run-loop events")
    }
}
