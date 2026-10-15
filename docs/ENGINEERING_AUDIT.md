# Reference fidelity and application audit

Audit started 2026-10-14; verification completed 2026-10-15 (America/Edmonton).

## Outcome

Mac Setup's default behavior now comes from the portable files it ships. The source revision and SHA-256 for each allowlisted file are recorded in `ReferenceProfile.json`. Workspace order, destination keys, modifier sets, app routing, display assignments, glyphs, fonts and bar palette are compiled from those files by `sync-dotfiles.py`. The build and release workflows verify the snapshots and the generated defaults together.

The app preserves separate Karabiner application rules. Customization changes the selected rule, instead of flattening the source into a replacement rule containing several applications. Existing user choices are retained on upgrade; new installations use the reference Alacritty action rather than a silent Terminal substitution.

## Scope and evidence

Reviewed the app's core, native and terminal interfaces, profile resources, task catalog and presets, installation/update scripts, recovery journal, startup services, permission guides, synchronization and packaging. Compared the public source, bundled snapshots and the author's active local configuration. Karabiner's CLI confirmed the active local profile. No setup changes were applied to the author's desktop during this audit.

The initial 154-test suite had 12 failures on this development machine. Several tests accidentally consulted globally installed applications, and one real preference integration test lacked the required sandbox access. App discovery is now injectable; the preference round-trip uses a disposable file domain.

## Findings and repairs

| Priority | Finding | Repair and regression evidence |
| --- | --- | --- |
| P1 | The renderer deleted separate Alacritty, VS Code and Finder rules and generated one `Mac Setup: Custom shortcuts` rule. | Retain source rule order, descriptions, manipulators and action data. Each custom launch action has its own rule. Semantic equality test for untouched Karabiner JSON; one-rule edit regression. |
| P1 | Fresh defaults changed the terminal action from Alacritty to Terminal; upgrade migration could also change a user's launcher. | Derive new app-launch defaults from source. Format migration retains existing terminal and Raycast assignments. |
| P1 | Optimized validators passed `CharacterSet.contains` as a bound method predicate, producing false failures for valid IDs on the tested toolchain. | Reproduced outside the app: `ai` and `chatgpt` fail the optimized bound predicate and pass an explicit closure. Replace bound predicates in ID, bundle and font validation; run optimized tests and validate the packaged reference. |
| P1 | `AI` was a display label attached to the old `chatgpt` runtime identity. There was no explicit identity migration. | Source and new defaults use `ai`. Known old `chatgpt` + `AI` entries get an explained draft migration. Custom names and existing `ai` identities are protected. |
| P1 | Renaming changed only an editor label; hidden runtime IDs survived. | Native and terminal rename update the runtime identity; show the ID. Regenerate shortcuts, routes, bar entries and display assignments from that identity. |
| P1 | Removing a workspace shifted inherited number-row shortcuts; terminal reorder used a different policy from native reorder. | Materialize keys before structural edits. Both reorder paths use the same insertion operation. Additions start unbound. |
| P1 | Routing rules were silently removed based on installed apps and optional installer choices. | Keep all saved routes, including Telegram, Spotify, Obsidian and Tomito. Missing applications can be installed later without another profile edit. |
| P1 | Native app assignment editing hid saved applications that were not installed and relied on a mutable array index. | Identify the selected workspace by ID; show saved missing apps, search bundle IDs, and allow explicit bundle ID assignment. |
| P1 | Default workspace data was independently hardcoded in Swift and could disagree with source snapshots. | Generate reference metadata from the TOML, Karabiner JSON and restricted shell icon/font declarations. Reject unsupported source changes rather than executing shell or guessing. |
| P1 | The bundled AeroSpace/SketchyBar/wallpaper files differed from the public source. Blind synchronization also removed app-only runtime fixes. | Reconcile source fixes first, then synchronize. Promote bounded wallpaper processing, portable ImageMagick lookup and workspace refresh fixes to dot-files. Hash-check all 20 shared files. |
| P1 | A changed bar palette counted as verified merely because the file contained `HIGHLIGHT_COLOR=`. | Compare the rendered palette; wallpaper accent changes remain in their independent cache. Regression changes an installed bar color and requires Ready, not Verified. |
| P1 | Full setup saved editor JSON before profile prerequisites and writes succeeded. Resume could save unrelated drafts and skip already-completed profiles after inputs changed. | Keep reviewed drafts in memory. Persist only the component whose profile task succeeded, in that task's journal transaction. Resolve selection once for review/apply/resume and invalidate affected completed profiles after edits. |
| P1 | Dedicated editor applies could leave JSON and earlier profile writes ahead of a failed later task. | Coordinated recovery restores changed profiles and saved JSON in reverse order; retain the draft. Retry restarts the editor operation. Report restore or reload failures explicitly. |
| P1 | Workspace behavior, global workspace modifiers, bar styling and wallpaper automation were divided inconsistently. | Workspaces owns destinations, routing, display selection and shared workspace modifiers. Workspace Bar owns SketchyBar visuals and explicit accent controls. Keyboard Shortcuts owns other provider actions. Each apply saves its selected scope. |
| P1 | Generator key names were valid for AeroSpace but invalid for many Karabiner keys. Invalid modifier/duplicate data could trap during generation. | Map physical key names explicitly and validate before constructing rules; reject duplicate IDs without dictionary or forced-modifier crashes. |
| P1 | Advanced disabled examples were shown enabled, and enabling them retained their JSON `enabled: false` flag. | Respect the source flag in the editor and reconcile it on generation. Keep disabled rules visible and structurally intact. |
| P1 | Applying the reference Karabiner profile overwrote other installed profiles. Script paths also ignored a custom configuration directory. | Preserve other profiles and global preferences; explicitly select Portable. Adapt script paths only in generated local files. Retain source actions when only keys change. |
| P1 | The wallpaper migration depended on the literal wording of a source comment. | Locate the cache loader by its assignment, so a harmless comment edit does not break migration. |
| P1 | Productivity included the optional Finder folder-metadata reset. | Exclude the reset from every preset; retain it as an explicit opt-in action. Regression covers every preset. |
| P2 | `dotfiles update --dry-run` could still pull; editor commands accepted an ineffective dry-run flag. | Preview the pull without writing; reject dry-run for interactive editor commands and direct users to `plan`. |
| P2 | Synchronization lacked a source/defaults parity gate and could race another local synchronization. | Verify recorded hashes and regenerated defaults in CI/releases; reject dirty source snapshots; serialize synchronization; stage metadata before replacing profiles. Test source glyph/color changes, dynamic shell rejection and allowlist path boundaries. |

## Local configuration compared with public source

- **Karabiner:** the active local profile has Chrome, Alacritty, Visual Studio Code and Finder as separate enabled rules. Their portable versions retain that structure and behavior after personal script paths are replaced with quoted runtime paths. Private disabled workflow rules are deliberately excluded; one generic disabled example remains. Public profile name `Portable` is an intentional distribution adaptation.
- **Telegram:** the inspected active local Karabiner JSON and its scripts contain no separate Telegram launch mapping. AeroSpace routes Telegram to Messages, and Option+0 switches to Messages. Both are retained and checked. The audit does not invent an unobserved Telegram launch chord.
- **AeroSpace:** local `chatgpt` naming is a legacy runtime ID. The requested public identity is now `ai` throughout persistent workspaces, destinations and routing. Tiling rules remain source-owned, including additional non-routing rules added later.
- **SketchyBar:** the source used SF Pro private-use symbols with incompatible font selection in some workspaces. The public font mapping and app defaults now use SF Pro for those symbols, with Hack Nerd Font for numbers. Recipient-specific display geometry remains an explicit app adaptation; it is not baked into the portable source.
- **Wallpaper:** local color changes remain local. Source files support a validated cache override; no wallpaper image or personal path is published. Large images are normalized once, extraction stages time out, and ImageMagick is located portably rather than hardcoded to an Apple silicon Homebrew path.
- **Other preferences:** Vorssaint's portable export remains independently bundled. Raycast's global Option+R launcher matches the inspected local preference. Private extension databases, account settings and usage history are outside the portable profile.

The reported invalid-ID error was reproduced in the optimized build. The debug validator accepted `chatgpt`, but the release validator's bound character-set predicate rejected valid IDs. A minimal optimized executable reproduced the difference between the bound predicate and an explicit closure. Packaged UI validation also exposed a font predicate failure missed by the original debug-only suite. The validators now use explicit closures; release-mode regression tests and packaged reference validation guard against recurrence. The stale AI identity was a separate defect and is migrated explicitly.

## Verification and limits

The regression suite covers source rule parity, customization, persistence, provider conflicts, workspace identity/order/keys, palette drift, live response parsing, installed-app isolation, preference round-trip, startup registration, watcher behavior, journal restore and injected apply failures. Python checks cover the portable public allowlist, wallpaper pipeline, source-derived defaults, sidebar structure and installer isolation. Packaging checks the reference resource from inside the actual app bundle.

Local verification results:

- Apple Swift 6.4 / Xcode 27 on Apple silicon: **175 debug tests and 175 optimized release tests pass**.
- Native packaged UI: moved AI down and back without an invalid-ID error; renamed AI to Research and verified `research`; restored the original draft; workspace review lists AeroSpace plus SketchyBar; Workspace Bar review lists only SketchyBar. No Apply action was invoked.
- Public dot-files privacy/allowlist and wallpaper checks pass, including GitHub CI on the paired source pull request.
- App source parity/default generation, wallpaper, sidebar, installer isolation and shell checks pass.
- Interactive terminal navigation is exercised through a pseudo-terminal, with setup cancelled before applying changes.
- Packaged app validates its bundled reference and wallpaper helper from inside the `.app`.

A saved file, a successful reload request and verified running behavior remain distinct. Runtime queries check AeroSpace membership/config path and SketchyBar item order. Missing applications or stale runtime responses remain visible as verification issues. Automated checks do not prove physical keyboard permission behavior, monitor hot-plug behavior, every macOS preference's visible effect, or every supported macOS version.

Full setup is intentionally incremental: successfully installed applications and completed tasks remain when a later task fails. Each successful profile's saved inputs are journaled with its files; an unfinished profile cannot publish its draft as saved configuration. Dedicated editor configuration batches roll back on failure. Restore still protects later external edits and reports conflicts rather than force-overwriting them.

## Review and release

Review the paired dot-files change before merging this app change, so source synchronization cannot propose reverting the updated reference. The app change pins the reviewed source commit. No production release or installation is performed by this audit. Before shipping broadly, exercise physical switch/move shortcuts, app launch actions, permissions, multiple displays and login behavior on a disposable account and supported macOS versions.
