import XCTest
@testable import MacSetupCore

final class WorkspaceConfigurationTests: XCTestCase {
    private func template(_ file: String) throws -> String {
        let url = Paths().profile.appendingPathComponent(file)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDefaultDoesNotRequireTomito() throws {
        let config = WorkspaceConfiguration.defaultLayout
        try config.validate()
        XCTAssertFalse(config.workspaces.contains { $0.id == "timer" })
        XCTAssertFalse(config.workspaces.flatMap(\.apps).contains("com.tomito.tomito"))
        let toml = try config.aerospaceTOML(from: template("aerospace/aerospace.toml"))
        XCTAssertFalse(toml.contains("com.tomito.tomito"))
        XCTAssertFalse(toml.contains("workspace timer"))
        XCTAssertTrue(toml.contains("persistent-workspaces = ["))
        XCTAssertTrue(toml.contains("alt-9 = 'workspace music'"))
        XCTAssertFalse(toml.contains("alt-equal = 'workspace timer'"))
    }

    func testRearrangeRenameDeleteAndAssignApps() throws {
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces.removeAll { $0.id == "music" || $0.id == "messages" }
        config.workspaces[0].id = "research"
        config.workspaces[0].name = "Research"
        config.workspaces[0].glyph = "book"
        config.workspaces[0].apps = ["com.example.Research"]
        config.workspaces.swapAt(0, 1)
        try config.validate()

        let toml = try config.aerospaceTOML(from: template("aerospace/aerospace.toml"))
        XCTAssertTrue(toml.contains("alt-backtick = 'workspace 1'"))
        XCTAssertTrue(toml.contains("alt-1 = 'workspace research'"))
        XCTAssertTrue(toml.contains("move-node-to-workspace research"))
        XCTAssertTrue(toml.contains("com.example.Research"))
        XCTAssertFalse(toml.contains("workspace chatgpt"))
        XCTAssertFalse(toml.contains("workspace music"))
        XCTAssertFalse(toml.contains("com.spotify.client"))
        let bar = try config.sketchybarShell(from: template("sketchybar/sketchybarrc"))
        XCTAssertTrue(bar.contains("research) printf"))
        XCTAssertTrue(bar.contains("Hack Nerd Font:Bold:14.5"))
        XCTAssertFalse(bar.contains("    chatgpt) echo"))
    }

    func testInvalidIDsDuplicateAppAndUnknownGlyphAreRejected() throws {
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces[0].id = "bad name"
        XCTAssertThrowsError(try config.validate())
        config.workspaces[0].id = "workspace"
        config.workspaces[0].glyph = "not-a-font-glyph"
        XCTAssertThrowsError(try config.validate())
        config.workspaces[0].glyph = "robot"
        config.workspaces[1].apps = config.workspaces[0].apps
        XCTAssertThrowsError(try config.validate())
        config.workspaces[1].apps = ["com.example.App'; rm -rf /"]
        XCTAssertThrowsError(try config.validate())
    }

    func testSaveAndLoadFromPrivateState() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths),
                       WorkspaceConfiguration.defaultLayout)
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces.removeLast()
        try config.save(to: paths)
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths), config)
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            paths.state.appendingPathComponent("workspaces.json").path))
    }

    func testApplicationDiscoveryIncludesBundledApplications() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Applications/TestEditor.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.testeditor",
            "CFBundleName": "Test Editor",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "test-editor"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let apps = ApplicationDiscovery.scan(home: home)
        XCTAssertTrue(apps.contains { $0.bundleID == "com.example.testeditor" })
    }

    func testAppliedProfileCanBeReconfiguredAndRestored() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = Paths(home: home)
        let runner = FakeRunner()
        let engine = try Engine(paths: paths, runner: runner, tools: { _ in nil })

        let first = try engine.apply(Catalog.task("aerospace-profile"))
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .done)
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces[0].id = "assistant"
        try config.save(to: paths)
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .ready)
        let second = try engine.apply(Catalog.task("aerospace-profile"))
        let updated = try String(contentsOf:
            paths.config.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
        XCTAssertTrue(updated.contains("workspace assistant"))
        XCTAssertFalse(updated.contains("workspace chatgpt"))
        try engine.journal.restore(second)
        let restored = try String(contentsOf:
            paths.config.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
        XCTAssertTrue(restored.contains("workspace chatgpt"))
        try engine.journal.restore(first)
    }
}
