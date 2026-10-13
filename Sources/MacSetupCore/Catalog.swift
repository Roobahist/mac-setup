import Foundation

public struct Preference {
    public let domain: String
    public let key: String
    public let value: Any
    public init(_ domain: String, _ key: String, _ value: Any) { self.domain = domain; self.key = key; self.value = value }
}

public enum TaskAction {
    case install(packages: [String], cask: Bool, app: String?)
    case profile([String])
    case preferences([Preference], restart: String?)
    case vorssaint
    case gitIgnore
    case atuinShell
    case service
    case accent
    case guide(url: String?, app: String?, instructions: [String])
}

public struct SetupTask {
    public let id: String
    public let category: String
    public let title: String
    public let summary: String
    public let dependencies: [String]
    public let action: TaskAction
    public init(_ id: String, _ category: String, _ title: String, _ summary: String, dependencies: [String] = [], action: TaskAction) {
        self.id = id; self.category = category; self.title = title; self.summary = summary; self.dependencies = dependencies; self.action = action
    }
    public var guided: Bool { if case .guide = action { return true }; return false }
}

public enum Catalog {
    public static let tasks: [SetupTask] = [
        SetupTask("homebrew", "Tools", "Homebrew", "Install the package manager if needed.", action: .guide(url: "https://brew.sh", app: nil, instructions: [
            "Follow Homebrew's official installation instructions in Terminal. It may request your administrator password and Command Line Tools.",
            "Finish the shell PATH instructions printed by the installer, then return here. No remote installation script is executed by mac-setup."
        ])),
        SetupTask("fonts", "Tools", "Interface and terminal fonts", "Install Hack Nerd Font and JetBrains Mono.", dependencies: ["homebrew"], action: .install(packages: ["font-hack-nerd-font", "font-jetbrains-mono"], cask: true, app: nil)),
        SetupTask("aerospace", "Window management", "AeroSpace", "Install the tiling window manager.", dependencies: ["homebrew"], action: .install(packages: ["nikitabobko/tap/aerospace"], cask: true, app: "AeroSpace")),
        SetupTask("aerospace-profile", "Window management", "AeroSpace configuration", "Apply workspace names, key bindings, app rules and SketchyBar integration. Replaces the AeroSpace config folder after backup.", dependencies: ["aerospace"], action: .profile(["aerospace"])),
        SetupTask("aerospace-access", "Window management", "AeroSpace access and launch", "Grant Accessibility, then verify that AeroSpace can list workspaces.", dependencies: ["aerospace-profile"], action: .guide(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", app: "AeroSpace", instructions: [
            "In Privacy & Security > Accessibility, add AeroSpace.app if it is missing and enable it.",
            "Launch AeroSpace. Resolve any config errors in its own UI. The profile uses config-version 2 and requires a version supporting it.",
            "In Desktop & Dock > Mission Control, turn off automatic Space rearrangement and keep Displays have separate Spaces enabled. macOS may require logout for the latter."
        ])),
        SetupTask("sketchybar", "Window management", "SketchyBar", "Install the custom menu bar.", dependencies: ["homebrew"], action: .install(packages: ["felixkratz/formulae/sketchybar"], cask: false, app: nil)),
        SetupTask("sketchybar-profile", "Window management", "SketchyBar configuration", "Apply the workspace bar, clock, fonts and colors. Replaces the SketchyBar config folder after backup.", dependencies: ["sketchybar", "aerospace-profile", "fonts"], action: .profile(["sketchybar"])),
        SetupTask("sketchybar-start", "Window management", "Start SketchyBar at login", "Start the user-level Homebrew service, or restart it after applying the profile.", dependencies: ["sketchybar-profile", "aerospace-access"], action: .service),
        SetupTask("vorssaint", "Apps", "Vorssaint", "Install the modular macOS utility (Apple silicon, macOS 14+).", dependencies: ["homebrew"], action: .install(packages: ["vorssaint"], cask: true, app: "Vorssaint")),
        SetupTask("vorssaint-profile", "Apps", "Vorssaint preferences", "Apply the portable preference snapshot, including quit-on-last-window. Quit Vorssaint first. Private snippets, shelf contents and machine state are excluded.", dependencies: ["vorssaint"], action: .vorssaint),
        SetupTask("vorssaint-access", "Apps", "Vorssaint access and remaining settings", "Finish permissions and settings that cannot be transferred as public preferences.", dependencies: ["vorssaint-profile"], action: .guide(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", app: "Vorssaint", instructions: [
            "Launch Vorssaint and complete its onboarding. Grant only permissions requested by the features you enable.",
            "Check Quit on close and select the apps it should affect. Test by closing an app's last window.",
            "Use Vorssaint's native Settings export/import for a full personal transfer, including defaults not persisted to disk. Review any export before sharing; never publish snippets or personal content.",
            "Enable launch at login in Vorssaint itself. The captured profile merges portable stored settings; it does not overwrite another Mac's private content or register login items."
        ])),
        SetupTask("raycast", "Apps", "Raycast", "Install Raycast. Account setup and personal extensions stay local.", dependencies: ["homebrew"], action: .install(packages: ["raycast"], cask: true, app: "Raycast")),
        SetupTask("raycast-access", "Apps", "Raycast setup", "Set the launcher shortcut and authorize the extensions you use.", dependencies: ["raycast"], action: .guide(url: nil, app: "Raycast", instructions: [
            "Complete Raycast onboarding and choose your launcher shortcut.",
            "Resolve the Spotlight shortcut conflict if necessary. Grant the permissions requested by your selected extensions.",
            "Enable launch at login in Raycast Settings if desired."
        ])),
        SetupTask("karabiner", "Apps", "Karabiner-Elements", "Install the keyboard remapping tool.", dependencies: ["homebrew"], action: .install(packages: ["karabiner-elements"], cask: true, app: "Karabiner-Elements")),
        SetupTask("karabiner-profile", "Apps", "Karabiner configuration", "Apply portable application shortcuts. Replaces the Karabiner config folder after backup; one optional generic key-sequence example is disabled.", dependencies: ["karabiner"], action: .profile(["karabiner"])),
        SetupTask("karabiner-access", "Apps", "Karabiner permissions", "Use Karabiner's own setup assistant for its helper permissions and driver approval.", dependencies: ["karabiner-profile"], action: .guide(url: "https://karabiner-elements.pqrs.org/docs/getting-started/installation/", app: "Karabiner-Elements", instructions: [
            "Follow every permission and driver-approval step shown by Karabiner-Elements. The exact helper names and panes depend on its version.",
            "Do not grant permissions to mac-setup as a substitute for Karabiner's helpers.",
            "Test Option+Return for Alacritty, Option+E for Finder, and Option+V for Visual Studio Code. Install those target apps if needed."
        ])),
        SetupTask("alacritty", "Terminal", "Alacritty", "Install the terminal used by the keyboard shortcuts.", dependencies: ["homebrew"], action: .install(packages: ["alacritty"], cask: true, app: "Alacritty")),
        SetupTask("alacritty-profile", "Terminal", "Alacritty configuration", "Apply the terminal font, transparency and dark palette.", dependencies: ["alacritty", "fonts"], action: .profile(["alacritty"])),
        SetupTask("atuin", "Terminal", "Atuin", "Install searchable shell history. No personal history or account is imported.", dependencies: ["homebrew"], action: .install(packages: ["atuin"], cask: false, app: nil)),
        SetupTask("atuin-profile", "Terminal", "Atuin preferences", "Apply Atuin configuration without history, encryption keys or session tokens.", dependencies: ["atuin"], action: .profile(["atuin"])),
        SetupTask("atuin-shell", "Terminal", "Enable Atuin in zsh", "Append one managed initialization block to .zshrc. Open a new shell afterwards.", dependencies: ["atuin-profile"], action: .atuinShell),
        SetupTask("git-ignore", "Terminal", "Global Git ignore", "Preserve existing rules and append standard macOS ignores. Save the previous Git setting.", action: .gitIgnore),
        SetupTask("dark-mode", "Appearance", "Dark mode", "Set dark appearance. A logout may be needed for every app to refresh.", action: .preferences([Preference("NSGlobalDomain", "AppleInterfaceStyle", "Dark")], restart: nil)),
        SetupTask("dock-hide", "Appearance", "Hide Dock with a long delay", "Enable auto-hide, set a five-second reveal delay, and hide recent apps. The undocumented delay setting may vary by macOS version.", action: .preferences([
            Preference("com.apple.dock", "autohide", true), Preference("com.apple.dock", "autohide-delay", 5.0), Preference("com.apple.dock", "show-recents", false)
        ], restart: "Dock")),
        SetupTask("dock-minimal", "Appearance", "Clear pinned Dock items", "Remove pinned app and folder tiles after backup. Running apps, Finder and Trash can still appear.", action: .preferences([
            Preference("com.apple.dock", "persistent-apps", [String]()), Preference("com.apple.dock", "persistent-others", [String]()), Preference("com.apple.dock", "show-recents", false)
        ], restart: "Dock")),
        SetupTask("desktop-clean", "Appearance", "Hide desktop files", "Hide Finder's desktop icons without deleting or moving files. Desktop widgets are a separate guided step.", action: .preferences([Preference("com.apple.finder", "CreateDesktop", false)], restart: "Finder")),
        SetupTask("finder-list", "Finder", "Default to list view", "Set the preferred Finder view to list. Existing folder view overrides may remain.", action: .preferences([Preference("com.apple.finder", "FXPreferredViewStyle", "Nlsv")], restart: "Finder")),
        SetupTask("finder-tabs", "Finder", "Prefer windows over tabs", "Disable Finder's folder-tab preference and set the system tab preference to Never. Explicit tab commands remain available.", action: .preferences([
            Preference("com.apple.finder", "FinderWindowTabs", false), Preference("NSGlobalDomain", "AppleWindowTabbingMode", "manual")
        ], restart: "Finder")),
        SetupTask("finder-icons", "Finder", "Larger list-view icons", "Use Finder's supported View Options UI.", action: .guide(url: nil, app: "Finder", instructions: [
            "Open your Home folder, choose View > as List, then View > Show View Options (Command+J).",
            "Choose the larger icon size and your preferred text size. Click Use as Defaults if available. Existing folders may retain individual view settings."
        ])),
        SetupTask("finder-sidebar", "Finder", "Clean up Finder sidebar", "Keep Home and Macintosh HD; remove unused favorites such as Desktop.", action: .guide(url: nil, app: "Finder", instructions: [
            "In Finder > Settings > Sidebar, enable your Home folder and Hard disks; disable unused entries such as Desktop.",
            "Drag useful folders into Favorites. Remove an existing favorite using its context menu > Remove from Sidebar. This removes the shortcut, not the folder.",
            "Macintosh HD appears under Locations; its name can differ on other Macs."
        ])),
        SetupTask("display-scaling", "Appearance", "Larger text and display scaling", "Choose a suitable scaled resolution for each connected display.", action: .guide(url: "x-apple.systempreferences:com.apple.preference.displays", app: nil, instructions: [
            "In Displays, select each display and choose Larger Text or a lower effective resolution that looks comfortable.",
            "Use a mode offered by this Mac. Do not copy a numeric resolution from a different monitor."
        ])),
        SetupTask("menu-bar", "Appearance", "Hide the system menu bar", "Use Always auto-hide so SketchyBar can occupy the top edge.", action: .guide(url: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension", app: nil, instructions: [
            "Find Menu Bar settings (or Control Center / Desktop & Dock on older macOS) and set Automatically hide and show the menu bar to Always.",
            "A long reveal delay has not been established as a reliable setting here. That part remains unimplemented; this task only covers auto-hide."
        ])),
        SetupTask("trackpad", "Appearance", "Two-finger secondary click", "Make clicking with two fingers perform a right click.", action: .guide(url: "x-apple.systempreferences:com.apple.preference.trackpad", app: nil, instructions: [
            "In Trackpad > Point & Click, set Secondary click to Click with Two Fingers.",
            "Test the gesture on a file in Finder. This profile does not change tap-to-click."
        ])),
        SetupTask("appearance-details", "Appearance", "Default icon colors and Liquid Glass", "Use the default icon appearance and the most transparent available glass style.", action: .guide(url: "x-apple.systempreferences:com.apple.Appearance-Settings.extension", app: nil, instructions: [
            "Keep dark system appearance but choose the default icon style rather than tinted or clear icons, where macOS exposes that choice.",
            "Choose the clear Liquid Glass style if available. Check Accessibility > Display for Reduce Transparency if glass appears opaque.",
            "Older macOS releases may not offer these controls. Record this task as skipped on unsupported systems."
        ])),
        SetupTask("desktop-widgets", "Appearance", "Hide desktop widgets", "Finish the clean desktop by turning off desktop widgets.", action: .guide(url: "x-apple.systempreferences:com.apple.Desktop-Settings.extension", app: nil, instructions: [
            "In Desktop & Dock, turn off Show Widgets on Desktop, and disable showing items on the desktop if that control is present.",
            "Files remain accessible in the Desktop folder."
        ])),
        SetupTask("wallpaper-tools", "Appearance", "Wallpaper color dependencies", "Install Python and ImageMagick for local accent extraction.", dependencies: ["homebrew"], action: .install(packages: ["python", "imagemagick"], cask: false, app: nil)),
        SetupTask("wallpaper-colors", "Appearance", "Match SketchyBar accent to wallpaper", "Extract an accent locally from the current wallpaper and update SketchyBar. Run again after a wallpaper change.", dependencies: ["wallpaper-tools", "sketchybar-profile"], action: .accent),
        SetupTask("wallpaper-watcher", "Appearance", "Automatic wallpaper color updates", "Configure the wallpaper-change watcher after its source is available.", action: .guide(url: nil, app: nil, instructions: [
            "The personal setup references WallpaperAccentWatcher, but its source is not in the shared dotfiles. This automatic integration still needs that source or an agreed replacement.",
            "For now, run mac-setup setup wallpaper-colors after changing the wallpaper. This task cannot be automatically verified."
        ])),
        SetupTask("dock-special-items", "Appearance", "Finder and launcher Dock items", "Review special Dock items that are not ordinary pinned apps.", action: .guide(url: "x-apple.systempreferences:com.apple.Desktop-Settings.extension", app: nil, instructions: [
            "The dock-minimal task removes ordinary pinned launchers. Finder and Trash are system-managed items.",
            "Removing system-managed Finder or newer launcher controls has not been implemented. Auto-hide keeps the Dock out of the way; no system files are patched."
        ]))
    ]

    public static func task(_ id: String) throws -> SetupTask {
        guard let task = tasks.first(where: { $0.id == id }) else { throw SetupError("Unknown task '\(id)'. Run mac-setup list.") }
        return task
    }

    public static func ordered(_ ids: [String]) throws -> [SetupTask] {
        var result: [SetupTask] = []; var visiting = Set<String>(); var visited = Set<String>()
        func visit(_ id: String) throws {
            if visited.contains(id) { return }
            guard visiting.insert(id).inserted else { throw SetupError("Task dependency cycle: \(id)") }
            let item = try task(id)
            for dependency in item.dependencies { try visit(dependency) }
            visiting.remove(id); visited.insert(id); result.append(item)
        }
        for id in ids { try visit(id) }
        return result
    }
}
