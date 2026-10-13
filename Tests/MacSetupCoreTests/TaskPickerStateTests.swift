import XCTest
@testable import MacSetupCore

final class TaskPickerStateTests: XCTestCase {
    func testCompletePresetIncludesWatcherPermissionsAndExcludesRemovedDockTask() {
        let state = TaskPickerState()
        XCTAssertTrue(state.selected.contains("sketchybar-start"))
        XCTAssertTrue(state.selected.contains("wallpaper-watcher"))
        XCTAssertTrue(state.selected.contains("wallpaper-access"))
        XCTAssertFalse(state.selected.contains("dock-special-items"))
    }

    func testSelectingDependentTaskIncludesPrerequisites() {
        var state = TaskPickerState(preset: .minimal)
        state.toggle("sketchybar-start")
        for id in ["homebrew", "fonts", "aerospace", "aerospace-profile",
                   "aerospace-access", "sketchybar", "sketchybar-profile", "sketchybar-start"] {
            XCTAssertTrue(state.selected.contains(id), id)
        }
    }

    func testRemovingPrerequisiteRemovesSelectedDependents() {
        var state = TaskPickerState()
        state.toggle("aerospace")
        XCTAssertFalse(state.selected.contains("aerospace"))
        XCTAssertFalse(state.selected.contains("sketchybar-profile"))
        XCTAssertFalse(state.selected.contains("sketchybar-start"))
        XCTAssertFalse(state.selected.contains("aerospace-access"))
        XCTAssertTrue(state.selected.contains("raycast"))
    }

    func testCategoryFilterAndSearchDoNotDiscardSelections() {
        var state = TaskPickerState(preset: .developer)
        let original = state.selected
        state.cycleCategory()
        XCTAssertEqual(state.category, "Tools")
        state.appendSearch("f")
        XCTAssertTrue(state.visibleTasks.allSatisfy { $0.category == "Tools" })
        state.clearSearch()
        state.cycleCategory()
        XCTAssertEqual(state.selected, original)
    }

    func testMovementAndSearchHandleNoResults() {
        var state = TaskPickerState()
        for letter in "not-a-real-configuration" { state.appendSearch(letter) }
        XCTAssertTrue(state.visibleTasks.isEmpty)
        state.move(1)
        XCTAssertNil(state.focusedTask)
        state.clearSearch()
        state.move(-1)
        XCTAssertEqual(state.focusedTask?.id, "wallpaper-access")
    }

    func testMinimalAndDeveloperPresetsAreDistinct() {
        var state = TaskPickerState(preset: .minimal)
        XCTAssertTrue(state.selected.contains("dark-mode"))
        XCTAssertFalse(state.selected.contains("atuin"))
        state.choose(.developer)
        XCTAssertTrue(state.selected.contains("atuin-shell"))
        XCTAssertFalse(state.selected.contains("dark-mode"))
        XCTAssertEqual(state.preset, .developer)
    }

    func testToggleAllVisibleAndZeroSelectionAreSupported() {
        var state = TaskPickerState()
        state.toggleVisible()
        XCTAssertEqual(state.selectedCount, 0)
        state.toggleVisible()
        XCTAssertEqual(state.selectedCount, Catalog.tasks.count)
    }
}
