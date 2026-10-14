import XCTest
@testable import MacSetupCore

final class WorkspaceConfigurationTests: XCTestCase {
    private func template(_ file: String) throws -> String {
        let url = Paths().profile.appendingPathComponent(file)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testGeneratedSystemSettingsRulesTileLikePublicDotfiles() throws {
        let source = try String(contentsOf: Paths().profile.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
        let generated = try WorkspaceConfiguration.defaultLayout.aerospaceTOML(from: source)
        for id in ["com.apple.systempreferences", "com.apple.ScreenContinuity"] {
            let rule = "if = 'test %{app-bundle-id} = \(id)'\nrun = 'layout tiling'"
            XCTAssertTrue(source.contains(rule), "The bundled profile must match the public dotfiles for \(id)")
            XCTAssertTrue(generated.contains(rule), "Generation must not change the tiling rule for \(id)")
            XCTAssertFalse(generated.contains("if = 'test %{app-bundle-id} = \(id)'\nrun = 'layout floating'"))
        }
    }

    func testOptionalAppsPreserveEmptyWorkspaces() throws {
        let config = WorkspaceConfiguration.defaultLayout
        try config.validate()
        XCTAssertEqual(config.workspaces.count, 13)
        let chosen: Set<String> = ["aerospace-profile", "sketchybar-profile"]
        let missing = config.forSelectedTasks(chosen, installedBundleIDs: [])
        XCTAssertEqual(missing.workspaces.count, config.workspaces.count)
        for id in ["timer", "notes", "music"] {
            XCTAssertTrue(missing.workspaces.contains { $0.id == id && $0.apps.isEmpty })
        }
        let toml = try missing.aerospaceTOML(from: template("aerospace/aerospace.toml"))
        XCTAssertTrue(toml.contains("workspace timer"))
        XCTAssertFalse(toml.contains("com.tomito.tomito"))
        XCTAssertFalse(toml.contains("md.obsidian"))
        XCTAssertFalse(toml.contains("com.spotify.client"))
        let requested = config.forSelectedTasks(chosen.union(["tomito", "obsidian"]),
                                                installedBundleIDs: [])
        XCTAssertTrue(requested.workspaces.contains { $0.id == "timer" && $0.apps == ["com.tomito.tomito"] })
        XCTAssertTrue(requested.workspaces.contains { $0.id == "notes" && $0.apps == ["md.obsidian"] })
        XCTAssertEqual(config.forSelectedTasks(nil), config)
        XCTAssertEqual(config.forSelectedTasks(chosen, installedBundleIDs: [
            "com.tomito.tomito", "md.obsidian", "com.spotify.client"
        ]), config)
    }

    func testEditingDoesNotDuplicateOptionalWorkspaces() throws {
        let original = WorkspaceConfiguration.defaultLayout
        var visible = original.forSelectedTasks(["aerospace-profile"], installedBundleIDs: [])
        visible.workspaces[0].name = "Development"
        let merged = try original.mergingVisible(visible, selectedTasks: ["aerospace-profile"])
        XCTAssertEqual(merged.workspaces.count, original.workspaces.count)
        XCTAssertEqual(merged.workspaces[0].name, "Development")
        XCTAssertTrue(merged.workspaces.contains { $0.id == "timer" })
    }

    func testReorderingChangesGeneratedWorkspaceOrderBeforeSaving() throws {
        let original = WorkspaceConfiguration.defaultLayout
        var draft = original
        let first = try XCTUnwrap(draft.workspaces.first?.id)
        draft.insertWorkspace(first, at: 3)
        XCTAssertEqual(draft.workspaces[2].id, first)
        XCTAssertNotEqual(draft.workspaces.map(\.id), original.workspaces.map(\.id))
        XCTAssertEqual(draft.workspaces.count, original.workspaces.count)
        let generated = try draft.sketchybarShell(from: template("sketchybar/sketchybarrc"))
        let baseline = try original.sketchybarShell(from: template("sketchybar/sketchybarrc"))
        XCTAssertNotEqual(generated, baseline)
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
        XCTAssertTrue(withoutTomito.contains("workspace timer"))
        XCTAssertFalse(withoutTomito.contains("com.tomito.tomito"))
        XCTAssertTrue(withoutTomito.contains("alt-equal = 'workspace timer'"))

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
