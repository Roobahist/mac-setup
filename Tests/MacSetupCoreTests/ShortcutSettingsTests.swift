import XCTest
@testable import MacSetupCore

final class ShortcutSettingsTests: XCTestCase {
    private func aerospaceTemplate() throws -> String {
        try String(contentsOf: Paths().profile.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
    }

    private func settings() throws -> ShortcutSettings {
        .defaults(aerospaceTemplate: try aerospaceTemplate())
    }

    func testAllProvidersArePopulatedAndDefaultsDoNotConflict() throws {
        let settings = try settings()
        XCTAssertTrue(settings.entries.contains { $0.provider == .aerospace && $0.action == "'fullscreen'" })
        XCTAssertTrue(settings.entries.contains { $0.provider == .karabiner && $0.action == "Finder" })
        XCTAssertTrue(settings.entries.contains { $0.provider == .raycast && $0.action == "launcher" })
        XCTAssertGreaterThan(settings.entries.filter { $0.provider == .aerospace }.count, 10)
        try settings.validate(workspaces: .defaultLayout, aerospaceTemplate: aerospaceTemplate())
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
        XCTAssertFalse(result.contains("alt-f = 'fullscreen'"))
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
        let custom = try XCTUnwrap(rules.first { ($0["description"] as? String) == "Mac Setup: Custom shortcuts" })
        let manipulators = try XCTUnwrap(custom["manipulators"] as? [[String: Any]])
        XCTAssertEqual(manipulators.count, 4)
        let encoded = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(encoded.contains("/usr/bin/open -b com.apple.Safari"))
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
