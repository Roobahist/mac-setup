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
2. **Keyboard shortcuts.** Confirm the shortcuts owned by AeroSpace, Karabiner, and Raycast. The global workspace switch and move-window modifiers are adjustable here, with one consistent base for all workspaces. AeroSpace manages focus, moving and resizing windows; Karabiner handles app launch mappings; Raycast uses Command+Space.
3. **Workspaces.** Drag whole cards to insert them at a new position. Edit workspace names, pick symbols from installed fonts, select assigned apps, and choose a letter or number for each workspace. Both workspace actions share that key and use the global modifiers from the previous step.
4. **Review.** See the exact tasks that will run.
5. **Set up & test.** Apply the tasks and check permissions and physical shortcuts. Copy the timestamped apply log if anything needs troubleshooting.

Our workspace cards and full-width preview use the macOS system material, which adapts to appearance settings and translucent surfaces.

### Make changes later without repeating installation

Use **Edit workspaces only** or **Edit shortcuts only** from the app's first screen. Or open either editor directly:

```sh
mac-setup workspaces
mac-setup shortcuts
```

These paths apply only the relevant workspace profiles, rather than restarting the entire installer. The full setup is available with `mac-setup`. The older terminal editor remains available through `mac-setup terminal`.

### Shortcut behavior

The default number-row workspace shortcuts are **Option + key** for switching and **Option + Shift + key** for moving windows. Change these global modifier sets in the shortcut step. Each workspace card only controls the key itself. If no key is assigned, that workspace still appears in SketchyBar. Conflicting keys and reserved AeroSpace bindings are rejected.

Earlier saved layouts are decoded and retain their chosen destination key; existing per-workspace modifier choices are normalized to the global modifier sets. Workspace configuration is saved in `~/Library/Application Support/mac-setup/workspaces.json`.

### Optional applications and routing

An app may belong to only one workspace. Its assignment routes new windows but does not install or launch the app. The Music, Notes, and Pomodoro workspaces remain in the layout even when Spotify, Obsidian, or Tomito is not available. In that case, missing optional app assignments are left out of generated rules unless the app is selected for installation. The workspace itself is never deleted.

### Logs, checks, and backups

Select **Copy log** during a run or on a failure/completion screen to copy the current session's timestamped task history, outcomes, errors, and available installer output. Password responses are entered through a secure field, not saved as configuration. Review logs before sharing them, as installer output may include private system details.

We create backups before replacing configuration files and changed preferences. They live in `~/Library/Application Support/mac-setup`. Installation and permission changes are not silently reversed: examine recovery entries before restoring.

AeroSpace needs Accessibility access; Karabiner requires its own services, driver extension, Accessibility and Input Monitoring, virtual keyboard and Portable profile. Raycast uses Command+Space, and setup backs up and disables the conflicting Spotlight shortcut. Apple privacy permissions always require user approval.

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
