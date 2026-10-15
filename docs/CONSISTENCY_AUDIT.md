# Settings and workspace consistency audit

This follow-up uses the supplied screenshots, fresh native app captures, the reported apply logs and an isolated reproduction of linked configuration directories. It addresses the shared causes across navigation, editing, style and recovery.

| Priority | Finding | Resolution |
| --- | --- | --- |
| P1 | Generated profiles rejected any directory link outside the hardcoded source path, blocking workspace edits. | Snapshot an existing linked directory into local config, back up the link itself, preserve extra content, and leave the original checkout untouched. Restore reconnects the link. |
| P1 | Relative links in a copied directory could point somewhere else after detachment. | Preserve their original destinations before moving the snapshot. A regression exercises an extra linked file. |
| P1 | A legacy home-level AeroSpace config created another manual block. | Show its migration in the plan; journal removal of the ambiguous legacy path so it is restored with the profile on failure or undo. |
| P1 | Coordinated recovery restored files but repeated an inner error telling the user to restore again. | Preserve the underlying cause separately from its recovery instructions. A successful rollback reports that recovery already happened. |
| P1 | Leaving a prerequisite pending caused the next dependent task to fail. | Leave dependent tasks pending as well, with an explanation, instead of attempting them. |
| P2 | A full-width native list was cropped to create the narrow sidebar. Native selection geometry was therefore cut off and icons were off-center. | One set of labeled, keyboard-accessible buttons with a fixed icon rail; the actual row and highlight width follows the sidebar width. |
| P2 | Page descriptions inherited different fonts and cards had independently chosen padding and radii. | A shared page header, typography roles and card/control surfaces across overview, apps, workspaces, bar, shortcuts, settings and updates. |
| P2 | Workspace headers and cards had separate dimensions; display was an extra row under name. | One column specification for headers and rows. Display becomes a peer field, with the same field height and surface as the other controls. Column titles are centered; app, key and display chevrons share geometry and styling, with direction indicating sheet versus menu. |
| P2 | The normal editor showed both name and routing ID, and terminal editing allowed them to diverge independently. | One user-facing name, coupled rename behavior in both editors, and internal keys retained only in saved/runtime configuration. |
| P2 | The application had an empty menu bar, so normal Quit and text-editing shortcuts were absent. | Standard application, File, Edit and Window menus; Quit observes the running-installer guard. |
| P2 | A source-text test explicitly mandated the broken clipped-sidebar implementation. | Remove the implementation-mirroring assertion; document screenshot and interaction checks, while retaining behavior and compatibility tests. |

The regression tests cover preservation of linked source content and extra files, undo reconnecting a link, legacy config recovery, failure after detachment followed by a successful retry, saved layout restoration and the existing profile/shortcut behavior. Parent configuration-directory links remain guarded against accidental write-through. No real desktop configuration is applied during native UI checks.

The design rules are documented in [UI_DESIGN.md](UI_DESIGN.md). Local screenshots and the runnable preview are delivery artifacts rather than public repository assets. Visual and accessibility checks apply to the surfaces exercised; they do not establish universal macOS-version or assistive-technology compliance.

Validation: 180 tests passed in both debug and optimized release builds. The real-terminal navigation/rename/review/cancel smoke test, bundled-source parity, public-profile validation, installer-isolation and SwiftUI compatibility checks passed. The arm64 preview built successfully. Native checks exercised expanded/collapsed navigation, rename and move/undo, app assignment, key/display menus, neighboring workspace-bar and keyboard pages, and standard text editing. Changes were not applied to the author’s desktop during those checks.
