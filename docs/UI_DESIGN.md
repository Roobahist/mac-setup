# Native interface rules

The control center uses `SetupDesign` for shared typography, spacing and surfaces. Treat these as product roles; avoid screen-specific replacements for the same role.

| Role | Rule |
| --- | --- |
| Page heading and description | `SetupPageHeader`: 27 pt semibold heading, 13 pt description, 8 pt gap |
| Page column | 980 pt maximum including 28 pt gutters; 20 pt between content groups |
| Body and controls | 13 pt system font |
| Section heading | 15 pt semibold |
| Sheet heading | 20 pt semibold |
| Supporting caption | 11 pt |
| Card | 18 pt padding, 12 pt corner radius, native material |
| Workspace field | 32 pt height, shared border and fill |

The sidebar has one set of native buttons. Its width is 248 pt expanded and 70 pt collapsed. The 54 pt icon column and 8 pt outer inset keep every icon centered at x=35 in either mode. Rows stay 36 pt high. Hide only the title area; size the row, focus/hit area, hover and selection backgrounds to the actual sidebar width. Do not clip a full-width navigation list to simulate a compact rail. Selection uses a shape and semibold title, with accessible selected state. Buttons keep their labels and tooltips when collapsed, and support keyboard navigation.

Workspace column titles are centered over their input group. Headers and rows share `WorkspaceColumns`, including the flexible name column, gutters and vertical inset. Display is a peer column alongside icon, name, apps and key. Use `SetupDropdown` for menu selections: its native `NSPopUpButton` fills the entire shared control surface, while a non-interactive SwiftUI overlay draws the label and arrow. Never add padding around an intrinsically sized native menu and assume that padding is clickable. The same component serves workspace fields, shortcut editors and macOS selection controls. App assignment opens a sheet and uses a right disclosure arrow. Apps, key and display share a 9 pt semibold chevron in a 10 pt frame, centered vertically and inset 8 pt from the right edge. Apps points right; key and display point down. Hide the native popup drawing so it cannot override this placement; retain native keyboard navigation, selection, accessibility and focus indication. The drag insertion boundary follows the actual row height.

Users edit one workspace name. Internal routing keys remain an implementation detail of the saved configuration and generated AeroSpace/SketchyBar files. A rename updates those keys and routing together; neither the native editor nor terminal editor offers an independent second identity. Existing portable source identifiers remain compatible until renamed. Diagnostic repair remains available for imported malformed settings.

A page must keep its draft when validation or apply fails. Review precedes changes. Generated-profile migration explains local copies and backups in the plan; applying must never write through a directory link into the original checkout. Successful automatic rollback must not instruct the user to undo the same operation again.

Before delivery, inspect expanded and collapsed navigation, the narrow supported window, workspace rows and menus, rename/reorder/app assignment, neighboring settings pages, review and error/retry states. Confirm keyboard labels and focus, the standard Edit menu, and reduced-motion behavior. Screenshot comparisons complement behavior tests; source-text assertions about a particular layout are not visual verification.

Color controls show an opaque RGB swatch, editable six-digit RGB value and a separate opacity slider. Editing either channel preserves the other. Background blur has single-step precision from 0 to 100; it is visible through translucent backgrounds. Keep stored source ARGB values intact. Plain buttons must put their padded frame and content shape inside the button label, including icon-only actions and glyph grids.

The entire SketchyBar follows measured native menu-bar height in logical points at the current display scaling, including notch safe areas. Read per-display menu-window bounds with the native main-menu height as fallback; generic status-item thickness is insufficient. Background workers use the bundled display helper rather than blocking the GUI or terminal main thread. Re-enforce bar geometry on reload/display/wake even when AeroSpace gaps already match. Preserve the reference height if the helper fails to return valid measurements.

Workspace previews share `WorkspaceBarPreview` and the same live draft in both sections. Keep native point heights, readable glyph sizes and shared item widths within the compact preview. Show only the strip behind the bar; condense the wallpaper horizontally to fit instead of shrinking workspace glyphs or adding desktop scenery below. Sample state is keyed by workspace identity and stays stable across reorders. The Workspaces preview has no focus and all items occupied; Workspace Bar has exactly one focus and a mixed sample. Draw the wallpaper’s top region using the current display aspect ratio, placement options and fill color, then composite blur and ARGB colors over it. Never use an ambient material or capsule as a substitute for the real rectangular bar. Clearly identify approximation for dynamic wallpapers and blur.

Shared macOS preferences are cards, with search, categories, current-value descriptions, per-card inclusion and typed controls. One review applies only edited preference keys and writes one JSON profile. Refresh unedited cards when returning from another app without discarding drafts. Keep the original comparison token for a pending edit so a concurrent external change requires reload. Never export full preference domains, Dock bookmarks or private paths into the portable profile. Source defaults are an explicit action, never an automatic overwrite of current values. Native menu-bar clock controls are absent from navigation, guided steps and search.
