import XCTest
@testable import MacSetupCore

final class MacOSPreferencesTests: XCTestCase {
    var home: URL!
    var paths: Paths!
    var runner: FakeRunner!
    var journal: Journal!
    var service: MacOSPreferenceService!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("macos-profile-test-" + UUID().uuidString)
        paths = Paths(home: home); runner = FakeRunner()
        journal = try Journal(paths: paths, runner: runner)
        service = MacOSPreferenceService(paths: paths, journal: journal, runner: runner, osMajor: 15)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    func row(_ id: String = "dock.autoHide", key: String = "autohide", value: Any = true, enabled: Bool = true) -> [String: Any] {
        ["id": id, "title": id, "enabled": enabled, "domain": "com.apple.dock", "key": key, "value": value, "tasks": ["dock-hide"]]
    }
    func write(_ rows: [[String: Any]], enabled: Bool = true) throws {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "enabled": enabled, "settings": rows])
        try FileManager.default.createDirectory(at: service.profileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: service.profileURL)
    }

    func testRepeatedApplyKeepsOriginalBaselineAndOffRestoresOnlyManagedKeys() throws {
        runner.preferences["com.apple.dock"] = ["autohide": false, "unrelated": "keep"]
        try write([row()]); _ = try service.apply()
        try write([row(value: false)]); _ = try service.apply()
        try write([row()]); _ = try service.apply()
        _ = try service.apply(enabled: false)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, false)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["unrelated"] as? String, "keep")
        XCTAssertFalse(try service.profile().enabled)
        _ = try service.apply(enabled: true)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, true)
    }

    func testDisabledSettingReleasesButFalseIsARealValueAndNullRemovesOverride() throws {
        runner.preferences["com.apple.dock"] = ["autohide": true]
        try write([row(value: false)]); _ = try service.apply()
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, false)
        try write([row(value: false, enabled: false)]); _ = try service.apply()
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, true)
        try write([row(value: NSNull())]); _ = try service.apply()
        XCTAssertNil(runner.preferences["com.apple.dock"]?["autohide"])
        _ = try service.apply(enabled: false)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, true)
    }

    func testOffPreservesLaterManualEditAndNextOnCapturesNewBaseline() throws {
        runner.preferences["com.apple.dock"] = ["autohide-delay": 0.5]
        try write([row("dock.hoverDelay", key: "autohide-delay", value: 0.1)]); _ = try service.apply()
        runner.preferences["com.apple.dock"]?["autohide-delay"] = 0.8
        XCTAssertTrue(try service.preview(enabled: false).joined().contains("Keep later manual edit"))
        _ = try service.apply(enabled: false)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide-delay"] as? Double, 0.8)
        _ = try service.apply(enabled: true); _ = try service.apply(enabled: false)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide-delay"] as? Double, 0.8)
    }

    func testRemovingSettingRestoresOriginalValue() throws {
        runner.preferences["com.apple.dock"] = ["autohide": false]
        try write([row(), row("dock.recents", key: "show-recents", value: false)])
        _ = try service.apply()
        try write([row("dock.recents", key: "show-recents", value: false)])
        _ = try service.apply()
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, false)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["show-recents"] as? Bool, false)
    }

    func testUndoRestoresProfileManagedBaselineAndValuesWithPrivateStatePermissions() throws {
        try write([row()])
        let original = try Data(contentsOf: service.profileURL)
        let outcome = try service.apply()
        let state = paths.state.appendingPathComponent("macos-managed.json")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: state.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try journal.restore(outcome.transaction)
        XCTAssertNil(runner.preferences["com.apple.dock"]?["autohide"])
        XCTAssertEqual(try Data(contentsOf: service.profileURL), original)
        XCTAssertFalse(Journal.exists(state))
    }

    func testIndividualControlUpdatesSameFileAndUndoRestoresBoth() throws {
        try write([row(), row("dock.recents", key: "show-recents", value: true)])
        let original = try Data(contentsOf: service.profileURL)
        let tweaks = TweakService(journal: journal, runner: runner, paths: paths)
        let tweak = try XCTUnwrap(TweakRegistry.all.first { $0.id == "dock.recents" })
        let result = try tweaks.apply(tweak, value: NSNumber(value: false))
        XCTAssertEqual(try service.profile().settings.first { $0.id == tweak.id }?.value as? Bool, false)
        XCTAssertNil(runner.preferences["com.apple.dock"]?["autohide"], "Individual edits must not apply the rest of the group")
        _ = try service.apply()
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["show-recents"] as? Bool, false)
        // Undo the later group apply first, then the individual change.
        try journal.restore(try XCTUnwrap(journal.transactions.last).id)
        _ = try tweaks.restore(result.transaction, tweak: tweak)
        XCTAssertEqual(try Data(contentsOf: service.profileURL), original)
        XCTAssertNil(runner.preferences["com.apple.dock"]?["show-recents"])
    }

    func testSetupTaskUsesLocalValuesAndHonorsMasterOff() throws {
        try write([row(value: false)])
        runner.preferences["com.apple.dock"] = ["autohide": true]
        let engine = try Engine(paths: paths, runner: runner)
        _ = try engine.apply(Catalog.task("dock-hide"))
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, false)
        _ = try service.apply(enabled: false)
        _ = try engine.apply(Catalog.task("dock-hide"))
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, true)
        XCTAssertFalse(try service.profile().enabled)
    }

    func testUnsupportedOSAndReadOnlyPreviewDoNotWrite() throws {
        var setting = row(); setting["minimumOS"] = 26
        try write([setting])
        let before = try Data(contentsOf: service.profileURL)
        XCTAssertTrue(try service.preview().joined().contains("requires macOS 26"))
        XCTAssertFalse(Journal.exists(paths.state))
        XCTAssertEqual(try Data(contentsOf: service.profileURL), before)
        _ = try service.apply()
        XCTAssertNil(runner.preferences["com.apple.dock"]?["autohide"])
    }

    func testChangedReviewAndExplicitMissingPathAreRejected() throws {
        try write([row()]); let reviewed = try service.profile().encoded()
        try write([row(value: false)])
        XCTAssertThrowsError(try service.apply(expected: reviewed))
        XCTAssertFalse(Journal.exists(paths.state))
        let missing = MacOSPreferenceService(paths: paths, journal: journal, runner: runner,
                                             profileURL: home.appendingPathComponent("missing.json"))
        XCTAssertThrowsError(try missing.profile())
    }

    func testMalformedProfileNeverFallsBackOrWrites() throws {
        for rows in [[row(), row()], [row(value: [NSNull()])]] {
            try write(rows)
            XCTAssertThrowsError(try service.apply())
            XCTAssertFalse(Journal.exists(paths.state))
        }
        var malformed = row(); malformed["enabled"] = "true"
        try write([malformed]); XCTAssertThrowsError(try service.apply())
        malformed = row(); malformed["domain"] = "/tmp/other-file"
        try write([malformed]); XCTAssertThrowsError(try service.apply())
        malformed = row(); malformed["restart"] = "arbitrary-command"
        try write([malformed]); XCTAssertThrowsError(try service.apply())
        malformed = row(); malformed["minimumOS"] = "newest"
        try write([malformed]); XCTAssertThrowsError(try service.apply())
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testBundledProfileCoversEveryControlAndPreferenceTask() throws {
        let profile = try service.profile()
        for tweak in TweakRegistry.all {
            let row = try XCTUnwrap(profile.settings.first { $0.id == tweak.id })
            XCTAssertEqual(row.domain, tweak.domain); XCTAssertEqual(row.key, tweak.key)
        }
        for task in Catalog.tasks {
            if case let .preferences(values, _) = task.action, values.isEmpty && task.id != "macos-preferences" {
                XCTAssertTrue(profile.settings.contains { $0.tasks.contains(task.id) }, task.id)
            }
        }
    }

    func testApplyThroughDirectoryLinkEditsIntendedFileAndUndoRestoresIt() throws {
        let source = home.appendingPathComponent("dotfiles/macos")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try write([row()]); let original = try Data(contentsOf: service.profileURL)
        try original.write(to: source.appendingPathComponent("preferences.json"))
        try FileManager.default.removeItem(at: service.profileURL.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: service.profileURL.deletingLastPathComponent(), withDestinationURL: source)
        let outcome = try service.apply(enabled: false)
        XCTAssertFalse(try service.profile().enabled)
        try journal.restore(outcome.transaction)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("preferences.json")), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: service.profileURL.deletingLastPathComponent().path), source.path)
    }
}

private final class FailingMacOSWriteRunner: CommandRunning {
    let fake = FakeRunner()
    var remainingWrites = 2
    func run(_ executable: String, _ args: [String], interactive: Bool, input: Data?) throws -> CommandResult {
        if executable == "/usr/bin/defaults", args.first == "write" {
            remainingWrites -= 1
            if remainingWrites == 0 { return CommandResult(status: 1, output: Data("injected one-time failure".utf8)) }
        }
        return try fake.run(executable, args, interactive: interactive, input: input)
    }
}

extension MacOSPreferencesTests {
    func testPartialFailureRestoresAlreadyWrittenValuesAndProfileAndCanRetry() throws {
        let failing = FailingMacOSWriteRunner()
        failing.fake.preferences["com.apple.dock"] = ["autohide": false, "show-recents": true]
        let record = try Journal(paths: paths, runner: failing)
        let subject = MacOSPreferenceService(paths: paths, journal: record, runner: failing)
        try write([row(), row("dock.recents", key: "show-recents", value: false)])
        let original = try Data(contentsOf: service.profileURL)
        XCTAssertThrowsError(try subject.apply()) { XCTAssertTrue(String(describing: $0).contains("Previous files and values were restored")) }
        XCTAssertEqual(failing.fake.preferences["com.apple.dock"]?["autohide"] as? Bool, false)
        XCTAssertEqual(failing.fake.preferences["com.apple.dock"]?["show-recents"] as? Bool, true)
        XCTAssertEqual(try Data(contentsOf: service.profileURL), original)
        XCTAssertFalse(Journal.exists(paths.state.appendingPathComponent("macos-managed.json")))
        _ = try subject.apply()
        XCTAssertEqual(failing.fake.preferences["com.apple.dock"]?["autohide"] as? Bool, true)
        XCTAssertEqual(failing.fake.preferences["com.apple.dock"]?["show-recents"] as? Bool, false)
    }
}

extension MacOSPreferencesTests {
    func testRenamedEntryReconcilesOldOwnershipBeforeApplyingNewValue() throws {
        runner.preferences["com.apple.dock"] = ["autohide": false]
        try write([row()]); _ = try service.apply()
        try write([row("renamed-setting")]); _ = try service.apply()
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, true)
        _ = try service.apply(enabled: false)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, false)
    }
}
