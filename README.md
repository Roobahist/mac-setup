# mac-setup

A native Swift setup app and companion CLI for reproducing a macOS setup,
with readable guidance, workspace previews, readiness checks and recovery records.

Choose a repair or installation preset, preview the changes, then apply and test
them in one Swift window. The public configurations
come from [dot-files](https://github.com/Roobahist/dot-files); offline snapshots are
bundled with every release. No GitHub account is required to run downloaded builds.

## Start here: install and open the app

Requires macOS 13+. Building from source also requires Swift 5.9+
(Xcode or compatible Command Line Tools).
Some installed apps have higher requirements; Vorssaint requires Apple silicon
and macOS 14+. Run the installer as your normal user, without `sudo`.

**Cloning this repo gives you source code. Run the one-time installer below to
build and install Mac Setup.app, then open its window.**

In Terminal, run:

```sh
git clone https://github.com/Roobahist/mac-setup.git
cd mac-setup
bash install.sh
open "$HOME/Applications/Mac Setup.app"
```

The last command opens the **graphical Mac Setup app**. Keep **Repair** selected,
click **Continue**, check the workspace preview, then **Review changes → Start setup**.
The remaining setup, installer prompts and permission checks appear in that window.

**Next time, use Finder:** choose **Go → Home**, open **Applications**, then
double-click **Mac Setup**. This is the Applications folder inside your home folder.
You do not need Terminal for later launches.

Where the app is stored compared with the cloned repo:

| Location | What it contains |
| --- | --- |
| The cloned `mac-setup` folder | Source code and build scripts. A fresh clone has no prebuilt `.app`. |
| `~/Applications/Mac Setup.app` | The installed app you open in Finder; a link to the managed app bundle. |
| `~/.local/lib/mac-setup/current/Mac Setup.app` | The managed app bundle used by that link. |

If you previously installed an older CLI, update it from inside your existing clone:

```sh
git pull
bash install.sh
open "$HOME/Applications/Mac Setup.app"
```

If the installer reports an existing unrelated Mac Setup app, it preserves it and
prints the exact path and launch command for the newly installed app instead.

The installer also provides optional command-line tools in `~/.local/bin` and backs
up `.zshrc` before adding that directory to PATH. Linked shell configuration files
are left for you to update manually. After changing source code, run `bash install.sh`
again to rebuild and update. Normal app launches do not rebuild anything.

The build helper uses SwiftPM's native engine for compatibility with Command Line
Tools. This avoids the missing Xcode framework search-path warnings from Swift
6.4's default build engine. Those warnings did not indicate a failed setup.

## Using the app

After opening **Mac Setup.app**, its window has four steps:

1. **Choose features.** Repair is selected by default and targets the reported Dock,
   menu-bar, workspace, launcher and keyboard problems. Expand a section to change
   individual tasks, or select another preset. Installed applications are kept.
2. **Workspaces.** Preview the bar, change names and icons, reorder workspaces,
   and assign installed apps. Use **Shortcuts…** beside any workspace to change its
   switch and move-window combinations. The number row remains the default.
3. **Review.** Read the selected changes before pressing Start setup once.
4. **Set up & test.** Automatic tasks run in the app. Each guided task opens its
   relevant application and shows explicit choices, numbered checks, Check again,
   and Test passed. A failed task offers Retry, Review selection, or Leave pending.

Installer output and a secure response field stay inside the Swift window, including
Homebrew's administrator prompts. The response goes directly to the local installer.
No password is saved by mac-setup. Privacy and driver approvals still require the
user's action in the application's assistant or System Settings.

AeroSpace must be running and see windows before its guide can complete. Karabiner
must report working services, Accessibility, Input Monitoring, its driver, virtual
keyboard and the Portable profile; a previous yes/no answer cannot bypass these
checks. Test the physical keyboard shortcuts before continuing.

The Repair preset assigns **Command+Space** to Raycast and disables only Spotlight’s
conflicting Show Spotlight search shortcut after backing up the existing shortcuts.
Its guide explains which optional account/AI/extension screens to skip and how to
test Command+Space and resolve any onboarding override. Vorssaint's replacement app switcher is disabled
in this AeroSpace profile so native Command+Tab can follow workspace focus. The
remaining guide enables quit-on-close and explains the required Accessibility and
launch-at-login choices. Permission Settings open from a separate button, so they
cannot obscure an app's onboarding window as soon as it opens.

Finder, Dock and SystemUIServer refresh once at the end. The Dock is placed at the
bottom with a one-second reveal delay and a short animation. Menu-bar auto-hide
covers the desktop and fullscreen. Its reveal timing is controlled by macOS; if the
visible preference has not refreshed, set it to Always in System Settings and log
out and back in. Stored defaults alone do not prove visible behavior.

Use `mac-setup terminal` for the legacy keyboard picker. Scripted `setup --yes`
applies automatic tasks only and leaves guided tasks pending. Read-only `plan` and
`status` remain available. Explicit interactive `setup` selections open the Swift app.

## Customize workspaces

Workspace configuration is Step 2 whenever AeroSpace configuration is selected.
Use the native controls to rename, reorder, delete or add workspaces; the Apps
button shows installed applications with a searchable checklist. An app can be
assigned to only one workspace. Assignments route new windows; they do not install
or launch the application.

There is no 13-workspace limit. The first 13 positions default to **Option +
number-row key** for switching and **Option + Shift + that key** for moving a window,
including backtick, minus and equals. Click **Shortcuts… → Custom** to choose a
combination of Control, Option, Shift and Command with a letter, number, function
key, navigation key or other supported key. Switch and move-window shortcuts are
independent; either can be turned off. Custom shortcuts stay attached to their
workspace when you reorder it, while default shortcuts follow the displayed order.

Additional workspaces start without a shortcut once the number row is full. Give
them a custom combination or click their SketchyBar icon to switch. Duplicate
combinations and conflicts with the profile's other AeroSpace bindings are shown
before you save or apply. For example, **Control + Option + R** can switch to a
Research workspace and **Control + Option + Shift + R** can move a window there.

Your choices are saved locally in
`~/Library/Application Support/mac-setup/workspaces.json` when setup starts.
The optional timer workspace is emitted only when Tomito is selected. AeroSpace and
SketchyBar are generated as backed-up local copies rather than changes to a public
Git checkout. Glyph mappings have one definition. The five default symbols exactly match the
reference Mac’s SF Pro characters, while numbers and additional glyphs use Hack Nerd
Font at 14.5 points in 21-point slots. The native preview uses those same fonts and sizes.
The bar refreshes after application switching and wake, with a periodic recovery
check for missed workspace events.

SketchyBar’s height is measured in logical points from the host’s system status bar
and display safe areas. Notched displays receive a separate height override. AeroSpace
uses per-display gaps and subtracts the top area already reserved by macOS, so the
notch is not counted twice. A compiled helper keeps both configurations aligned after
monitor, resolution and scaling changes; it requires no Swift or Xcode on the receiving
Mac. Only the marked generated top-gap line is runtime-managed. Restore still checks
all other configuration edits. `topmost=window` and zero offsets keep SketchyBar over
application windows at the top edge, below the native menu bar when it reveals.

Karabiner’s guide separately records background services, Driver Extension,
Accessibility, Input Monitoring and virtual-keyboard/profile readiness. These checks
are refreshed from Karabiner and saved locally in
`~/Library/Application Support/mac-setup/guided-checklist.json`; pending steps can be
resumed. The driver and privacy approvals require the user’s action in System Settings.
The physical shortcut test is never inferred from service registration.

## Download the app instead of building from source

When a published build is available in [Releases](https://github.com/Roobahist/mac-setup/releases),
download the archive for your processor: `arm64` for Apple silicon or `x86_64` for Intel.
Extract the `.tar.gz` archive and double-click **Mac Setup.app** inside the extracted
folder. You can move it to your home **Applications** folder for later launches.
Downloaded apps do not require Swift or Xcode.

If Releases is empty, use the source installation above. Apple silicon preview builds
are also available from successful [Build and test runs](https://github.com/Roobahist/mac-setup/actions/workflows/ci.yml):
open a run, download its **mac-setup-preview-arm64** artifact (requires a GitHub login),
extract the downloaded ZIP, then extract the `.tar.gz` inside it and open **Mac Setup.app**.

If you build a package yourself with `bash scripts/package.sh`, the app is inside
the generated package folder under the clone's `dist` directory. Packaging alone
does not install it in your home Applications folder.

These builds use local ad-hoc signatures, not Apple Developer ID signing or
notarization. macOS may require an app-specific approval in System Settings >
Privacy & Security after a first launch attempt. Managed Macs may restrict it.
The installer does not disable Gatekeeper or remove quarantine attributes.

## Optional command-line tools

The app is the main setup interface. The installed `mac-setup` command with no
arguments opens the same app window; `mac-setup terminal` explicitly opens the
legacy terminal picker. These commands are available for scripting and diagnostics:

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

The default command opens the native Swift app. `status` distinguishes
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
- Dock auto-hide with a one-second reveal delay, removal of ordinary pinned Dock
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

Homebrew setup runs the official installer in the Swift window when missing, including
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
