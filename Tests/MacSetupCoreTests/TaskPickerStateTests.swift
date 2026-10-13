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

    func testSelectingOneTaskDoesNotSelectOtherTasks() {
        var state = TaskPickerState(preset: .minimal)
        let before = state.selected
        state.toggle("sketchybar-start")
        XCTAssertEqual(state.selected, before.union(["sketchybar-start"]))
        XCTAssertNil(state.preset)
    }

    func testRemovingEachTaskChangesOnlyThatTask() {
        for task in Catalog.tasks {
            var state = TaskPickerState()
            let before = state.selected
            state.toggle(task.id)
            XCTAssertEqual(state.selected, before.subtracting([task.id]), task.id)
            XCTAssertNil(state.preset)
            state.toggle(task.id)
            XCTAssertEqual(state.selected, before, task.id)
        }
    }

    func testBulkToggleDoesNotAffectTasksOutsideTheVisibleCategory() {
        var state = TaskPickerState()
        state.cycleCategory() // Tools
        let before = state.selected
        let visible = Set(state.visibleTasks.map(\.id))
        state.toggleVisible()
        XCTAssertEqual(state.selected, before.subtracting(visible))
        state.toggleVisible()
        XCTAssertEqual(state.selected, before)
    }

    func testCustomExecutionOrdersOnlyTheSelectedTasks() throws {
        let ids = ["sketchybar-start", "sketchybar-profile"]
        let ordered = try Catalog.ordered(ids, includingDependencies: false).map(\.id)
        XCTAssertEqual(ordered, ["sketchybar-profile", "sketchybar-start"])
        XCTAssertEqual(Set(ordered), Set(ids))
        XCTAssertTrue(try Catalog.ordered(ids).count > ids.count)
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
