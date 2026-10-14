import XCTest
@testable import MacSetupCore

final class WorkspaceConfigurationTests: XCTestCase {
    private func template(_ file: String) throws -> String {
        let url = Paths().profile.appendingPathComponent(file)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testTomitoDefaultAndOptionalWorkspace() throws {
        let config = WorkspaceConfiguration.defaultLayout
        try config.validate()
        XCTAssertEqual(config.workspaces.count, 13)
        XCTAssertEqual(config.workspaces.last?.id, "timer")
        XCTAssertEqual(config.workspaces.last?.requiresTask, "tomito")
        XCTAssertEqual(config.workspaces.last?.apps, ["com.tomito.tomito"])
        let toml = try config.aerospaceTOML(from: template("aerospace/aerospace.toml"))
        XCTAssertTrue(toml.contains("com.tomito.tomito"))
        XCTAssertTrue(toml.contains("alt-equal = 'workspace timer'"))
        XCTAssertTrue(toml.contains("alt-9 = 'workspace music'"))

        let withoutTomito = config.forSelectedTasks(["aerospace-profile", "sketchybar-profile"])
        XCTAssertEqual(withoutTomito.workspaces.count, 12)
        XCTAssertFalse(withoutTomito.workspaces.contains { $0.id == "timer" })
        let generated = try withoutTomito.aerospaceTOML(from: template("aerospace/aerospace.toml"))
        XCTAssertFalse(generated.contains("com.tomito.tomito"))
        XCTAssertFalse(generated.contains("workspace timer"))
        XCTAssertEqual(config.workspaces.count, 13, "Filtering must not mutate the user's saved layout")
        XCTAssertEqual(config.forSelectedTasks(nil), config)
        XCTAssertEqual(config.forSelectedTasks(["tomito"]), config)
    }

    func testHiddenOptionalWorkspaceSurvivesVisibleEdits() throws {
        let original = WorkspaceConfiguration.defaultLayout
        var visible = original.forSelectedTasks(["aerospace-profile"])
        XCTAssertFalse(visible.workspaces.contains { $0.id == "timer" })
        visible.workspaces[0].name = "Development"
        visible.workspaces[0].glyph = "terminal"

        let merged = try original.mergingVisible(visible, selectedTasks: ["aerospace-profile"])
        XCTAssertEqual(merged.workspaces.first?.name, "Development")
        XCTAssertEqual(merged.workspaces.last?.id, "timer")
        XCTAssertEqual(merged.workspaces.last?.requiresTask, "tomito")
        XCTAssertTrue(merged.forSelectedTasks(["aerospace-profile"])
            .workspaces.allSatisfy { $0.id != "timer" })

        visible.workspaces.append(WorkspaceDefinition(id: "extra", name: "Extra", glyph: "star"))
        XCTAssertThrowsError(try original.mergingVisible(visible, selectedTasks: ["aerospace-profile"]))
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

    func testEngineRespectsInstallerSelectionWhenGeneratingAeroSpace() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = Paths(home: home)
        let engine = try Engine(paths: paths, runner: FakeRunner(), tools: { _ in nil })

        engine.selectedWorkspaceTaskIDs = ["aerospace-profile", "sketchybar-profile"]
        let first = try engine.apply(Catalog.task("aerospace-profile"))
        let file = paths.config.appendingPathComponent("aerospace/aerospace.toml")
        let withoutTomito = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(withoutTomito.contains("workspace timer"))
        XCTAssertFalse(withoutTomito.contains("com.tomito.tomito"))
        XCTAssertFalse(withoutTomito.contains("alt-equal = 'workspace timer'"))

        engine.selectedWorkspaceTaskIDs = ["tomito", "aerospace-profile", "sketchybar-profile"]
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .ready)
        let second = try engine.apply(Catalog.task("aerospace-profile"))
        let withTomito = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(withTomito.contains("workspace timer"))
        XCTAssertTrue(withTomito.contains("com.tomito.tomito"))

        try engine.journal.restore(second)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), withoutTomito)
        try engine.journal.restore(first)
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
