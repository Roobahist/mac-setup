import XCTest
@testable import MacSetupCore

final class FolderViewOverridesTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    func testOnlyVisibleUserFolderOverridesAreDiscovered() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let manager = FileManager.default
        let dirs = ["Desktop", "Desktop/Project", "Desktop/.hidden", "Desktop/App.app",
                    "Library/Preferences", "Documents"]
        for dir in dirs {
            try manager.createDirectory(at: home.appendingPathComponent(dir), withIntermediateDirectories: true)
            try Data("finder".utf8).write(to: home.appendingPathComponent(dir + "/.DS_Store"))
        }
        try manager.createSymbolicLink(at: home.appendingPathComponent("Documents/linked"),
                                       withDestinationURL: home.appendingPathComponent("Library"))
        let roots = ["Desktop", "Documents"].map { home.appendingPathComponent($0) }
        let found = try FolderViewOverrides.discover(in: roots)
        XCTAssertEqual(found.map { $0.deletingLastPathComponent().lastPathComponent },
                       ["Desktop", "Project", "Documents"])
        XCTAssertThrowsError(try FolderViewOverrides.discover(in: roots, maximumFiles: 2))
    }

    func testRemovalIsJournaledAndReversible() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let desktop = home.appendingPathComponent("Desktop")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let file = desktop.appendingPathComponent(".DS_Store")
        let original = Data("saved folder settings".utf8)
        try original.write(to: file)
        let paths = Paths(home: home)
        let journal = try Journal(paths: paths, runner: FakeRunner())
        let id = try journal.begin("finder-reset-views")
        for override in try FolderViewOverrides.discover(in: [desktop]) {
            try journal.remove(override, transaction: id)
        }
        try journal.finish(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try journal.restore(id)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testProfilesMatchSourcePaletteAndAvoidRecurringRedraws() throws {
        let root = Paths().profile.appendingPathComponent("sketchybar")
        let colors = try String(contentsOf: root.appendingPathComponent("plugins/colors.sh"), encoding: .utf8)
        let bar = try String(contentsOf: root.appendingPathComponent("sketchybarrc"), encoding: .utf8)
        XCTAssertTrue(colors.contains("BASE_GRAY=0x30000000"))
        XCTAssertTrue(bar.contains("display_geometry drawing=off updates=on update_freq=0"))
        XCTAssertFalse(bar.contains("update_freq=15"))
        let aerospace = try String(contentsOf: Paths().profile.appendingPathComponent("aerospace/aerospace.toml"),
                                   encoding: .utf8)
        XCTAssertTrue(aerospace.contains("com.apple.systempreferences'\nrun = 'layout floating'"))
    }
}
