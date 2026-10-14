import XCTest
@testable import MacSetupCore

final class TaskPickerStateTests: XCTestCase {
    func testTomitoIsOptionalInTheDefaultPresets() throws {
        let complete = TaskPickerState(preset: .complete)
        let productivity = TaskPickerState(preset: .productivity)
        let developer = TaskPickerState(preset: .developer)
        XCTAssertTrue(complete.selected.contains("tomito"))
        XCTAssertTrue(productivity.selected.contains("tomito"))
        XCTAssertFalse(developer.selected.contains("tomito"))
        var edited = complete
        edited.available = Set(Catalog.tasks.map(\.id))
        edited.toggle("tomito")
        XCTAssertFalse(edited.selected.contains("tomito"))
        XCTAssertTrue(edited.selected.contains("aerospace-profile"))
    }

    func testCompletePresetIncludesWatcherPermissionsAndExcludesRemovedDockTask() {
        let state = TaskPickerState()
        XCTAssertTrue(state.selected.contains("sketchybar-start"))
        XCTAssertTrue(state.selected.contains("wallpaper-watcher"))
        XCTAssertTrue(state.selected.contains("wallpaper-access"))
        XCTAssertFalse(state.selected.contains("dock-special-items"))
    }

    func testSelectingOneTaskDoesNotSelectOtherTasks() {
        var state = TaskPickerState(preset: .minimal)
        state.available = Set(Catalog.tasks.map(\.id))
        let before = state.selected
        state.toggle("sketchybar-start")
        XCTAssertEqual(state.selected, before.union(["sketchybar-start"]))
        XCTAssertNil(state.preset)
    }

    func testRemovingEachTaskChangesOnlyThatTask() {
        for task in Catalog.tasks {
            var state = TaskPickerState()
            state.available = Set(Catalog.tasks.map(\.id))
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
        state.available = Set(Catalog.tasks.map(\.id))
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

    func testMissingHomebrewCascadesButInstalledHomebrewDoesNot() {
        var missing = TaskPickerState()
        missing.toggle("homebrew")
        XCTAssertFalse(missing.selected.contains("fonts"))
        XCTAssertFalse(missing.selected.contains("sketchybar-start"))
        XCTAssertTrue(missing.selected.contains("dark-mode"))
        var installed = TaskPickerState()
        installed.available = ["homebrew"]
        let before = installed.selected
        installed.toggle("homebrew")
        XCTAssertEqual(installed.selected, before.subtracting(["homebrew"]))
    }

    func testInstalledAppKeepsItsChildrenActiveWhenHomebrewIsMissing() {
        var state = TaskPickerState()
        state.available = ["aerospace"]
        state.toggle("homebrew")
        XCTAssertFalse(state.selected.contains("aerospace"))
        XCTAssertTrue(state.selected.contains("aerospace-profile"))
        XCTAssertTrue(state.selected.contains("aerospace-access"))
    }

    func testSelectingChildAddsOnlyMissingParents() {
        var state = TaskPickerState(preset: .minimal)
        state.available = ["homebrew", "sketchybar-profile", "aerospace-access"]
        state.toggle("homebrew")
        state.toggle("sketchybar-start")
        XCTAssertTrue(state.selected.contains("sketchybar-start"))
        XCTAssertFalse(state.selected.contains("homebrew"))
        XCTAssertFalse(state.selected.contains("sketchybar-profile"))
        var missing = TaskPickerState(preset: .minimal)
        missing.toggle("homebrew")
        missing.toggle("sketchybar-start")
        XCTAssertTrue(missing.selected.contains("homebrew"))
        XCTAssertTrue(missing.selected.contains("sketchybar-profile"))
    }

    func testFailedInspectionDoesNotGuessThatAParentIsMissing() {
        var state = TaskPickerState()
        state.unknown = ["homebrew"]
        let before = state.selected
        state.toggle("homebrew")
        XCTAssertEqual(state.selected, before.subtracting(["homebrew"]))
        XCTAssertFalse(state.available.contains("homebrew"))
    }

    func testUpdateMarkerIsExplicitAndRemovedWithSelection() {
        var state = TaskPickerState()
        state.available = ["homebrew"]
        XCTAssertTrue(state.updates.isEmpty)
        state.toggleUpdate("homebrew")
        XCTAssertEqual(state.updates, ["homebrew"])
        state.toggle("homebrew")
        XCTAssertTrue(state.updates.isEmpty)
        state.toggleUpdate("dark-mode")
        XCTAssertTrue(state.updates.isEmpty)
    }

    func testHierarchyGroupsChildrenWithoutDuplicatingSharedDependencies() {
        let state = TaskPickerState()
        let ids = state.visibleTasks.map(\.id)
        XCTAssertEqual(Set(ids).count, Catalog.tasks.count)
        XCTAssertEqual(ids.count, Catalog.tasks.count)
        XCTAssertEqual(ids.first, "homebrew")
        XCTAssertEqual(ids[1], "fonts")
        XCTAssertLessThan(ids.firstIndex(of: "aerospace")!, ids.firstIndex(of: "aerospace-profile")!)
        XCTAssertLessThan(ids.firstIndex(of: "aerospace-profile")!, ids.firstIndex(of: "aerospace-access")!)
        XCTAssertEqual(state.hierarchyPrefix(for: try! Catalog.task("homebrew")), "")
        XCTAssertEqual(state.hierarchyPrefix(for: try! Catalog.task("fonts")), "├── ")
        XCTAssertEqual(state.hierarchyPrefix(for: try! Catalog.task("aerospace-access")), "│       └── ")
        XCTAssertEqual(state.hierarchyPrefix(for: try! Catalog.task("wallpaper-access")), "        └── ")
        XCTAssertEqual(state.hierarchyPrefix(for: try! Catalog.task("aerospace-profile")), "│   └── ")
    }

    func testCompletedChildGroupsHaveSpacersWithContinuingGuides() throws {
        let state = TaskPickerState()
        XCTAssertEqual(state.hierarchySpacer(after: try Catalog.task("aerospace-access"), before: try Catalog.task("sketchybar")), "│")
        XCTAssertEqual(state.hierarchySpacer(after: try Catalog.task("wallpaper-access"), before: try Catalog.task("dotfiles-linked")), "")
        XCTAssertEqual(state.hierarchySpacer(after: try Catalog.task("fonts"), before: try Catalog.task("aerospace")), "│")
        XCTAssertEqual(state.hierarchySpacer(after: try Catalog.task("homebrew"), before: try Catalog.task("fonts")), "│")
    }

    func testFilteredChildrenRemainVisibleWithTheirParentReferences() {
        var state = TaskPickerState()
        for letter in "sketchybar-profile" { state.appendSearch(letter) }
        XCTAssertEqual(state.visibleTasks.map(\.id), ["sketchybar-profile"])
        let task = state.visibleTasks[0]
        XCTAssertEqual(task.dependencies, ["sketchybar", "aerospace-profile", "fonts"])
        XCTAssertEqual(state.hierarchyPrefix(for: task), "")
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
        XCTAssertEqual(state.focusedTask?.id, state.visibleTasks.last?.id)
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
