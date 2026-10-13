# mac-setup

A guided macOS setup CLI for apps, dotfiles, and system preferences.

Choose changes one by one, preview them, and keep recovery records. The public
configuration profile is bundled with each release. No access to the author's
private dotfiles repository or GitHub account is required.

## Run from source

Requires macOS 13+ and Swift 5.9+ (Xcode or compatible Command Line Tools).
Some installed apps have higher requirements; Vorssaint requires Apple silicon
and macOS 14+. The CLI never runs as root.

```sh
git clone https://github.com/Roobahist/mac-setup.git
cd mac-setup
swift run mac-setup plan
swift run mac-setup
```

`plan` is read-only. The interactive menu shows task numbers and IDs, includes
prerequisites, and asks before each task. Skipping a prerequisite leaves dependent
tasks pending. `--yes` approves automatic tasks only; permission and Settings steps
remain pending rather than being silently marked complete.

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
mac-setup list
mac-setup status
mac-setup plan aerospace-profile sketchybar-start
mac-setup setup aerospace-profile sketchybar-start
mac-setup setup --all --dry-run
mac-setup backups
mac-setup restore --dry-run
mac-setup restore
mac-setup update
mac-setup watcher-status
mac-setup watcher-stop
```

The default command opens the interactive checklist. `status` distinguishes
automatically verified state, guided steps, and steps the user confirmed.
Stored preference verification does not guarantee the visible behavior of an
undocumented setting on every macOS release.

`update` reapplies previously installed profiles bundled in the current executable.
It also refreshes a previously installed wallpaper watcher runtime when changed.
Install a newer CLI build first to obtain newer profiles. It does not pull a private
repository, upgrade every Homebrew package, or replace the executable itself.

## Included tasks

- Homebrew guidance; AeroSpace, SketchyBar, Vorssaint, Raycast, Karabiner, Alacritty,
  Atuin, fonts, Python and ImageMagick installation through Homebrew.
- Portable AeroSpace workspaces, app rules and bindings; SketchyBar workspace bar,
  clock, fonts and accent; Karabiner shortcuts; Alacritty and Atuin preferences.
- A snapshot of 786 portable Vorssaint settings from the native 3.4.1 export,
  including defaults, quit-on-close exceptions and feature choices.
  Quit Vorssaint before applying or restoring it. Launch it afterwards.
- Dock auto-hide with a five-second reveal delay, removal of ordinary pinned Dock
  items, hidden desktop files, dark appearance, Finder list view, 32-point default
  list icons, and tab preferences. Other Finder View Options are preserved.
- A managed Atuin zsh initialization block and macOS global Git ignore rules that
  preserve existing rules.
- Guided Finder sidebar and icon sizing, display scaling, menu-bar auto-hide,
  two-finger secondary click, default icon colors, Liquid Glass, desktop widgets,
  app permissions and login items.
- Local wallpaper accent extraction. `setup wallpaper-colors` reads the current
  wallpaper; the `--image` option accepts a local image path if the wallpaper is
  unavailable. Image bytes are never uploaded.
- A startup wallpaper watcher adapted from the author's existing watcher. It
  uses a private copy of the CLI, polls the main display every two seconds,
  debounces changes, detects overwritten image files, and retries errors.

The original full checklist is represented. Removal of system-managed
Finder/launcher Dock controls remains explicitly pending. A reliable
long menu-bar reveal delay is also not implemented. These tasks are not falsely
marked complete. Finder View Options have a guided visual check for existing-folder
overrides; display modes use the supported manual UI.

## Your data and backups

The public profile has no personal snippets, shelf contents, Atuin database,
authentication session, device bookmarks or private Git history. Karabiner uses
recipient-relative paths; disabled personal grading macros are removed. A full
personal Vorssaint transfer can use its native export/import. The public profile is
now based on that native export and includes default values. Ten keys are excluded:
snippets, private recorder presets, audio-device choices, volume exclusions, login
registration, live fan/awake state and screenshot numbering. `profile.json` lists
the exclusions. Portable onboarding flags travel; operating-system permission
grants never do. Raw exports must be reviewed before sharing.

Profile installation merges bundled files into the relevant config folders,
preserving unrelated files. If a config folder is a symlink into a personal repo,
the installer backs up that symlink and detaches it into an ordinary local folder;
it does not edit the linked repo. A symlinked parent config directory is rejected.
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
startup watcher registration/runtime, and a SketchyBar service newly started by
this tool. It does not uninstall apps,
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

## Wallpaper watcher

`mac-setup setup wallpaper-watcher` previews and installs a private runtime copy
under `~/Library/Application Support/mac-setup/watcher-runtime` and a user LaunchAgent
named `io.github.roobahist.mac-setup.wallpaper`. Moving the downloaded CLI does not
break the watcher. No separate graphical app is installed.

Only the active wallpaper on the main display supplies the accent. `watch` runs the
same behavior in the foreground; `watch --once` performs one refresh. `--image`
can select an accessible local image instead. The optional image choice is persisted
in a startup watcher installed with that option. Python and ImageMagick receive
image bytes locally; no image data is uploaded.

Run `watcher-status` to inspect registration and recent logs, then change wallpapers
to verify the visible result. Registration alone does not prove file access or a
healthy extraction. If the wallpaper provider stores an image in a protected
container, choose an accessible image or explicitly approve the runtime executable
in Privacy & Security > Full Disk Access. Permission given to Terminal does not
automatically authorize the startup executable. macOS may require reapproval after
a binary update. No permission database or security setting is edited by the CLI.

The original WallpaperAccentWatcher must be stopped before installing this watcher;
the CLI refuses to disable another tool's job. `watcher-stop` unloads the job but
retains its startup plist. Re-running setup registers it again. Restoring the
watcher installation backup unloads it and restores the previous runtime/plist;
if an older watcher installation was registered, it is registered again afterwards.
The last derived accent is left in place. Stop the watcher before restoring older
SketchyBar configuration backups; they may otherwise detect generated color edits.

The daemon only edits `HIGHLIGHT_COLOR` and refuses symlinked configuration paths
so it cannot alter a linked personal repository. Its own periodic writes do not
create an unlimited series of backups. Manual `setup wallpaper-colors` remains
backed up like any other setup task.
