import XCTest
@testable import MacSetupCore

final class ReferenceParityTests: XCTestCase {
    private var paths: Paths { Paths() }
    private func source(_ name: String) throws -> Data {
        try Data(contentsOf: paths.profile.appendingPathComponent(name))
    }
    private func template() throws -> String { String(decoding: try source("aerospace/aerospace.toml"), as: UTF8.self) }
    private func settings() throws -> ShortcutSettings { .defaults(aerospaceTemplate: try template()) }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func rules(_ data: Data) throws -> [[String: Any]] {
        let root = try object(data)
        let profiles = try XCTUnwrap(root["profiles"] as? [[String: Any]])
        let profile = try XCTUnwrap(profiles.first { $0["name"] as? String == "Portable" })
        let complex = try XCTUnwrap(profile["complex_modifications"] as? [String: Any])
        return try XCTUnwrap(complex["rules"] as? [[String: Any]])
    }

    func testUntouchedKarabinerRetainsEverySourceRuleAndItsOrder() throws {
        let input = try source("karabiner/karabiner.json")
        let output = try settings().karabinerData(from: input)
        XCTAssertTrue(NSDictionary(dictionary: try object(input)).isEqual(to: try object(output)),
                      "Untouched defaults must be semantically identical to the source JSON")
        XCTAssertEqual(try rules(output).compactMap { $0["description"] as? String },
                       ["Chrome", "Alacritty", "Visual Studio Code", "Finder", "Example (disabled): right Command sends 5 then Z"])
    }

    func testEditingOneApplicationKeepsOtherRulesIntact() throws {
        let input = try source("karabiner/karabiner.json")
        var settings = try settings()
        let index = try XCTUnwrap(settings.entries.firstIndex { $0.id == "karabiner:finder" })
        settings.entries[index].shortcut = .init(key: "pageDown", modifiers: ["ctrl"])
        let output = try settings.karabinerData(from: input)
        let originalRules = try rules(input)
        let modifiedRules = try rules(output)
        XCTAssertEqual(modifiedRules.count, originalRules.count)
        for (before, after) in zip(originalRules, modifiedRules) where before["description"] as? String != "Finder" {
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: after))
        }
        let finder = try XCTUnwrap(modifiedRules.first { $0["description"] as? String == "Finder" })
        let manipulator = try XCTUnwrap((finder["manipulators"] as? [[String: Any]])?.first)
        XCTAssertEqual((manipulator["from"] as? [String: Any])?["key_code"] as? String, "page_down")
    }

    func testDisabledExampleIsShownDisabledAndCanActuallyBeEnabled() throws {
        let input = try source("karabiner/karabiner.json")
        var example = try XCTUnwrap(ShortcutSettings.bundledAdvancedKarabinerRules(from: input).first { !$0.enabled })
        example.enabled = true
        var settings = try settings()
        settings.updateAdvancedRule(example)
        let enabled = try XCTUnwrap(rules(settings.karabinerData(from: input)).first { $0["description"] as? String == example.id })
        XCTAssertNotEqual(enabled["enabled"] as? Bool, false)
    }

    func testOtherInstalledProfilesAndGlobalSettingsSurviveImport() throws {
        let input = try source("karabiner/karabiner.json")
        let personal: [String: Any] = ["name": "Personal", "selected": true, "simple_modifications": [["from": ["key_code": "a"], "to": [["key_code": "b"]]]]]
        let installed = try JSONSerialization.data(withJSONObject: ["global": ["show_in_menu_bar": false], "profiles": [personal]])
        let output = try settings().karabinerData(from: input, preserving: installed,
                                                 configDirectory: URL(fileURLWithPath: "/tmp/custom config"))
        let result = try object(output)
        XCTAssertEqual((result["global"] as? [String: Any])?["show_in_menu_bar"] as? Bool, false)
        let profiles = try XCTUnwrap(result["profiles"] as? [[String: Any]])
        XCTAssertEqual(profiles.count, 2)
        var expected = personal
        expected["selected"] = false
        XCTAssertTrue(NSDictionary(dictionary: profiles[0]).isEqual(to: expected))
        let text = String(decoding: output, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
        XCTAssertTrue(text.contains("/tmp/custom config/karabiner/scripts/"))
        XCTAssertFalse(text.contains("$HOME/.config/karabiner"))
        XCTAssertEqual(try settings().karabinerData(from: input, preserving: output,
                                                   configDirectory: URL(fileURLWithPath: "/tmp/custom config")), output)
    }

    func testInvalidShortcutDataThrowsInsteadOfCrashingDuringGeneration() throws {
        let input = try source("karabiner/karabiner.json")
        var settings = try settings()
        settings.entries.append(settings.entries[0])
        XCTAssertThrowsError(try settings.karabinerData(from: input))
        settings = try self.settings()
        let index = try XCTUnwrap(settings.entries.firstIndex { $0.provider == .karabiner })
        settings.entries[index].shortcut.modifiers = ["invalid"]
        XCTAssertThrowsError(try settings.karabinerData(from: input))
    }

    func testKarabinerPhysicalKeyNamesAndDisabledRaycast() throws {
        let mappings = ["left": "left_arrow", "rightSquareBracket": "close_bracket", "esc": "escape",
                        "backspace": "delete_or_backspace", "forwardDelete": "delete_forward",
                        "keypad7": "keypad_7", "keypadMultiply": "keypad_asterisk"]
        for (source, target) in mappings {
            XCTAssertEqual(WorkspaceShortcut(key: source).karabinerKeyCode, target)
        }
        var settings = try settings()
        let raycast = try XCTUnwrap(settings.entries.firstIndex { $0.provider == .raycast })
        settings.entries[raycast].enabled = false
        XCTAssertEqual(settings.raycastHotkey, "")
        XCTAssertFalse(settings.usesSpotlightKey)
    }

    func testLegacyAIIdentityMigratesWithoutChangingSavedFileOrCustomWorkspace() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        var layout = WorkspaceConfiguration.defaultLayout
        layout.workspaces[0].id = "chatgpt"
        try layout.save(to: paths)
        let original = try Data(contentsOf: WorkspaceConfiguration.path(in: paths))
        let loaded = try WorkspaceConfiguration.loadForEditing(from: paths)
        XCTAssertEqual(loaded.original.workspaces[0].id, "chatgpt")
        XCTAssertEqual(loaded.draft.workspaces[0].id, "ai")
        XCTAssertEqual(loaded.repairs.count, 1)
        XCTAssertEqual(try Data(contentsOf: WorkspaceConfiguration.path(in: paths)), original)
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths).workspaces[0].id, "ai")
        layout.workspaces[0].name = "My Assistant"
        XCTAssertTrue(layout.migrateLegacyAIWorkspace().isEmpty)
    }

    func testRenameAndRemovePreserveKeysRoutingAndMonitorAssignments() throws {
        var layout = WorkspaceConfiguration.defaultLayout
        let keys = Dictionary(uniqueKeysWithValues: layout.workspaces.enumerated().map { ($0.element.id, layout.shortcuts(at: $0.offset)) })
        try layout.renameWorkspace("2", to: "Research")
        XCTAssertEqual(layout.workspaces.first { $0.id == "research" }?.resolvedMonitor, .secondary)
        try layout.renameWorkspace("ai", to: "Assistant")
        layout.insertWorkspace("assistant", at: 5)
        layout.removeWorkspace("1")
        layout.addWorkspace()
        for (i, item) in layout.workspaces.enumerated() where keys[item.id] != nil {
            XCTAssertEqual(layout.shortcuts(at: i), keys[item.id])
        }
        let toml = try layout.aerospaceTOML(from: template())
        XCTAssertTrue(toml.contains("research = 'secondary'"))
        XCTAssertFalse(toml.contains("2 = 'secondary'"))
        XCTAssertTrue(toml.contains("move-node-to-workspace assistant"))
        XCTAssertFalse(toml.contains("chatgpt"))
        XCTAssertFalse(toml.contains("workspace ai'"))
        XCTAssertTrue(toml.contains("ru.keepcoder.Telegram"))
        let bar = try layout.sketchybarShell(from: String(decoding: source("sketchybar/sketchybarrc"), as: UTF8.self))
        XCTAssertTrue(bar.contains("assistant) printf"))
        XCTAssertFalse(bar.contains("chatgpt"))
    }

    func testGenerationPreservesNewSourceRulesInsteadOfHardCodingKnownApps() throws {
        let template = try self.template().replacingOccurrences(of: "# MONITOR ASSIGNMENTS", with: "[[on-window-detected]]\nif = 'test %{app-bundle-id} = com.example.Utility'\nrun = 'layout floating'\n\n# MONITOR ASSIGNMENTS")
        let generated = try WorkspaceConfiguration.defaultLayout.aerospaceTOML(from: template)
        XCTAssertTrue(generated.contains("com.example.Utility'\nrun = 'layout floating'"))
    }

    func testFailedEditorApplyRestoresProfilesAndBothSavedDrafts() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        let engine = try Engine(paths: paths, runner: FakeRunner(), appResolver: isolatedAppPath,
                                displayHelper: nil, tools: { _ in nil })
        let baseline = WorkspaceConfiguration.defaultLayout
        let shortcuts = try settings()
        try baseline.save(to: paths)
        try shortcuts.save(to: paths)
        _ = try engine.apply(Catalog.task("aerospace-profile"))
        let configFile = paths.config.appendingPathComponent("aerospace/aerospace.toml")
        let before = try Data(contentsOf: configFile)
        var draft = baseline
        try draft.renameWorkspace("ai", to: "Research")
        var shortcutDraft = shortcuts
        shortcutDraft.entries.removeAll { $0.id == "karabiner:finder" }
        XCTAssertThrowsError(try engine.applyConfiguration(layout: draft, shortcuts: shortcutDraft,
            tasks: Catalog.ordered(["aerospace-profile", "sketchybar-profile"], includingDependencies: false))) { error in
            XCTAssertTrue(String(describing: error).contains("Previous files and saved settings were restored"))
        }
        XCTAssertEqual(try Data(contentsOf: configFile), before)
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths), baseline)
        XCTAssertEqual(try ShortcutSettings.load(from: paths, aerospaceTemplate: template()), shortcuts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.config.appendingPathComponent("sketchybar").path))
    }

    func testFailedFirstApplyLeavesNoSavedDraftOrProfileBehind() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        let engine = try Engine(paths: paths, runner: FakeRunner(), displayHelper: nil, tools: { _ in nil })
        XCTAssertThrowsError(try engine.applyConfiguration(layout: .defaultLayout,
            tasks: Catalog.ordered(["aerospace-profile", "sketchybar-profile"], includingDependencies: false)))
        XCTAssertFalse(Journal.exists(WorkspaceConfiguration.path(in: paths)))
        XCTAssertFalse(Journal.exists(paths.config.appendingPathComponent("aerospace")))
    }
    func testFullSetupCommitsOnlyTheConfigurationWhoseProfileSucceeded() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        let engine = try Engine(paths: paths, runner: FakeRunner(), displayHelper: nil, tools: { _ in nil })
        let baseline = WorkspaceConfiguration.defaultLayout
        var draft = baseline
        try draft.renameWorkspace("ai", to: "Research")
        draft.barStyle.blurRadius = 15
        engine.draftLayout = draft
        var shortcuts = try settings()
        let finder = try XCTUnwrap(shortcuts.entries.firstIndex { $0.id == "karabiner:finder" })
        shortcuts.entries[finder].shortcut = .init(key: "q", modifiers: ["ctrl"])
        engine.draftShortcuts = shortcuts
        // Preparing and inspecting a full setup must not save any editor files.
        _ = try engine.state(Catalog.task("aerospace-profile"))
        XCTAssertFalse(Journal.exists(WorkspaceConfiguration.path(in: paths)))
        XCTAssertFalse(Journal.exists(ShortcutSettings.path(in: paths)))
        let record = try engine.apply(Catalog.task("aerospace-profile"))
        let applied = try WorkspaceConfiguration.load(from: paths)
        XCTAssertEqual(applied.workspaces, draft.workspaces)
        XCTAssertEqual(applied.barStyle, baseline.barStyle)
        let savedShortcuts = try ShortcutSettings.load(from: paths, aerospaceTemplate: template())
        XCTAssertEqual(savedShortcuts.entries.filter { $0.provider == .karabiner }, try settings().entries.filter { $0.provider == .karabiner })
        // A later failed bar task leaves the successful AeroSpace task recoverable.
        XCTAssertThrowsError(try engine.apply(Catalog.task("sketchybar-profile")))
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths), applied)
        try engine.journal.restore(record)
        XCTAssertFalse(Journal.exists(WorkspaceConfiguration.path(in: paths)))
        XCTAssertFalse(Journal.exists(paths.config.appendingPathComponent("aerospace")))
    }

    func testBarPaletteDriftIsDetectedRatherThanDeclaredVerified() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = Paths(home: home)
        let helper = home.appendingPathComponent("display-helper")
        try Data("test helper".utf8).write(to: helper)
        let engine = try Engine(paths: paths, runner: FakeRunner(), displayHelper: helper, tools: { _ in nil })
        let task = try Catalog.task("sketchybar-profile")
        _ = try engine.apply(task)
        XCTAssertEqual(try engine.state(task), .done)
        let colors = paths.config.appendingPathComponent("sketchybar/plugins/colors.sh")
        var text = try String(contentsOf: colors, encoding: .utf8)
        text = text.replacingOccurrences(of: "BAR_COLOR=0x35000000", with: "BAR_COLOR=0xffffffff")
        try text.write(to: colors, atomically: true, encoding: .utf8)
        XCTAssertEqual(try engine.state(task), .ready)
    }

}
