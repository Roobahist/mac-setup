import XCTest
@testable import MacSetupCore

final class SelectedConfigurationTests: XCTestCase {
    private func settings() throws -> ShortcutSettings {
        let template = try String(contentsOf: Paths().profile.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
        return .defaults(aerospaceTemplate: template)
    }

    func testAppOnlySelectionDoesNotSaveUnrelatedDrafts() throws {
        let original = WorkspaceConfiguration.defaultLayout
        let saved = try settings()
        var draft = original
        draft.workspaces[0].name = ""
        let selected = SelectedConfiguration(taskIDs: ["obsidian"], draftLayout: draft,
            draftShortcuts: .init(entries: []), savedLayout: original, savedShortcuts: saved)
        XCTAssertNil(selected.layout)
        XCTAssertNil(selected.shortcuts)
    }

    func testBarOnlySelectionKeepsSavedRoutingAndKeyboard() throws {
        let original = WorkspaceConfiguration.defaultLayout
        let saved = try settings()
        var draft = original
        try draft.renameWorkspace("ai", to: "Unsaved Research")
        draft.keymap.switchModifiers = ["ctrl"]
        draft.barStyle.blurRadius = 20
        let selected = SelectedConfiguration(taskIDs: ["sketchybar-profile"], draftLayout: draft,
            draftShortcuts: .init(entries: []), savedLayout: original, savedShortcuts: saved)
        let layout = try XCTUnwrap(selected.layout)
        XCTAssertEqual(layout.workspaces, original.workspaces)
        XCTAssertEqual(layout.keymap, original.keymap)
        XCTAssertEqual(layout.barStyle.blurRadius, 20)
        XCTAssertNil(selected.shortcuts)
    }

    func testRaycastOnlySelectionPreservesUnsavedOtherProviderChanges() throws {
        let layout = WorkspaceConfiguration.defaultLayout
        let saved = try settings()
        var draft = saved
        draft.entries.removeAll { $0.provider == .karabiner }
        let index = try XCTUnwrap(draft.entries.firstIndex { $0.provider == .raycast })
        draft.entries[index].shortcut = .init(key: "space", modifiers: ["ctrl"])
        let selected = SelectedConfiguration(taskIDs: ["raycast-profile"], draftLayout: layout,
            draftShortcuts: draft, savedLayout: layout, savedShortcuts: saved)
        let shortcuts = try XCTUnwrap(selected.shortcuts)
        XCTAssertEqual(shortcuts.entries.filter { $0.provider == .karabiner }, saved.entries.filter { $0.provider == .karabiner })
        XCTAssertEqual(shortcuts.raycastHotkey, "Control-49")
        XCTAssertNil(selected.layout)
    }

    func testUnchangedSelectionDoesNotInventDraftChanges() throws {
        let layout = WorkspaceConfiguration.defaultLayout
        let shortcuts = try settings()
        for id in ["aerospace-profile", "karabiner-profile", "raycast-profile"] {
            let selected = SelectedConfiguration(taskIDs: [id], draftLayout: layout, draftShortcuts: shortcuts,
                                                  savedLayout: layout, savedShortcuts: shortcuts)
            XCTAssertEqual(selected.shortcuts, shortcuts)
        }
    }
}
