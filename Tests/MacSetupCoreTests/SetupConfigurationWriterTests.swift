import Foundation
import XCTest
@testable import MacSetupCore

final class SetupConfigurationWriterTests: XCTestCase {
    func testSelectedDraftsHaveIndependentJournaledRecovery() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = Paths(home: home)
        let journal = try Journal(paths: paths, runner: FakeRunner())
        let writer = SetupConfigurationWriter(journal: journal)

        var original = WorkspaceConfiguration.defaultLayout
        try original.save(to: paths)
        var changed = original
        changed.workspaces[0].name = "Code"
        let id = try XCTUnwrap(writer.save(layout: changed))
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths), changed)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            ShortcutSettings.path(in: paths).path), "Saving workspaces must not persist shortcut drafts")
        try journal.restore(id)
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths), original)

        original.workspaces[0].name = "Different"
        try original.save(to: paths)
        XCTAssertNil(try writer.save(), "An app-only workflow should not touch editor configuration")
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths), original)
    }

    func testInvalidDraftCannotReplacePersistedConfiguration() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = Paths(home: home)
        let journal = try Journal(paths: paths, runner: FakeRunner())
        let writer = SetupConfigurationWriter(journal: journal)
        let original = WorkspaceConfiguration.defaultLayout
        try original.save(to: paths)
        var invalid = original
        invalid.workspaces[1].id = invalid.workspaces[0].id
        XCTAssertThrowsError(try writer.save(layout: invalid))
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths), original)
        XCTAssertTrue(journal.transactions.isEmpty, "Validation must occur before starting a transaction")
    }

    func testBothEditorFilesRestoreTogether() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = Paths(home: home)
        let journal = try Journal(paths: paths, runner: FakeRunner())
        let writer = SetupConfigurationWriter(journal: journal)
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces[0].name = "A"
        let settings = ShortcutSettings(entries: [])
        let id = try XCTUnwrap(writer.save(layout: config, shortcuts: settings))
        XCTAssertTrue(FileManager.default.fileExists(atPath: WorkspaceConfiguration.path(in: paths).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ShortcutSettings.path(in: paths).path))
        try journal.restore(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: WorkspaceConfiguration.path(in: paths).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ShortcutSettings.path(in: paths).path))
    }
}
