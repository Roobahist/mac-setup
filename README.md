# mac-setup

A guided macOS setup CLI for apps, dotfiles, and system preferences.

Choose changes one by one, preview them, and keep recovery records. The public
configuration profile is bundled with each release. No GitHub account or repository checkout is required to run downloaded builds.

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
```

The default command opens the interactive checklist. `status` distinguishes
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

The portable application configurations are maintained in [dot-files](https://github.com/Roobahist/dot-files). This repository includes checked-in snapshots so a downloaded mac-setup release remains self-contained and works offline. The independent Vorssaint snapshot stays here.

To refresh bundled profiles from the canonical source, run:

```sh
python3 scripts/sync-dotfiles.py
python3 scripts/check-profile.py
swift test
```

A GitHub Actions workflow checks for updates hourly and when notified by the public dot-files repository. It opens a reviewable PR when profiles change. To enable immediate notifications, add a fine-grained token with Contents write permission limited to mac-setup as `MAC_SETUP_DISPATCH_TOKEN` in dot-files repository secrets. GitHub Actions may also need permission to create pull requests. The hourly sync works without that secret.

If you manage your own Mac with symlinks from a local dot-files checkout, use that repository's install and update scripts. Running mac-setup's profile installer intentionally backs up and detaches symlinks, so do not apply those profile tasks on top of a checkout you wish to keep linked.

## Your data and backups

The public profile has no personal snippets, shelf contents, Atuin database,
authentication session, device bookmarks or private Git history. Karabiner uses
$HOME-relative paths; one generic key-sequence example is disabled by default. A full
personal Vorssaint transfer can use its native export/import, but exports must be
reviewed before sharing. Stored settings alone cannot capture its unpersisted defaults.

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
