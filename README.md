# mac-setup

A keyboard-driven macOS setup CLI for reproducing a complete, opinionated setup while
letting each person choose which parts to install.

Browse a live checklist, select or deselect components, preview their prerequisites,
and apply changes with confirmation and recovery records. The public configurations
come from [dot-files](https://github.com/Roobahist/dot-files); offline snapshots are
bundled with every release. No GitHub account is required to run downloaded builds.

## Install and run

Requires macOS 13+ and Swift 5.9+ (Xcode or compatible Command Line Tools).
Some installed apps have higher requirements; Vorssaint requires Apple silicon
and macOS 14+. The CLI never runs as root.

```sh
git clone https://github.com/Roobahist/mac-setup.git
cd mac-setup
./install.sh
# Open a new terminal after installation:
mac-setup
mac-setup profiles
mac-setup plan --preset complete
```

The one-time installer builds a release executable and installs it with its resource
bundle into `~/.local`. It backs up `.zshrc` before adding the command directory to
PATH; linked shell configuration files are left for you to update manually. Daily
launches use the installed executable and do not invoke Swift or rebuild anything.
You can also run `./mac-setup` directly from this checkout; it builds once if needed.
After changing source code, run `./install.sh` again to rebuild and update.

The build helper uses SwiftPM's native engine for compatibility with Command Line
Tools. This avoids the missing Xcode framework search-path warnings from Swift
6.4's default build engine. Those warnings did not indicate a failed setup.

## Interactive checklist

Run `mac-setup` or `mac-setup setup` in a terminal to open the full-screen picker:

- **Up/Down** or **J/K**: move between tasks.
- **Space**: select or deselect a task. Required prerequisites are included automatically.
- **Tab** and **Shift+Tab**: cycle through categories.
- **/**: search by task name, description, category, or ID. **Esc** clears the filter.
- **A**: select or clear tasks currently shown by the category and search filters.
- **1**, **2**, **3**, **4**: Minimal, Productivity, Developer, or Complete preset.
- **W**: configure workspace order, names, Nerd Font glyphs and app assignments.
- **?**: keyboard shortcut help.
- **Enter**: continue to the workspace step when AeroSpace configuration is selected,
  then review selections and Enter again to start setup. **B** returns to feature selection.
  If AeroSpace configuration is not selected, Enter goes directly to review.
- **Q** or **Ctrl+C**: cancel without making changes.

Children are grouped beneath their primary parent using continuous `│`, `├──`
and `└──` tree connectors. Checkboxes stay in a fixed left column, and a spacer
separates completed child groups while continuing any open tree lines. Root tasks stand out, and guided/update labels occupy a
quiet column on the right. Shared prerequisites and their readiness appear only
in the focused task's detail panel, keeping the checklist uncluttered. Filters
show matching tasks once, without orphaned branches to hidden parents.

The picker first inspects installed packages and completed setup tasks in the
background. Navigation stays responsive while selection changes wait for that scan.
Unchecking an installed parent leaves its children selected. Unchecking a missing
parent also unchecks children that require it; an installed intermediate parent
still satisfies its own children. Selecting a child adds only missing prerequisites.
The same rules apply to app, profile, service and permission dependencies.

Checked installed packages are kept by default. Press **U** on Homebrew or an
installed package task to mark it **UPDATE**; press U again to keep it. Updates are
previewed and confirmed before execution. Homebrew uses `brew update`; packages use
a targeted `brew upgrade`, which can also update required dependencies. Apps installed
outside Homebrew are not taken over. Package updates cannot be undone by restore.
Deselecting a task does not uninstall anything.

The picker never performs installations by itself. Applying the selection uses the
existing task previews, confirmation prompts, prerequisite checks, and local recovery
journal. Guided permission steps are not silently marked complete.

If you are scripting installation, use task IDs or a preset instead of the picker.
`--yes` approves automated tasks only; guided steps remain pending.

## Customize workspaces

Workspace configuration is **Step 2** of the interactive setup whenever the
AeroSpace configuration task is selected. Press **Enter** on the feature checklist
to open it automatically; press **Enter** or **K** to **Keep existing layout**
and continue to review without saving anything. Press **S** to save your
changes and continue, or **Esc** to return to the feature checklist.
When no AeroSpace profile is selected, the workspace step is skipped.

You can still press **W** in the feature checklist to open it early, or run
`mac-setup workspaces` at any time to use the editor independently.
All three steps use the same header navigation, colors, layout spacing and
bottom keyboard-help area. The editor has a column-aligned workspace table and a selected-workspace
inspector on wider terminals. In narrow terminals, the inspector is placed
below the table instead. The workspace list distinguishes shortcut, friendly
label, glyph name, AeroSpace workspace ID and assigned application count. Color
highlights the focused row and unsaved changes; `NO_COLOR` and `TERM=dumb`
are supported, and each row retains an ASCII focus marker without color.
Glyph previews are always shown alongside their searchable names, even if the
terminal cannot display Hack Nerd Font glyphs. In that case, the icons may appear
as rectangles, but the names remain readable. Set your terminal font to Hack Nerd
Font for correct rendering, independently of SketchyBar's font.

The editor supports these keyboard controls:

- **Up/Down** selects a workspace; **[** and **]** move it left or right.
- **A** adds a workspace, **D** removes one (with confirmation).
- **R** renames its AeroSpace workspace ID; **N** edits its descriptive label.
  IDs use letters, digits, underscores or hyphens. Labels can contain spaces.
- **G** opens the searchable Nerd Font glyph browser. Start typing a glyph
  name or keyword (such as `terminal`, `music`, `code` or `notes`) to filter
  results; use arrows and Enter to select. The bar uses Hack Nerd Font.
- **P** opens searchable installed-app routing. Type to filter by app name or
  bundle ID; use arrows and Space/Enter to assign or unassign the focused
  application. Reassigning an app moves its rule from its previous workspace.
  Press **+** with an empty search field to enter a bundle ID manually.
- **S** validates and saves the layout. In guided setup, **K** or **Enter**
  keeps the existing layout if no edits are pending and continues to review.
  **Q**, **Esc** from the top-level editor, or **Ctrl+C** cancels editing.
  Within search results, Esc clears the filter first, then returns to the
  workspace list. Cancelling with edits asks for confirmation.

At most 13 workspaces are supported, using the familiar Option+backtick,
Option+1 through Option+0, Option+minus and Option+equal shortcuts in their
configured order. Option+Shift+key moves a window instead of switching focus.
The Complete and Productivity presets select an **optional Tomito** installation
step from the Mac App Store. The default layout includes its Pomodoro timer
workspace and auto-routing for `com.tomito.tomito`. Uncheck Tomito in the setup
checklist to hide that workspace when pressing W and to exclude its workspace
and application routing from AeroSpace/SketchyBar configurations generated by
that setup run. This does not uninstall Tomito if it is already installed or
silently discard your saved workspace definitions. Saving edits while Tomito
is unchecked retains the hidden Pomodoro definition in the private settings;
the remaining visible workspaces can only use the available shortcut slots. The standalone editor and
subsequent profile-only updates use the saved layout; optional app choices from
a prior checklist are not automatically persisted between installer runs.
Tomito is distributed through the Mac App Store, so installation requires the
user to complete App Store prompts. The CLI verifies the application exists.

The editor discovers applications in `/Applications`, `/System/Applications`
and `~/Applications`, including apps in subdirectories. Bundle IDs can be
entered manually for applications elsewhere. **App assignments route windows
when the application opens; they do not install or automatically launch apps.**
An unassigned application opens wherever AeroSpace would normally place it.

Your choices are stored locally in
`~/Library/Application Support/mac-setup/workspaces.json`. Saving from W
persists these choices even if you subsequently cancel the installation
checklist, but it does not modify AeroSpace or SketchyBar until their profile
tasks run. To apply later changes, use:

```sh
mac-setup workspaces
mac-setup setup aerospace-profile sketchybar-profile
```

AeroSpace and SketchyBar profiles are generated as **local, backed-up copies**
from the bundled templates rather than symlinks into public dotfiles. This
keeps private customization outside the public repository and prevents
`dotfiles update` from overwriting it. The existing recovery journal restores
the previous generated files; it does not erase workspace choices in
`workspaces.json`. Other application profiles can still link public dotfiles.

## Download a build

Download the archive for your processor from [Releases](https://github.com/Roobahist/mac-setup/releases):
`arm64` for Apple silicon or `x86_64` for Intel. Extract it and keep `mac-setup`
beside `MacSetup_MacSetupCore.bundle`. Run the executable directly or run
`bash install.sh` from the extracted directory to install into `~/.local`.
Users do not need Xcode to run a downloaded build.

Before the first tagged release, preview archives are available in successful
[GitHub Actions runs](https://github.com/Roobahist/mac-setup/actions).

These builds use local ad-hoc signatures, not Apple Developer ID signing or
notarization. macOS may require an app-specific approval in System Settings >
Privacy & Security after a first launch attempt. Managed Macs may restrict it.
The installer does not disable Gatekeeper or remove quarantine attributes.

## Commands

```sh
mac-setup profiles
mac-setup workspaces
mac-setup list
mac-setup status
mac-setup plan --preset productivity
mac-setup setup --preset developer
mac-setup setup aerospace-profile sketchybar-start
mac-setup setup --all --dry-run
mac-setup dotfiles status
mac-setup dotfiles update
mac-setup backups
mac-setup restore --dry-run
mac-setup restore
mac-setup update
```

The default command opens the interactive picker. `status` distinguishes
automatically verified state, guided steps, and steps the user confirmed.
Stored preference verification does not guarantee the visible behavior of an
undocumented setting on every macOS release.

### Resume after a Mission Control preference failure

If AeroSpace and its profile were installed but the `mission-control` task
failed with a `defaults` usage message, update `mac-setup` to a build containing
the Boolean preference fix, then rerun only the blocked steps:

```sh
mac-setup setup mission-control aerospace-access
```

You don't need to reinstall AeroSpace or its configuration. The Mission Control
task saves the previous values in a new recovery record before changing them,
and requires logging out and back in for the separate-Spaces setting to take
effect. If you are still in the original setup run, let other tasks finish and
return to the blocked steps afterward. A failed task's recovery record is not
automatically restored, so review `mac-setup backups` before restoring any
partially applied settings.

`update` reapplies previously installed profiles bundled in the current executable.
Install a newer CLI build first to obtain newer profiles. It does not download an updated public profile, upgrade every Homebrew package,
or replace the executable itself.

## Included tasks

- Automatic Homebrew installation and zsh setup; AeroSpace, SketchyBar, Vorssaint, Raycast, Karabiner, Alacritty,
  Atuin, fonts, Python and ImageMagick installation through Homebrew.
- Optional guided Tomito installation through the Mac App Store (Productivity and Complete presets).
- Portable AeroSpace workspaces, app rules and bindings; SketchyBar workspace bar,
  clock, fonts and accent; Karabiner shortcuts; Alacritty and Atuin preferences.
- A snapshot of 181 portable Vorssaint preferences, including quit-on-close.
  Quit Vorssaint before applying or restoring it. Launch it afterwards.
- Dock auto-hide with a five-second reveal delay, removal of ordinary pinned Dock
  items, hidden desktop files, dark appearance, Finder list view and tab preferences.
- A managed Atuin zsh initialization block and macOS global Git ignore rules that
  preserve existing rules.
- Automatic Finder list icon sizing, menu-bar auto-hide, two-finger secondary click,
  Mission Control workspace settings, and desktop widget hiding (macOS 14+), with preference verification and backups.
- Guided Finder sidebar customization, display scaling, icon colors/Liquid Glass,
  app permissions, onboarding and app-specific login items. These require choices
  or a supported app/Settings approval workflow.
- Local wallpaper accent extraction. `setup wallpaper-colors` reads the current
  wallpaper; the `--image` option accepts a local image path if the wallpaper is
  unavailable. Image bytes are never uploaded.

Automatic wallpaper updates use the existing WallpaperAccentWatcher.app. The
Complete and Productivity presets include its permission/test task. Dock setup
clears ordinary pinned items and enables auto-hide; Finder, Trash and system-managed
launcher controls can remain. mac-setup does not patch protected system files.

## Public dotfiles source

The canonical portable configurations live in [dot-files](https://github.com/Roobahist/dot-files).
Vorssaint's separate sanitized preference snapshot remains managed by `mac-setup`.

There are two ways to install an application profile:

1. **Linked mode:** select **Link public dotfiles** in the checklist. This clones
   `dot-files` into `~/dot-files`. When you later select an application's profile
   task, only that application's configuration directory is linked into `~/.config`.
   Subsequent source changes are visible through the same symlink, except for
   AeroSpace and SketchyBar, which are generated locally to support personal
   workspace layouts.
2. **Bundled mode:** leave the linked task unselected and do not have an existing
   `~/dot-files` checkout. The chosen profile is copied from the current `mac-setup`
   release, so setup works without network access.

Existing ordinary configuration directories are recorded in the local recovery
journal before being replaced. Existing links to **other** repositories are refused,
never overwritten or detached. A user-created symlink for the parent
`~/.config` directory is refused. Linking one app does not enable or install other
applications. Running a profile task again against its managed link does not
replace that link.

```sh
mac-setup setup dotfiles-linked
mac-setup setup aerospace-profile karabiner-profile
mac-setup dotfiles status
mac-setup dotfiles update
```

The `dotfiles update` command requires a clean checkout with the expected
Git remote and runs `git pull --ff-only`. If you have uncommitted changes,
commit or stash them before updating. It does not force-reset your checkout.

If you use `mac-setup update`, it reapplies installed bundled profiles only;
it is not an application updater. To obtain new linked configuration, use
`mac-setup dotfiles update`. To obtain newer bundled snapshots, install a
newer `mac-setup` release.

For maintainers, refresh checked-in snapshots with:

```sh
python3 scripts/sync-dotfiles.py
python3 scripts/check-profile.py
swift test
```

The repository sync workflow checks hourly and can create a reviewable pull request.
Optional immediate notifications require a fine-grained token stored in
`dot-files` as `MAC_SETUP_DISPATCH_TOKEN`; scheduled checks need no token.

## Your data and backups

The public profile has no personal snippets, shelf contents, Atuin database,
authentication session, device bookmarks or private Git history. Karabiner uses
$HOME-relative paths; one generic key-sequence example is disabled by default. A full
personal Vorssaint transfer can use its native export/import, but exports must be
reviewed before sharing. Stored settings alone cannot capture its unpersisted defaults.

Bundled profile installation merges files into their configuration folders while
preserving unrelated files. Linked profiles preserve their symlinks. The installer
refuses unrelated symlinks instead of detaching them. A symlinked parent config
directory is rejected.
An existing `~/.aerospace.toml` must be moved aside manually to avoid ambiguous config.

Recovery records and backups live in `~/Library/Application Support/mac-setup`.
They can contain private existing configuration: **do not commit or share them**.
Each changed target is recorded before mutation. Interrupted or failed tasks keep
their recovery record. Concurrent setup/restore processes are refused.

`restore` defaults to the newest unrestored record. Restore multiple records newest
first, using IDs printed by `backups` if needed. It refuses targets edited since
setup before restoring any target in that record. `--force` explicitly permits
discarding later edits. A partially completed restore can be retried.

Restore covers managed files, selected preference keys, global Git ignore settings,
and a SketchyBar service newly started by this tool. It does not uninstall apps,
revoke permissions, undo manual settings, or remove every empty parent directory.
Relaunch affected apps or log out after restoring preferences.

XDG_CONFIG_HOME and ZDOTDIR are honored when set. Reopen Terminal after changing
shell initialization. Existing history is not imported or synced automatically.

## Build and release

```sh
swift test
python3 scripts/check-profile.py
bash scripts/package.sh
```

The default package targets the build machine's architecture. Packaging includes
the executable, its resource bundle, installation instructions and a SHA-256 checksum.
GitHub Actions tests public profiles and produces preview artifacts on main pushes.
Pushing a `v`-prefixed version tag runs the release workflow, builds Apple silicon
and Intel archives, and publishes them to GitHub Releases without Apple membership.

Most tests use temporary homes and fake system commands. One regression test
checks `defaults` against a disposable, randomly named preference domain on
the macOS CI runner, then cleans it up. CI does not apply actual setup settings.
Real permission flows, display settings and app behavior still need testing
on a spare Mac or disposable user account before a stable release.

MIT license. Third-party apps and fonts retain their own licenses; see NOTICE.md.

## Wallpaper watcher

`mac-setup setup wallpaper-watcher` uses your existing `WallpaperAccentWatcher.app`
in `~/Applications` or `/Applications`, with LaunchAgent label
`com.roobahist.wallpaper-watcher`. An already running watcher and its launch
configuration are preserved. mac-setup does not install a second watcher, copy a
CLI runtime, or change the app's polling interval.

If the app is installed but not registered, setup reuses its existing LaunchAgent
plist or creates one with the app's existing environment options. A missing accent
extractor is installed from the bundled profile without replacing an existing
script. Existing plist changes are backed up. The app must be installed first;
mac-setup does not distribute your personal app binary. Your current app uses
Apple silicon Homebrew paths for Python, AeroSpace and SketchyBar; the bundled
Python extraction script discovers ImageMagick through PATH.

The app uses the active wallpaper on the main display, including non-Unsplash
images. On multiple monitors it supplies one shared accent. Its existing behavior
checks every two seconds and waits for two matching observations before applying
a changed image. `watch` runs the installed app in the foreground, and
`watch --once` uses its one-shot environment option. Stop the startup watcher first
to avoid running two copies. `--image` can choose an accessible local image.

Run `watcher-status` to inspect registration and the app's existing logs. Change
wallpapers to verify the visible result. If macOS blocks access, approve
WallpaperAccentWatcher.app in Privacy & Security > Full Disk Access or choose an
accessible local image. Permissions are never granted automatically.

`watcher-stop` stops the app until login or reload. `watcher-disable` disables its
LaunchAgent across logins; `watcher-enable` resumes it. These commands control the
existing app. Restore undoes only the changes recorded by mac-setup; it does not
remove your pre-existing app or a service that mac-setup did not install.

The existing app persists `HIGHLIGHT_COLOR` in SketchyBar's `plugins/colors.sh` and
triggers the focused-workspace update directly. Its behavior is preserved. Use a
local SketchyBar configuration rather than a symlink into tracked dotfiles if you
want generated colors to remain outside your repository. Manual
`setup wallpaper-colors` remains backed up like any other setup task.

Homebrew setup runs the official installer in your terminal when missing, including
any password or Command Line Tools prompts. The CLI then adds `brew shellenv` to
zsh's `.zprofile` after backup. Restore can undo the shell edit but does not uninstall
Homebrew. Privacy approvals always remain guided. Stored preference verification
does not replace checking the visible result; some changes need logout and login.

The Finder reference preset uses list view, no grouping, Date Modified sorting,
32-point icons, 13-point text, Name/Date Modified/Size/Kind columns, relative dates
and icon previews, with Calculate all sizes off. Folder-specific Always open/Browse
checkboxes remain a guided check because existing folders store their own view
metadata. The appearance guide targets Clear Liquid Glass with Reduce Transparency
off, matching the transparent Control Center reference.
