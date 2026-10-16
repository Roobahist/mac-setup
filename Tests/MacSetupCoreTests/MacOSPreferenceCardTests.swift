import XCTest
@testable import MacSetupCore

final class MacOSPreferenceCardTests: XCTestCase {
    private var home: URL!
    private var paths: Paths!
    private var runner: FakeRunner!
    private var journal: Journal!
    private var service: MacOSPreferenceService!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        paths = Paths(home: home); runner = FakeRunner()
        journal = try Journal(paths: paths, runner: runner)
        service = MacOSPreferenceService(paths: paths, journal: journal, runner: runner, osMajor: 15)
        let rows: [[String: Any]] = [
            ["id": "dock.autoHide", "title": "Hide Dock", "category": "Dock", "domain": "com.apple.dock", "key": "autohide", "value": true, "enabled": true, "tasks": []],
            ["id": "dock.recents", "title": "Recents", "category": "Dock", "domain": "com.apple.dock", "key": "show-recents", "value": false, "enabled": true, "tasks": []],
            ["id": "dock.pinnedApps", "title": "Pinned apps", "category": "Dock", "domain": "com.apple.dock", "key": "persistent-apps", "value": [], "enabled": true, "tasks": []]
        ]
        try FileManager.default.createDirectory(at: service.profileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["version": 1, "enabled": true, "settings": rows]).write(to: service.profileURL)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    func testLoadReadsLiveValuesAndSavingOneCardAdoptsUneditedManualChanges() throws {
        runner.preferences["com.apple.dock"] = ["autohide": false, "show-recents": true]
        let snapshot = try service.snapshot()
        let editor = try service.editingProfile(snapshot)
        XCTAssertEqual(editor.settings.first { $0.id == "dock.autoHide" }?.value as? Bool, false)
        XCTAssertEqual(editor.settings.first { $0.id == "dock.recents" }?.value as? Bool, true)
        XCTAssertFalse(Journal.exists(paths.state))
        // This second setting changes outside the app after its cards have loaded.
        runner.preferences["com.apple.dock"]?["show-recents"] = false
        runner.calls = []
        _ = try service.applyEdits([.init(id: "dock.autoHide", enabled: true, value: true)], snapshot: snapshot, enabled: true)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, true)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["show-recents"] as? Bool, false)
        XCTAssertEqual(try service.profile().settings.first { $0.id == "dock.recents" }?.value as? Bool, false)
        let writes = runner.calls.filter { $0.prefix(2) == ["/usr/bin/defaults", "write"] }
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(writes[0].contains("autohide"))
    }

    func testConcurrentManualEditToEditedCardIsRejectedBeforeAnyWrites() throws {
        runner.preferences["com.apple.dock"] = ["autohide": false]
        let snapshot = try service.snapshot(), original = try Data(contentsOf: service.profileURL)
        runner.preferences["com.apple.dock"]?["autohide"] = true
        XCTAssertThrowsError(try service.applyEdits([.init(id: "dock.autoHide", enabled: true, value: true)], snapshot: snapshot, enabled: true))
        XCTAssertEqual(try Data(contentsOf: service.profileURL), original)
        XCTAssertFalse(Journal.exists(paths.state.appendingPathComponent("journal.json")))
        XCTAssertTrue(journal.transactions.isEmpty)
    }

    func testConcurrentFileEditIsRejectedAndPreviewDoesNotWrite() throws {
        let snapshot = try service.snapshot()
        let edits = [MacOSPreferenceEdit(id: "dock.autoHide", enabled: true, value: true)]
        _ = try service.previewEdits(edits, snapshot: snapshot, enabled: true)
        XCTAssertFalse(Journal.exists(paths.state))
        try snapshot.profile.settingEnabled(false).encoded().write(to: service.profileURL)
        XCTAssertThrowsError(try service.applyEdits(edits, snapshot: snapshot, enabled: true))
        XCTAssertFalse(Journal.exists(paths.state.appendingPathComponent("journal.json")))
        XCTAssertTrue(journal.transactions.isEmpty)
    }

    func testPortableFileNeverCopiesPrivateDockRecords() throws {
        let secret = "private-path-must-not-enter-the-profile"
        runner.preferences["com.apple.dock"] = ["persistent-apps": [["bookmark": Data([1, 2, 3]), "path": secret]]]
        let snapshot = try service.snapshot()
        let editor = try service.editingProfile(snapshot)
        XCTAssertFalse(try XCTUnwrap(editor.settings.first { $0.id == "dock.pinnedApps" }).enabled)
        _ = try service.applyEdits([.init(id: "dock.autoHide", enabled: true, value: true)], snapshot: snapshot, enabled: true)
        let json = try String(contentsOf: service.profileURL)
        XCTAssertFalse(json.contains(secret))
        XCTAssertEqual((runner.preferences["com.apple.dock"]?["persistent-apps"] as? [[String: Any]])?.count, 1)
    }

    func testLaterManualEditSurvivesAnotherCardApplyAndMasterOff() throws {
        runner.preferences["com.apple.dock"] = ["autohide": false, "show-recents": true]
        _ = try service.applyEdits([.init(id: "dock.autoHide", enabled: true, value: true)], snapshot: service.snapshot(), enabled: true)
        runner.preferences["com.apple.dock"]?["autohide"] = false
        _ = try service.applyEdits([.init(id: "dock.recents", enabled: true, value: false)], snapshot: service.snapshot(), enabled: true)
        _ = try service.applyEdits([], snapshot: service.snapshot(), enabled: false)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, false)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["show-recents"] as? Bool, true)
    }

    func testManualEditBecomesBaselineForNextExplicitChangeAndUndoRestoresOneFile() throws {
        runner.preferences["com.apple.dock"] = ["autohide": false]
        _ = try service.applyEdits([.init(id: "dock.autoHide", enabled: true, value: true)], snapshot: service.snapshot(), enabled: true)
        runner.preferences["com.apple.dock"]?["autohide"] = false
        let previousFile = try Data(contentsOf: service.profileURL)
        let change = try service.applyEdits([.init(id: "dock.autoHide", enabled: true, value: true)], snapshot: service.snapshot(), enabled: true)
        _ = try service.restore(change.transaction)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, false)
        XCTAssertEqual(try Data(contentsOf: service.profileURL), previousFile)
    }

    func testRefreshPreservesPendingComparisonAndUpdatesOtherBaselines() throws {
        runner.preferences["com.apple.dock"] = ["autohide": false, "show-recents": false]
        let old = try service.snapshot()
        runner.preferences["com.apple.dock"] = ["autohide": true, "show-recents": true]
        let fresh = try service.snapshot(), merged = fresh.preservingBaseline(for: ["dock.autoHide"], from: old)
        XCTAssertEqual(try merged.value(for: "dock.autoHide") as? Bool, false)
        XCTAssertEqual(try merged.value(for: "dock.recents") as? Bool, true)
        XCTAssertThrowsError(try service.applyEdits([.init(id: "dock.autoHide", enabled: true, value: false)], snapshot: merged, enabled: true))
        _ = try service.applyEdits([.init(id: "dock.recents", enabled: true, value: false)], snapshot: merged, enabled: true)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["autohide"] as? Bool, true)
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["show-recents"] as? Bool, false)
    }

    func testReferenceFinderProjectionKeepsOnlyPortableOptions() throws {
        let reference = Paths(home: home).profile.appendingPathComponent("macos/preferences.json")
        try Data(contentsOf: reference).write(to: service.profileURL)
        runner.preferences["com.apple.finder"] = ["StandardViewSettings": ["ListViewSettings": [
            "iconSize": 48.0, "textSize": 16.0, "sortColumn": "size", "privateBookmark": Data([9, 9]),
            "columns": ["name": ["visible": true], "size": ["visible": true, "ascending": true]]]]]
        let projected = try service.editingProfile(service.snapshot())
        let value = try XCTUnwrap(projected.settings.first { $0.id == "finder.listOptions" }?.value as? [String: Any])
        XCTAssertEqual(value["iconSize"] as? Double, 48)
        XCTAssertEqual(value["visibleColumns"] as? [String], ["name", "size"])
        XCTAssertEqual(value["sortAscending"] as? Bool, true)
        XCTAssertFalse(try projected.encoded().contains(Data("privateBookmark".utf8)))
    }
}
