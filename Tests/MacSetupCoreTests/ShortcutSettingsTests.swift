import XCTest
@testable import MacSetupCore

final class ShortcutSettingsTests: XCTestCase {
    private func aerospaceTemplate() throws -> String {
        try String(contentsOf: Paths().profile.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
    }

    private func settings() throws -> ShortcutSettings {
        .defaults(aerospaceTemplate: try aerospaceTemplate())
    }

    func testWorkspaceValidationIgnoresInvalidKarabinerAction() throws {
        let config = WorkspaceConfiguration.defaultLayout
        let template = try String(contentsOf:
            Paths().profile.appendingPathComponent("aerospace/aerospace.toml"),
            encoding: .utf8)
        var settings = try ShortcutSettings.load(from: Paths(), aerospaceTemplate: template)
        settings.entries.append(ManagedShortcut(id: "bad-app", provider: .karabiner,
            action: "open:", shortcut: WorkspaceShortcut(key: "f19", modifiers: ["ctrl"]),
            enabled: false))
        // This unrelated editor error is reported only in Keyboard Shortcuts.
        XCTAssertThrowsError(try settings.validate(workspaces: config, aerospaceTemplate: template))
        XCTAssertNoThrow(try settings.validateWorkspaceBindings(config, aerospaceTemplate: template))
    }

    func testAllProvidersArePopulatedAndDefaultsDoNotConflict() throws {
        let settings = try settings()
        XCTAssertTrue(settings.entries.contains { $0.provider == .aerospace && $0.action == "'fullscreen'" })
        XCTAssertTrue(settings.entries.contains { $0.provider == .karabiner && $0.action == "Finder" })
        XCTAssertTrue(settings.entries.contains { $0.provider == .raycast && $0.action == "launcher" })
        XCTAssertEqual(settings.raycastHotkey, "Option-15")
        XCTAssertTrue(settings.entries.contains {
            $0.provider == .karabiner && $0.action == "Alacritty"
        })
        XCTAssertGreaterThan(settings.entries.filter { $0.provider == .aerospace }.count, 10)
        try settings.validate(workspaces: .defaultLayout, aerospaceTemplate: aerospaceTemplate())
    }

    func testGeneratedAeroSpaceProfileNeverRedeclaresModifierPermutations() throws {
        let source = try aerospaceTemplate()
        let managed = try settings().aerospaceTemplateApplying(to: source)
        XCTAssertFalse(managed.contains("alt-ctrl-down ="))
        XCTAssertTrue(managed.contains("ctrl-alt-down ="))
        let generated = try WorkspaceConfiguration.defaultLayout.aerospaceTOML(from: managed)
        try WorkspaceConfiguration.verifyGeneratedBindings(generated)
        let count = generated.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("ctrl-alt-down =") }.count
        XCTAssertEqual(count, 1)
        let broken = generated.replacingOccurrences(
            of: "ctrl-alt-down = 'move down'",
            with: "ctrl-alt-down = 'move down'\nalt-ctrl-down = 'move down'"
        )
        XCTAssertThrowsError(try WorkspaceConfiguration.verifyGeneratedBindings(broken))
    }

    func testModifiedAerospaceBindingAppearsInGeneratedProfile() throws {
        var settings = try settings()
        let index = try XCTUnwrap(settings.entries.firstIndex {
            $0.provider == .aerospace && $0.action == "'fullscreen'"
        })
        settings.entries[index].shortcut = .init(key: "f", modifiers: ["ctrl", "alt"])
        try settings.validate(workspaces: .defaultLayout, aerospaceTemplate: aerospaceTemplate())
        let result = try WorkspaceConfiguration.defaultLayout.aerospaceTOML(
            from: settings.aerospaceTemplateApplying(to: aerospaceTemplate())
        )
        XCTAssertTrue(result.contains("ctrl-alt-f = 'fullscreen'"))
        XCTAssertFalse(result.components(separatedBy: "\n").contains("alt-f = 'fullscreen'"))
    }

    func testDisablingAndRemovingAeroSpaceBinding() throws {
        var settings = try settings()
        let index = try XCTUnwrap(settings.entries.firstIndex { $0.provider == .aerospace && $0.action == "'fullscreen'" })
        settings.entries[index].enabled = false
        XCTAssertFalse(settings.aerospaceTemplateApplying(to: try aerospaceTemplate()).contains("alt-f = 'fullscreen'"))
        settings.entries.remove(at: index)
        try settings.validate(workspaces: .defaultLayout, aerospaceTemplate: aerospaceTemplate())
    }

    func testKarabinerRewritesOnlySimpleShortcuts() throws {
        let file = Paths().profile.appendingPathComponent("karabiner/karabiner.json")
        let input = try Data(contentsOf: file)
        var settings = try settings()
        settings.entries.append(.init(provider: .karabiner, action: "open:com.apple.Safari",
                                      shortcut: .init(key: "s", modifiers: ["ctrl", "alt"])))
        try settings.validate(workspaces: .defaultLayout, aerospaceTemplate: aerospaceTemplate())
        let output = try settings.karabinerData(from: input)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let profiles = try XCTUnwrap(obj["profiles"] as? [[String: Any]])
        let profile = try XCTUnwrap(profiles.first { ($0["name"] as? String) == "Portable" })
        let modifications = try XCTUnwrap(profile["complex_modifications"] as? [String: Any])
        let rules = try XCTUnwrap(modifications["rules"] as? [[String: Any]])
        XCTAssertTrue(rules.contains { ($0["description"] as? String) == "Chrome" })
        XCTAssertTrue(rules.contains { ($0["description"] as? String)?.contains("Example (disabled)") == true })
        XCTAssertFalse(rules.contains { ($0["description"] as? String) == "Mac Setup: Custom shortcuts" })
        for name in ["Alacritty", "Visual Studio Code", "Finder", "Open com.apple.Safari"] {
            let rule = try XCTUnwrap(rules.first { ($0["description"] as? String) == name })
            XCTAssertEqual((rule["manipulators"] as? [[String: Any]])?.count, 1)
        }
        let encoded = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(encoded.contains("com.apple.Safari"))
        XCTAssertTrue(encoded.contains("open_new_window.sh"))
    }

    func testCrossProviderAndWorkspaceConflictsAreRejected() throws {
        var settings = try settings()
        let raycast = try XCTUnwrap(settings.entries.firstIndex { $0.provider == .raycast })
        settings.entries[raycast].shortcut = .init(key: "1", modifiers: ["alt"])
        XCTAssertThrowsError(try settings.validate(workspaces: .defaultLayout,
                                                   aerospaceTemplate: aerospaceTemplate()))
        settings.entries[raycast].shortcut = .init(key: "space", modifiers: ["alt"])
        try settings.validate(workspaces: .defaultLayout, aerospaceTemplate: aerospaceTemplate())
        XCTAssertEqual(settings.raycastHotkey, "Option-49")
        XCTAssertFalse(settings.usesSpotlightKey)
    }

    func testAdvancedKarabinerRuleCanBeDisabledAndEdited() throws {
        let file = Paths().profile.appendingPathComponent("karabiner/karabiner.json")
        let data = try Data(contentsOf: file)
        let advanced = ShortcutSettings.bundledAdvancedKarabinerRules(from: data)
        let original = try XCTUnwrap(advanced.first(where: { $0.id == "Chrome" }))
        var settings = try settings()
        var disabled = original
        disabled.enabled = false
        settings.updateAdvancedRule(disabled)
        try settings.validate(workspaces: .defaultLayout, aerospaceTemplate: aerospaceTemplate())
        let suppressed = try settings.karabinerData(from: data)
        let suppressedText = String(decoding: suppressed, as: UTF8.self)
        XCTAssertTrue(suppressedText.contains("\"description\" : \"Chrome\""))
        XCTAssertTrue(suppressedText.contains("\"enabled\" : false"))

        var invalid = original
        invalid.json = "{\"description\":\"Chrome\",\"manipulators\":[]}"
        settings.updateAdvancedRule(invalid)
        XCTAssertThrowsError(try settings.validate(workspaces: .defaultLayout,
                                                   aerospaceTemplate: aerospaceTemplate()))
        settings.updateAdvancedRule(original)
        try settings.validate(workspaces: .defaultLayout, aerospaceTemplate: aerospaceTemplate())
    }

    func testLegacyDefaultMigrationPreservesCustomBindings() throws {
        let template = try aerospaceTemplate()
        var settings = ShortcutSettings.defaults(aerospaceTemplate: template)
        settings.configurationVersion = nil
        let raycast = try XCTUnwrap(settings.entries.firstIndex(where: { $0.id == "raycast:launcher" }))
        settings.entries[raycast].shortcut = .init(key: "space", modifiers: ["cmd"])
        settings.migrateBundledDefaults(installedAlacritty: false)
        XCTAssertEqual(settings.raycastHotkey, "Command-49")
        XCTAssertEqual(settings.configurationVersion, 3)
        var custom = settings
        custom.entries[raycast].shortcut = .init(key: "t", modifiers: ["cmd"])
        custom.migrateBundledDefaults(installedAlacritty: false)
        XCTAssertEqual(custom.raycastHotkey, "Command-17")
    }

    func testShortcutPersistenceAndUnsupportedKarabinerAction() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        var settings = try settings()
        try settings.save(to: paths)
        XCTAssertEqual(try ShortcutSettings.load(from: paths, aerospaceTemplate: aerospaceTemplate()), settings)
        settings.entries.append(.init(provider: .karabiner, action: "open:bad id",
                                      shortcut: .init(key: "r", modifiers: ["ctrl"])))
        XCTAssertThrowsError(try settings.validate(workspaces: .defaultLayout,
                                                   aerospaceTemplate: aerospaceTemplate()))
    }
}
