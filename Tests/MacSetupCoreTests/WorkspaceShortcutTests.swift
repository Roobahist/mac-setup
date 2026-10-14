import XCTest
@testable import MacSetupCore

final class WorkspaceShortcutTests: XCTestCase {
    private func template() throws -> String {
        try String(contentsOf: Paths().profile.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
    }

    func testSharedModifiersAndWorkspaceKeys() throws {
        let config = WorkspaceConfiguration.defaultLayout
        XCTAssertEqual(config.shortcuts(at: 0).switchTo?.binding, "alt-backtick")
        XCTAssertEqual(config.shortcuts(at: 0).moveWindow?.binding, "alt-shift-backtick")
        var extended = config
        extended.workspaces.append(.init(id: "extra", name: "Extra", glyph: "star"))
        XCTAssertNil(extended.shortcuts(at: 13).switchTo)
        try extended.validate(aerospaceTemplate: template())
    }

    func testGlobalModifierChangeAppliesToBothActions() throws {
        var config = WorkspaceConfiguration.defaultLayout
        config.keymap = .init(switchModifiers: ["ctrl", "alt"], moveModifiers: ["ctrl", "alt", "shift"])
        config.workspaces[0].shortcutKey = "r"
        config.workspaces.swapAt(0, 1)
        XCTAssertEqual(config.shortcuts(at: 1).switchTo?.binding, "ctrl-alt-r")
        XCTAssertEqual(config.shortcuts(at: 1).moveWindow?.binding, "ctrl-alt-shift-r")
        let toml = try config.aerospaceTOML(from: template())
        XCTAssertTrue(toml.contains("ctrl-alt-r = 'workspace chatgpt'"))
        XCTAssertTrue(toml.contains("ctrl-alt-shift-r = ['move-node-to-workspace chatgpt'"))
    }

    func testInsertionMovesCardWithoutReplacingIt() throws {
        var config = WorkspaceConfiguration.defaultLayout
        let original = config.workspaces
        let originalKeys = config.workspaces.indices.map {
            config.shortcuts(at: $0).switchTo?.key ?? ""
        }
        config.insertWorkspace("chatgpt", at: 3)
        XCTAssertEqual(config.workspaces.count, original.count)
        XCTAssertEqual(config.workspaces[2].id, original[0].id)
        XCTAssertEqual(config.workspaces[2].name, original[0].name)
        XCTAssertEqual(config.shortcuts(at: 2).switchTo?.key, originalKeys[0])
        config.insertWorkspace("chatgpt", at: 0)
        XCTAssertEqual(config.workspaces.map(\.id), original.map(\.id))
        for (i, item) in config.workspaces.enumerated() {
            XCTAssertEqual(item.name, original[i].name)
            XCTAssertEqual(item.glyph, original[i].glyph)
            XCTAssertEqual(item.apps, original[i].apps)
            XCTAssertEqual(config.shortcuts(at: i).switchTo?.key ?? "", originalKeys[i])
        }
    }

    func testLegacyShortcutJSONUsesSharedModifiers() throws {
        let old = Data("""
        {"workspaces":[{"id":"research","name":"Research","glyph":"book","apps":[],
        "shortcuts":{"switchTo":{"key":"r","modifiers":["ctrl","alt"]},
        "moveWindow":{"key":"f12","modifiers":["cmd","shift"]}}}]}
        """.utf8)
        let config = try JSONDecoder().decode(WorkspaceConfiguration.self, from: old)
        XCTAssertEqual(config.keymap, .init())
        XCTAssertEqual(config.shortcuts(at: 0).switchTo?.binding, "alt-r")
        XCTAssertEqual(config.shortcuts(at: 0).moveWindow?.binding, "alt-shift-r")
        try config.validate(aerospaceTemplate: template())
    }

    func testDuplicateAndReservedKeysAreRejected() throws {
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces[0].shortcutKey = "1"
        XCTAssertThrowsError(try config.validate())
        config.workspaces[0].shortcutKey = "left"
        XCTAssertThrowsError(try config.validate(aerospaceTemplate: template()))
        config.workspaces[0].shortcutKey = "r"
        config.keymap = .init(switchModifiers: ["alt"], moveModifiers: ["alt"])
        XCTAssertThrowsError(try config.validate())
        config.keymap = .init(switchModifiers: ["alt"], moveModifiers: ["ctrl", "alt", "shift"])
        try config.validate(aerospaceTemplate: template())
    }

    func testDisabledAndUnsupportedKey() throws {
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces[0].shortcutKey = ""
        XCTAssertNil(config.shortcuts(at: 0).switchTo)
        config.workspaces[0].shortcutKey = "invalid-command"
        XCTAssertThrowsError(try config.validate())
    }
}
