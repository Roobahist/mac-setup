import XCTest
@testable import MacSetupCore

final class WorkspaceShortcutTests: XCTestCase {
    private func template(_ file: String = "aerospace/aerospace.toml") throws -> String {
        try String(contentsOf: Paths().profile.appendingPathComponent(file), encoding: .utf8)
    }

    func testAdditionalWorkspacesStayPersistentWithoutInventingShortcuts() throws {
        var config = WorkspaceConfiguration.defaultLayout
        for n in 14...30 {
            config.workspaces.append(.init(id: "extra\(n)", name: "Extra \(n)", glyph: "star"))
        }
        let toml = try config.aerospaceTOML(from: template())
        XCTAssertTrue(toml.contains("\"extra30\""))
        XCTAssertFalse(toml.contains("= 'workspace extra30'"))
        XCTAssertNil(config.shortcuts(at: 29).switchTo)
        let bar = try config.sketchybarShell(from: template("sketchybar/sketchybarrc"))
        XCTAssertTrue(bar.contains("extra30) printf"))
    }

    func testCustomLetterAndFunctionShortcutsRenderIndependentActions() throws {
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces.append(.init(id: "research", name: "Research", glyph: "book", shortcuts: .init(
            switchTo: .init(key: "r", modifiers: ["ctrl", "alt"]),
            moveWindow: .init(key: "f12", modifiers: ["cmd", "shift"]))))
        let toml = try config.aerospaceTOML(from: template())
        XCTAssertTrue(toml.contains("ctrl-alt-r = 'workspace research'"))
        XCTAssertTrue(toml.contains("cmd-shift-f12 = ['move-node-to-workspace research'"))
        XCTAssertTrue(toml.contains("alt-1 = 'workspace 1'"))
        XCTAssertTrue(toml.contains("alt-shift-1 = ['move-node-to-workspace 1'"))
        XCTAssertTrue(toml.contains("alt-f = 'fullscreen'"))
    }

    func testCustomShortcutStaysWithWorkspaceWhenReordered() throws {
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces[0].shortcuts = .init(switchTo: .init(key: "a", modifiers: ["ctrl", "alt"]))
        config.workspaces.swapAt(0, 1)
        let toml = try config.aerospaceTOML(from: template())
        XCTAssertTrue(toml.contains("ctrl-alt-a = 'workspace chatgpt'"))
        XCTAssertTrue(toml.contains("alt-backtick = 'workspace 1'"))
        XCTAssertFalse(toml.contains("alt-shift-1 = ['move-node-to-workspace chatgpt'"))
    }

    func testNoShortcutChoicePersistsAndOldJSONRetainsDefaults() throws {
        let oldJSON = Data("""
        {"workspaces":[{"id":"research","name":"Research","glyph":"book","apps":[]}]}
        """.utf8)
        var config = try JSONDecoder().decode(WorkspaceConfiguration.self, from: oldJSON)
        XCTAssertNil(config.workspaces[0].shortcuts)
        XCTAssertEqual(config.shortcuts(at: 0).switchTo?.binding, "alt-backtick")
        config.workspaces[0].shortcuts = .init()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        try config.save(to: paths)
        let saved = try WorkspaceConfiguration.load(from: paths)
        XCTAssertEqual(saved, config)
        XCTAssertNil(saved.shortcuts(at: 0).switchTo)
        XCTAssertNil(saved.shortcuts(at: 0).moveWindow)
        XCTAssertFalse(try saved.aerospaceTOML(from: template()).contains("= 'workspace research'"))
    }

    func testDuplicateModifiersAreCanonicalizedForConflictChecks() throws {
        var config = WorkspaceConfiguration.defaultLayout
        config.workspaces[0].shortcuts = .init(switchTo: .init(key: "r", modifiers: ["alt", "ctrl"]))
        config.workspaces[1].shortcuts = .init(moveWindow: .init(key: "r", modifiers: ["ctrl", "alt"]))
        XCTAssertThrowsError(try config.validate())
        config.workspaces[1].shortcuts = .init(switchTo: .init(key: "1"), moveWindow: .init(key: "1"))
        XCTAssertThrowsError(try config.validate())
    }

    func testReservedProfileActionsCannotBeOverwritten() throws {
        var config = WorkspaceConfiguration.defaultLayout
        for shortcut in [WorkspaceShortcut(key: "f"), .init(key: "left", modifiers: ["ctrl", "alt"]),
                         .init(key: "tab", modifiers: ["alt", "shift"])] {
            config.workspaces[0].shortcuts = .init(switchTo: shortcut)
            XCTAssertThrowsError(try config.aerospaceTOML(from: template()))
        }
        config.workspaces[0].shortcuts = .init(switchTo: .init(key: "r", modifiers: ["ctrl", "alt"]))
        let updated = try template().replacingOccurrences(of: "# Resize\n", with: "# Resize\nalt-ctrl-r = 'resize width -25'\n")
        XCTAssertThrowsError(try config.aerospaceTOML(from: updated))
    }

    func testConflictsCanBeRepairedOneWorkspaceAtATime() throws {
        var config = WorkspaceConfiguration.defaultLayout
        for (index, key) in ["r", "r", "t", "t"].enumerated() {
            config.workspaces[index].shortcuts = .init(switchTo: .init(key: key, modifiers: ["ctrl", "alt"]))
        }
        XCTAssertThrowsError(try config.validate(checkingShortcutsFor: config.workspaces[0].id))
        config.workspaces[0].shortcuts?.switchTo?.key = "g"
        try config.validate(aerospaceTemplate: template(), checkingShortcutsFor: config.workspaces[0].id)
        XCTAssertThrowsError(try config.validate())
        config.workspaces[2].shortcuts?.switchTo?.key = "y"
        try config.validate(aerospaceTemplate: template())
    }

    func testInvalidKeysAndModifiersAreRejectedBeforeGeneration() throws {
        var config = WorkspaceConfiguration.defaultLayout
        for shortcut in [WorkspaceShortcut(key: "r'; injected = 'command"),
                         .init(key: "r", modifiers: []), .init(key: "r", modifiers: ["hyper"]),
                         .init(key: "r", modifiers: ["ctrl", "ctrl"])] {
            config.workspaces[0].shortcuts = .init(switchTo: shortcut)
            XCTAssertThrowsError(try config.validate())
        }
        for key in ["leftSquareBracket", "keypadPlus", "f20", "pageUp"] {
            try WorkspaceShortcut(key: key, modifiers: ["cmd", "ctrl", "alt", "shift"]).validate()
        }
    }
}
