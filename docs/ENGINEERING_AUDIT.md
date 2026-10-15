# mac-setup engineering audit

Audit date: 2026-10-14. Target: SwiftUI control center, CLI, profile generation, system application, recovery, and package tests.

## Priority and evidence

| Priority | Finding and root cause | Location | Status |
| --- | --- | --- | --- |
| P0 | A successful profile copy and `sketchybar --reload` exit were presented as applied changes even when the active bar retained its old workspace order. | `Engine.apply(.profile)`, `SetupModel.advance` | **Addressed in code:** poll the live bar after reload; report mismatches. Requires physical Mac verification. |
| P0 | Configuration JSON can be saved before all requested installation and runtime operations succeed. A failure can therefore leave persisted configuration ahead of actual system state; Journal restores installed files independently from the JSON draft. | `SetupModel.start`, `WorkspaceConfiguration.save`, `Journal.restore` | **Open architecture issue:** introduce one transaction boundary spanning workspace/shortcut drafts, profile writes, service reloads, and rollback. Do not treat this as solved by the runtime probe. |
| P1 | An app-only full setup saved otherwise unrelated workspace and shortcut drafts. | `SetupModel.start` | **Fixed in code:** write only configuration associated with selected profile tasks. |
| P1 | Workspace order was compared against generated files, not the active menu bar. AeroSpace's own `list-workspaces --all` can sort by workspace name rather than persistent-workspaces order. | `WorkspaceConfiguration.sketchybarShell`, `Engine` | **Addressed in code:** compare ordered `space.*` item names from SketchyBar's live `--query bar` JSON. Check AeroSpace membership and active config path separately. |
| P1 | SketchyBar color/spacing/blur changes depended on literal bundled default values. Template updates could produce unchanged files and false success. | `WorkspaceBarStyle.colorsShell`, `WorkspaceConfiguration.sketchybarShell` | **Fixed in code:** replace assignment values irrespective of original defaults; reject absent or duplicate assignments. |
| P1 | Related SketchyBar controls were divided between Workspaces and Appearance while Appearance also controls native macOS colors. | `NativeSetup.swift`, `ControlCenter.swift` | **Fixed in code:** workspace/bar styling and wallpaper accent watcher live together in Workspaces. Native appearance remains separate. |
| P1 | Reordering depended on precision dragging, with no equivalent context-menu or accessibility move action. | `NativeSetup.workspaceCard` | **Addressed in code:** Move up/down actions, while preserving existing drag/drop and shortcuts. |
| P1 | One native `ControlCenter` uses `SetupView` for shortcut/workspace editing, but feature choosing and page layout are still implemented in both `ControlCenter` and standalone `SetupView`. | `ControlCenter.swift`, `NativeSetup.swift` | **Open:** extract reusable feature picker and a view-independent coordinator instead of copying another set of controls. |
| P1 | Saved, draft and truly active configuration are not consistently modeled as separate states. `appliedLayout` was refreshed from persisted JSON without querying runtime. | `SetupModel` | **Partially addressed:** a failed runtime probe keeps the last checked layout; a full state-machine refactor remains open. |
| P2 | No automated pixel/screenshot baselines or full UI interaction tests; existing Python sidebar test checks source structure rather than rendering. | `scripts/test-native-sidebar.py`, CI | **Open:** add macOS UI harness and versioned snapshots on each supported SDK/window size. |
| P2 | Settings that macOS may cache or change across OS releases need physical user-session confirmation, not solely `defaults` reads. | `TweakService`, preference tasks, system restart paths | **Open for manual verification** on clean test accounts for each target macOS version. |

## Verification contract

The app should distinguish four things: editor draft, saved configuration, installed profile files, and running desktop state. The new runtime probe covers the last distinction for workspace presence and SketchyBar order. It does **not** prove that actual keyboard shortcuts navigate and move windows, that wallpaper notifications propagate, or that every control is visible and clickable.

SketchyBar order is taken from the `items` array in `sketchybar --query bar`, filtering `space.` items. A matching file on disk is not proof of a matching bar. AeroSpace `list-workspaces --all` is used to check *membership*, not order. When the bar or AeroSpace cannot be queried, validation is explicitly unresolved.

## Tests added in this branch

- Strict SketchyBar profile template substitutions and refusal of stale/missing/duplicate assignments.
- Live SketchyBar JSON order checks, including missing and malformed results.
- AeroSpace workspace membership independent of CLI enumeration ordering.
- Engine integration with an injected fake process runner and controlled output for active config, order mismatch, and retry/failure after reload.
- Native workspace move controls have bounded destination indices through the existing `insertWorkspace` logic.

Existing macOS CI continues to run all XCTest suites, CLI smoke tests, shell lint, public profile validation, terminal navigation tests, and package build. CI success is not a UI screenshot comparison or a physical live session.

## Manual macOS validation checklist

Use a disposable macOS user account with AeroSpace and SketchyBar installed. Back up the configuration before proceeding. Validate on a current supported macOS release and at least one older supported release, using narrow and wide windows.

1. Launch the control center, navigate every sidebar section with the sidebar expanded and collapsed, and confirm icons, selection highlights, search, focus, and labels remain aligned. Capture comparable screenshots at minimum and expanded window sizes.
2. In Workspaces, reorder by drag/drop and by context-menu Move up/down; rename a card, edit its glyph, edit app assignments, and edit the bar palette, blur, and spacing. Review without applying, close/reopen, confirm draft behavior, then apply.
3. Inspect `aerospace config --config-path` and `aerospace list-workspaces --all`. Inspect the `items` array from `sketchybar --query bar` and confirm that its `space.*` entries follow the saved order. Confirm visible order on every active display.
4. Intentionally stop SketchyBar, apply the selected profile, restart SketchyBar, then use “Check running apps again.” Confirm no false success when live state is unavailable or stale.
5. Trigger a bad SketchyBar configuration and check the recovery record, Retry, Undo, and later reapplication. Confirm user settings and unrelated dotfiles remain intact.
6. Change shortcut mappings, apply them, switch and move real windows using AeroSpace, and confirm Karabiner/Raycast bindings work with their required permissions. Repeat after relaunch and reboot.
7. Toggle the wallpaper watcher **only after explicit user action**, change the wallpaper, apply manual color, and verify neither setting silently activates the other. Check startup state after reboot.
8. Test Dock, Finder, system clock, macOS accent, installed apps, and startup tasks on the real machine. For each, compare before/after settings, UI behavior, return codes, persistence, and Undo/Reset/Refresh.
9. Test failures (missing dependency, bad config syntax, process unavailable, denied permissions, conflicting saved files) and check each error is shown once with a usable recovery path.

## Remaining release gates

This branch is **not** an audited release of the entire app. The cross-system transaction/rollback model, all-setting functional smoke tests, independent SwiftUI snapshot tests, and physical macOS verification must be completed before calling the overhaul validated or merging its PR.
