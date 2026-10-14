# Mac Setup

Mac Setup is a native macOS app and CLI for setting up and maintaining a portable desktop configuration. Our app includes task selection, shared keyboard shortcuts, editable workspaces, preview of the SketchyBar layout, guided permissions, copyable logs, and recovery records.

The portable configurations come from [dot-files](https://github.com/Roobahist/dot-files), with offline snapshots bundled into builds.

## Start here: install and open the app

macOS 13+ is required. Building from source requires Swift 5.9+ and compatible Command Line Tools or Xcode. Vorssaint requires Apple silicon and macOS 14+.

Run the installer as your normal macOS user, without `sudo`:

```sh
git clone https://github.com/Roobahist/mac-setup.git
cd mac-setup
bash install.sh
open "$HOME/Applications/Mac Setup.app"
```

The installer creates `~/Applications/Mac Setup.app` as a link to the managed bundle in `~/.local/lib/mac-setup/current`. Reopen it from Finder to make later adjustments. To rebuild after a source update, run `git pull && bash install.sh`.

## How setup works

1. **Choose features.** Select a preset or individual tasks. Existing apps are kept; Obsidian and Tomito are optional installers.
2. **Keyboard shortcuts.** Browse the AeroSpace, Karabiner, and Raycast shortcut sections. Add, edit, disable, or remove supported action bindings, and choose consistent modifiers for workspace switching and moving windows. Raycast has one editable launcher hotkey. Changes are written into the actual provider profiles and preferences; no redundant confirmation checkbox is required.
3. **Workspaces.** Drag whole cards to insert them at a new position. Edit workspace names, pick symbols from installed fonts, select assigned apps, and choose a letter or number for each workspace. Both workspace actions share that key and use the global modifiers from the previous step.
4. **Review.** See the exact tasks that will run.
5. **Set up & test.** Apply the tasks and check permissions and physical shortcuts. Copy the timestamped apply log if anything needs troubleshooting.

Workspace cards use consistent-sized controls and a clearly labeled drag handle. The menu-bar preview is visually separated from the editor with a dark bar treatment, while the cards use translucent macOS materials. Entire category headers on the feature-selection page are clickable.

### Make changes later without repeating installation

Use **Edit workspaces only** or **Edit shortcuts only** from the app's first screen. Or open either editor directly:

```sh
mac-setup workspaces
mac-setup shortcuts
```

These paths apply only the relevant provider profiles, rather than restarting the entire installer. The full setup is available with `mac-setup`. The older terminal editor remains available through `mac-setup terminal`.

### Workspace cards and shortcut readability

Workspaces are edited as compact, individually bordered rows. The grip icon at the left indicates that the entire row can be dragged to insert it at a different position. Workspace icon, application assignment, destination key, and removal controls are compact and have descriptive accessibility labels and hover help.

Keyboard shortcuts have larger key-combination chips; the editor shows installed app icons for application shortcuts and provider icons otherwise. AeroSpace bindings are canonicalized before generation, so modifier-order permutations such as `alt-ctrl-down` and `ctrl-alt-down` cannot both be emitted. Generated bindings are checked for duplicates before writing the configuration.

Vorssaint floating-point settings use a small numeric tolerance when verifying macOS `defaults` writes; strings, booleans, and meaningful numeric differences still require exact values. Appearance checklists only instruct users to configure Liquid Glass on supported macOS versions.

### Login and native menu bar

Our full, productivity and repair setups include **Start essential apps at login**. When selected, Mac Setup registers installed AeroSpace, Karabiner-Elements and Raycast under **System Settings > General > Login Items & Extensions > Open at Login**, without removing existing items or duplicating an already registered app. macOS may require permission for Mac Setup to automate System Events. Restoring the setup transaction removes only the login items created by that run.

SketchyBar continues to start through its existing Homebrew user service. WallpaperAccentWatcher starts from its existing user LaunchAgent and may appear under **Allow in Background**, not **Open at Login**. Karabiner's drivers and helper services also retain their own system-managed startup and permission requirements. We never replace these with duplicate boot processes.

On macOS 26 and later, setup includes the **Native menu bar background** check. In **System Settings > Menu Bar**, enable **Show menu bar background** so the auto-hidden native menu bar has its own blurred surface when it appears over SketchyBar. Apple has not documented a stable command-line preference for this switch, so Mac Setup links to the real system setting rather than writing an unverified key. This does not globally enable Reduce Transparency or change SketchyBar's palette.

The public dotfiles are the source of truth for unrelated window rules. System Settings and Screen Continuity are tiled just as their source profile specifies. Mac Setup only substitutes generated workspace keys, app assignments, and host-specific layout geometry.

### Shortcut behavior

All supported AeroSpace bindings in the bundled main-mode configuration are editable. Additional shortcuts may reuse available actions. Karabiner application shortcuts can use built-in app-opening scripts or a validated application bundle ID. Advanced stateful Karabiner rules, such as the Chrome chord remapping, remain preserved in the Portable profile and can be disabled or edited through a validated JSON editor. They cannot be represented faithfully as ordinary single-chord shortcuts. The Raycast launcher combination is editable and synchronized with its macOS preference.

The shortcut editor checks for duplicate combinations across all three providers and workspace destinations, and rejects collisions with the generated AeroSpace settings. Supported shortcut choices are stored in `~/Library/Application Support/mac-setup/shortcuts.json` before profiles are applied. To change only shortcuts, run `mac-setup shortcuts`.



The default number-row workspace shortcuts are **Option + key** for switching and **Option + Shift + key** for moving windows. Raycast opens with **Option + R** by default. **Option + Return** launches macOS Terminal unless you select another installed terminal in the Karabiner shortcuts editor. Change these global modifier sets in the shortcut step. Each workspace card only controls the key itself. If no key is assigned, that workspace still appears in SketchyBar. Conflicting keys and reserved AeroSpace bindings are rejected.

Earlier saved layouts are decoded and retain their chosen destination key; existing per-workspace modifier choices are normalized to the global modifier sets. Workspace configuration is saved in `~/Library/Application Support/mac-setup/workspaces.json`.

### Vorssaint defaults

The bundled Vorssaint 3.4.1 native settings export is applied automatically during **Vorssaint preferences** setup, including the feature configuration and launch-at-login preference. The public snapshot includes over 700 portable settings. Personal text snippet contents are excluded so they cannot be published accidentally. macOS system permissions and login item approval still require explicit user authorization, but settings do not need to be recreated manually.

### Terminal selection and interrupted setup

Terminal installation is optional. A complete setup does not automatically install Alacritty because the Homebrew cask may be disabled. Install Ghostty, WezTerm, Kitty or another terminal if you prefer, or use the Terminal app already included with macOS. In the shortcuts editor, set the terminal launch binding to **Open application by bundle ID** to route it to your preferred emulator.

If an installation fails, choose **Change selection** to return to the feature list, uncheck the unavailable app and any related profile, and press **Resume setup**. Completed steps stay completed, and the app continues without rescanning them. A failure can also be retried or left pending. Keep the app open while editing an interrupted run; cross-relaunch session recovery is not yet supported.

The Raycast default is Option + R. Legacy configurations using the former Command + Space default are migrated once; customized launcher shortcuts remain unchanged.

### Guided permissions and wallpaper accents

Multi-step permission guides display instructions as individual rows. Karabiner's background services, driver extension, Accessibility, Input Monitoring, and profile configuration each have an adjacent settings or app shortcut and a local **Check this step** action. Verified states are shown beside their corresponding instructions. macOS still requires users to approve all permissions; setup does not silently grant access.

Wallpaper accent extraction normalizes large images once before performing its analysis, avoiding repeated full-resolution ImageMagick decodes. Each image processing stage has a bounded timeout, and the complete accent task has a longer 120-second budget in both the CLI and native app. Other setup commands retain their existing timeout. When extraction fails, the app shows the specific ImageMagick stage error instead of asking users to open Python as if it were an application. The wallpaper accent is still computed locally and the watcher remains the existing WallpaperAccentWatcher app.

### Finder folder views

macOS Finder uses global preferences for newly opened folders, but existing directories may keep their own `.DS_Store` view overrides. The optional **Reset saved folder view overrides** task backs up and removes these files under Desktop, Documents, Downloads, Movies, Music and Pictures. It intentionally excludes Library, hidden directories, application packages and symlinks. Clearing `.DS_Store` also resets per-folder icon positions and window layout, so this task requires explicit selection. Prior files can be restored using Mac Setup's recovery journal.

### SketchyBar, AeroSpace and Dock

Workspace inactive coloring follows our public dotfiles palette; the previously divergent gray value was corrected. SketchyBar geometry recalculation now responds to display change and wake events without a 15-second polling timer, avoiding redundant bar repaints. System Settings and Continuity auxiliary windows are kept floating instead of entering AeroSpace's tile tree. The Dock auto-hide delay is set to zero, though macOS can still apply its own animation and edge-trigger timing.

### Optional applications and routing

An app may belong to only one workspace. Its assignment routes new windows but does not install or launch the app. The Music, Notes, and Pomodoro workspaces remain in the layout even when Spotify, Obsidian, or Tomito is not available. In that case, missing optional app assignments are left out of generated rules unless the app is selected for installation. The workspace itself is never deleted.

### Logs, checks, and backups

Select **Copy log** during a run or on a failure/completion screen to copy the current session's timestamped task history, outcomes, errors, and available installer output. Password responses are entered through a secure field, not saved as configuration. Review logs before sharing them, as installer output may include private system details.

We create backups before replacing configuration files and changed preferences. They live in `~/Library/Application Support/mac-setup`. Installation and permission changes are not silently reversed: examine recovery entries before restoring.

AeroSpace needs Accessibility access; Karabiner requires its own services, driver extension, Accessibility and Input Monitoring, virtual keyboard and Portable profile. Raycast uses the chosen launcher combination (Command+Space by default); setup backs up and disables Spotlight's conflicting shortcut only when that default combination is selected. Apple privacy permissions always require user approval.

```sh
mac-setup list
mac-setup status
mac-setup plan --preset productivity
mac-setup backups
mac-setup restore --dry-run
mac-setup restore
mac-setup dotfiles status
mac-setup dotfiles update
```

`setup --yes` applies automatic tasks only and leaves guided checks pending. `mac-setup update` reapplies installed bundled profiles, not app updates.

## Development and releases

We maintain public portable configurations in [dot-files](https://github.com/Roobahist/dot-files). Linking is optional. AeroSpace and SketchyBar are generated locally so editing workspaces never modifies the public checkout. We preserve unrelated symlinks instead of overwriting them.

```sh
python3 scripts/check-profile.py
swift test
bash scripts/package.sh
```

The [Releases](https://github.com/Roobahist/mac-setup/releases) page provides packaged builds when available. Builds are ad-hoc signed, not notarized; macOS may require a one-time approval in System Settings > Privacy & Security. We do not disable Gatekeeper.

Our portable snapshots exclude private sessions and account data. Local recovery files may include sensitive previous settings and must not be committed publicly.
