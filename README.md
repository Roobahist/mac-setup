# mac-setup

A keyboard-driven macOS setup CLI for reproducing a complete, opinionated setup while
letting each person choose which parts to install.

Browse a live checklist, select or deselect components, preview their prerequisites,
and apply changes with confirmation and recovery records. The public configurations
come from [dot-files](https://github.com/Roobahist/dot-files); offline snapshots are
bundled with every release. No GitHub account is required to run downloaded builds.

## Run from source

Requires macOS 13+ and Swift 5.9+ (Xcode or compatible Command Line Tools).
Some installed apps have higher requirements; Vorssaint requires Apple silicon
and macOS 14+. The CLI never runs as root.

```sh
git clone https://github.com/Roobahist/mac-setup.git
cd mac-setup
swift run mac-setup
swift run mac-setup profiles
swift run mac-setup plan --preset complete
```

## Interactive checklist

Run `mac-setup` or `mac-setup setup` in a terminal to open the full-screen picker:

- **Up/Down** or **J/K**: move between tasks.
- **Space**: select or deselect a task. Required prerequisites are included automatically.
- **Tab** and **Shift+Tab**: cycle through categories.
- **/**: search by task name, description, category, or ID. **Esc** clears the filter.
- **A**: select or clear tasks currently shown by the category and search filters.
- **1**, **2**, **3**, **4**: Minimal, Productivity, Developer, or Complete preset.
- **?**: keyboard shortcut help.
- **Enter**: review the selection, then Enter again to begin. **B** returns to editing.
- **Q** or **Ctrl+C**: cancel without making changes.

Deselecting a prerequisite also deselects tasks that require it. A selected task is
an instruction to check and, if needed, configure that component; deselecting does
**not** uninstall an already installed application.

The picker never performs installations by itself. Applying the selection uses the
existing task previews, confirmation prompts, prerequisite checks, and local recovery
journal. Guided permission steps are not silently marked complete.

If you are scripting installation, use task IDs or a preset instead of the picker.
`--yes` approves automated tasks only; guided steps remain pending.

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

`update` reapplies previously installed profiles bundled in the current executable.
Install a newer CLI build first to obtain newer profiles. It does not download an updated public profile, upgrade every Homebrew package,
or replace the executable itself.

## Included tasks

- Homebrew guidance; AeroSpace, SketchyBar, Vorssaint, Raycast, Karabiner, Alacritty,
  Atuin, fonts, Python and ImageMagick installation through Homebrew.
- Portable AeroSpace workspaces, app rules and bindings; SketchyBar workspace bar,
  clock, fonts and accent; Karabiner shortcuts; Alacritty and Atuin preferences.
- A snapshot of 181 portable Vorssaint preferences, including quit-on-close.
  Quit Vorssaint before applying or restoring it. Launch it afterwards.
- Dock auto-hide with a five-second reveal delay, removal of ordinary pinned Dock
  items, hidden desktop files, dark appearance, Finder list view and tab preferences.
- A managed Atuin zsh initialization block and macOS global Git ignore rules that
  preserve existing rules.
- Guided Finder sidebar and icon sizing, display scaling, menu-bar auto-hide,
  two-finger secondary click, default icon colors, Liquid Glass, desktop widgets,
  app permissions and login items.
- Local wallpaper accent extraction. `setup wallpaper-colors` reads the current
  wallpaper; the `--image` option accepts a local image path if the wallpaper is
  unavailable. Image bytes are never uploaded.

The original full checklist is represented, but two pieces remain explicitly
pending: automatic wallpaper-change watching (the personal watcher source is
missing) and removal of system-managed Finder/launcher Dock controls. A reliable
long menu-bar reveal delay is also not implemented. These tasks are not falsely
marked complete. Finder list icon size and display modes use supported manual UIs.

## Public dotfiles source

The canonical portable configurations live in [dot-files](https://github.com/Roobahist/dot-files).
Vorssaint's separate sanitized preference snapshot remains managed by `mac-setup`.

There are two ways to install an application profile:

1. **Linked mode:** select **Link public dotfiles** in the checklist. This clones
   `dot-files` into `~/dot-files`. When you later select an application's profile
   task, only that application's configuration directory is linked into `~/.config`.
   Subsequent source changes are visible through the same symlink.
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

Tests use temporary homes and fake system commands. CI never applies the setup to
the runner's actual preferences. Real permission flows, display settings and app
behavior still need testing on a spare Mac or disposable user account before a
stable release.

MIT license. Third-party apps and fonts retain their own licenses; see NOTICE.md.
