import Foundation

public struct Preference {
    public let domain: String
    public let key: String
    public let value: Any
    public init(_ domain: String, _ key: String, _ value: Any) { self.domain = domain; self.key = key; self.value = value }
}

public enum TaskAction {
    case homebrew
    case finderIcons
    case finderResetFolderViews
    case install(packages: [String], cask: Bool, app: String?)
    case profile([String])
    case appStore(app: String, url: String)
    case linkedDotfiles
    case preferences([Preference], restart: String?)
    case vorssaint
    case gitIgnore
    case atuinShell
    case service
    case accent
    case wallpaperWatcher
    case loginItems(names: [String])
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
    public var updatable: Bool {
        if id == "homebrew" { return true }
        if case .install = action { return true }
        return false
    }
    public var guided: Bool {
        switch action { case .guide, .appStore: return true; default: return false }
    }
}

public enum Catalog {
    public static let tasks: [SetupTask] = [
        SetupTask("homebrew", "Tools", "Homebrew", "Install Homebrew with its official installer when missing, then configure zsh. Administrator authentication and Command Line Tools approval may be requested.", action: .homebrew),
        SetupTask("dotfiles-linked", "Tools", "Link public dotfiles",
                  "Clone the public dot-files repository. Only selected application profiles are linked later. Requires Git.",
                  action: .linkedDotfiles),
        SetupTask("fonts", "Tools", "Interface and terminal fonts", "Install SF Pro for the reference workspace symbols, Hack Nerd Font, and JetBrains Mono.", dependencies: ["homebrew"], action: .install(packages: ["font-sf-pro", "font-hack-nerd-font", "font-jetbrains-mono"], cask: true, app: nil)),
        SetupTask("aerospace", "Window management", "AeroSpace", "Install the tiling window manager.", dependencies: ["homebrew"], action: .install(packages: ["nikitabobko/tap/aerospace"], cask: true, app: "AeroSpace")),
        SetupTask("aerospace-profile", "Window management", "AeroSpace configuration", "Apply workspace names, key bindings, app rules and SketchyBar integration. Replaces the AeroSpace config folder after backup.", dependencies: ["aerospace"], action: .profile(["aerospace"])),
        SetupTask("mission-control", "Window management", "Mission Control workspace settings", "Keep Space order fixed and enable separate Spaces per display. Log out and back in for the display setting to take effect.", dependencies: ["aerospace-profile"], action: .preferences([
            Preference("com.apple.dock", "mru-spaces", false),
            Preference("com.apple.spaces", "spans-displays", false)
        ], restart: "Dock")),
        SetupTask("aerospace-access", "Window management", "AeroSpace access and launch", "Grant Accessibility, then verify that AeroSpace can list workspaces.", dependencies: ["aerospace-profile"], action: .guide(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", app: "AeroSpace", instructions: [
            "In Privacy & Security > Accessibility, add AeroSpace.app if it is missing and enable it.",
            "Launch AeroSpace. Resolve any config errors in its own UI. The profile uses config-version 2 and requires a version supporting it.",
            "The mission-control task applies Space order and separate-display preferences automatically. Log out and back in before testing if those preferences changed."
        ])),
        SetupTask("sketchybar", "Window management", "SketchyBar", "Install the custom menu bar.", dependencies: ["homebrew"], action: .install(packages: ["felixkratz/formulae/sketchybar"], cask: false, app: nil)),
        SetupTask("sketchybar-profile", "Window management", "SketchyBar configuration", "Apply the workspace bar, clock, fonts and colors. Replaces the SketchyBar config folder after backup.", dependencies: ["sketchybar", "aerospace-profile", "fonts"], action: .profile(["sketchybar"])),
        SetupTask("sketchybar-start", "Window management", "Start SketchyBar at login", "Start the user-level Homebrew service, or restart it after applying the profile.", dependencies: ["sketchybar-profile", "aerospace-access"], action: .service),
        SetupTask("tomito", "Apps", "Tomito Pomodoro timer",
                  "Optional Mac App Store timer. Its workspace remains even when Tomito is not installed.",
                  action: .appStore(app: "Tomito", url: "macappstore://itunes.apple.com/app/id1526042938")),
        SetupTask("obsidian", "Apps", "Obsidian",
                  "Install Obsidian for local notes. The Notes workspace stays available if this task is unchecked.",
                  dependencies: ["homebrew"], action: .install(packages: ["obsidian"], cask: true, app: "Obsidian")),
        SetupTask("vorssaint", "Apps", "Vorssaint", "Install the modular macOS utility (Apple silicon, macOS 14+).", dependencies: ["homebrew"], action: .install(packages: ["vorssaint"], cask: true, app: "Vorssaint")),
        SetupTask("vorssaint-profile", "Apps", "Vorssaint preferences", "Automatically import the portable settings from the bundled Vorssaint 3.4.1 export. Personal text snippets are excluded. Existing preferences are backed up.", dependencies: ["vorssaint"], action: .vorssaint),
        SetupTask("vorssaint-access", "Apps", "Vorssaint system permissions",
                  "Check macOS permissions and login item registration. All exported preferences are applied automatically.",
                  dependencies: ["vorssaint-profile"],
                  action: .guide(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                                 app: "Vorssaint", instructions: [
            "The bundled Vorssaint preferences have already been imported. No manual settings recreation is required.",
            "Approve macOS Accessibility and other permissions for any active features. Apple requires the user to approve these access requests.",
            "If macOS has not registered Vorssaint as a login item, approve it in System Settings > General > Login Items & Extensions. The launch-at-login preference was imported automatically."
        ])),
        SetupTask("raycast", "Apps", "Raycast", "Install Raycast. Account setup and personal extensions stay local.", dependencies: ["homebrew"], action: .install(packages: ["raycast"], cask: true, app: "Raycast")),
        SetupTask("raycast-profile", "Apps", "Raycast launcher shortcut", "Apply the launcher shortcut chosen in Mac Setup. If it uses Command+Space, back up and disable the conflicting Spotlight shortcut.", dependencies: ["raycast"], action: .preferences([
            Preference("com.raycast.macos", "raycastGlobalHotkey", "Option-15")
        ], restart: nil)),
        SetupTask("raycast-access", "Apps", "Raycast setup", "Check the configured Raycast launcher shortcut and authorize the extensions you use.", dependencies: ["raycast-profile"], action: .guide(url: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension", app: "Raycast", instructions: [
            "If Raycast shows Welcome, continue with local setup. Skip account sign-in, AI, and extension suggestions if offered. Those are optional.",
            "Open Raycast Settings > General. Verify that the launcher shortcut matches the key combination selected in Mac Setup. Setup handles the Spotlight conflict when Command+Space was chosen.",
            "In Raycast Settings > General, enable Launch Raycast at login. Press the chosen launcher shortcut and confirm that Raycast opens."
        ])),
        SetupTask("karabiner", "Apps", "Karabiner-Elements", "Install the keyboard remapping tool.", dependencies: ["homebrew"], action: .install(packages: ["karabiner-elements"], cask: true, app: "Karabiner-Elements")),
        SetupTask("karabiner-profile", "Apps", "Karabiner configuration", "Render editable application hotkeys into Karabiner's Portable profile, preserving existing advanced rules. Back up the configuration first.", dependencies: ["karabiner"], action: .profile(["karabiner"])),
        SetupTask("karabiner-access", "Apps", "Karabiner permissions", "Use Karabiner's own setup assistant for its helper permissions and driver approval.", dependencies: ["karabiner-profile"], action: .guide(url: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension", app: "Karabiner-Elements", instructions: [
            "Background services: in System Settings > General > Login Items & Extensions, allow the Karabiner background services shown by its assistant. Keep the privileged core service and the user agent enabled.",
            "Driver Extension: in General > Login Items & Extensions > Driver Extensions, allow org.pqrs.Karabiner-DriverKit-VirtualHIDDevice. This is required even after installing Karabiner; without it the remappings do not work.",
            "Accessibility: in Privacy & Security > Accessibility, enable the Karabiner core service requested by its assistant. Approval for Mac Setup does not approve Karabiner.",
            "Input Monitoring: enable the Karabiner helper requested by its assistant under Privacy & Security > Input Monitoring if Karabiner still asks for it. Return to Karabiner after each approval.",
            "In Karabiner, select the Portable profile and the virtual keyboard layout matching your physical keyboard. Click Check again here; the step stays pending until the services, driver, virtual keyboard and permissions are ready.",
            "Test Option+Return for Alacritty, Option+E for Finder, and Option+V for Visual Studio Code. Install those target apps if needed."
        ])),
        SetupTask("alacritty", "Terminal", "Alacritty (optional)", "Optional terminal. Homebrew disabled its cask on some versions of macOS; select another terminal if unavailable.", dependencies: ["homebrew"], action: .install(packages: ["alacritty"], cask: true, app: "Alacritty")),
        SetupTask("alacritty-profile", "Terminal", "Alacritty configuration", "Apply the terminal font, transparency and dark palette.", dependencies: ["alacritty", "fonts"], action: .profile(["alacritty"])),
        SetupTask("ghostty", "Terminal", "Ghostty (optional)", "Install Ghostty, or keep your preferred existing terminal. Select its launch shortcut in the shortcuts editor.", dependencies: ["homebrew"], action: .install(packages: ["ghostty"], cask: true, app: "Ghostty")),
        SetupTask("wezterm", "Terminal", "WezTerm (optional)", "Install WezTerm. Terminal choice does not block other setup tasks.", dependencies: ["homebrew"], action: .install(packages: ["wezterm"], cask: true, app: "WezTerm")),
        SetupTask("kitty", "Terminal", "Kitty (optional)", "Install Kitty. Terminal choice does not block other setup tasks.", dependencies: ["homebrew"], action: .install(packages: ["kitty"], cask: true, app: "kitty")),
        SetupTask("atuin", "Terminal", "Atuin", "Install searchable shell history. No personal history or account is imported.", dependencies: ["homebrew"], action: .install(packages: ["atuin"], cask: false, app: nil)),
        SetupTask("atuin-profile", "Terminal", "Atuin preferences", "Apply Atuin configuration without history, encryption keys or session tokens.", dependencies: ["atuin"], action: .profile(["atuin"])),
        SetupTask("atuin-shell", "Terminal", "Enable Atuin in zsh", "Append one managed initialization block to .zshrc. Open a new shell afterwards.", dependencies: ["atuin-profile"], action: .atuinShell),
        SetupTask("git-ignore", "Terminal", "Global Git ignore", "Preserve existing rules and append standard macOS ignores. Save the previous Git setting.", action: .gitIgnore),
        SetupTask("dark-mode", "Appearance", "Dark mode", "Set dark appearance. A logout may be needed for every app to refresh.", action: .preferences([Preference("NSGlobalDomain", "AppleInterfaceStyle", "Dark")], restart: nil)),
        SetupTask("dock-hide", "Appearance", "Auto-hide Dock; reveal immediately", "Show the hidden Dock promptly when the pointer reaches its edge. macOS animation and edge-trigger behavior still apply.", action: .preferences([
            Preference("com.apple.dock", "autohide", true), Preference("com.apple.dock", "orientation", "bottom"), Preference("com.apple.dock", "autohide-time-modifier", 0.15), Preference("com.apple.dock", "autohide-delay", 0.0), Preference("com.apple.dock", "show-recents", false)
        ], restart: "Dock")),
        SetupTask("dock-minimal", "Appearance", "Clear pinned Dock items", "Remove pinned app and folder tiles after backup. Running apps, Finder and Trash can still appear.", action: .preferences([
            Preference("com.apple.dock", "persistent-apps", [String]()), Preference("com.apple.dock", "persistent-others", [String]()), Preference("com.apple.dock", "show-recents", false)
        ], restart: "Dock")),
        SetupTask("desktop-clean", "Appearance", "Hide desktop files", "Hide Finder's desktop icons without deleting or moving files. Desktop widgets are a separate task.", action: .preferences([Preference("com.apple.finder", "CreateDesktop", false)], restart: "Finder")),
        SetupTask("finder-list", "Finder", "Default to list view", "Set the preferred Finder view to list. Existing folder view overrides may remain.", action: .preferences([Preference("com.apple.finder", "FXPreferredViewStyle", "Nlsv")], restart: "Finder")),
        SetupTask("finder-tabs", "Finder", "Prefer windows over tabs", "Disable Finder's folder-tab preference and set the system tab preference to Never. Explicit tab commands remain available.", action: .preferences([
            Preference("com.apple.finder", "FinderWindowTabs", false), Preference("NSGlobalDomain", "AppleWindowTabbingMode", "manual")
        ], restart: "Finder")),
        SetupTask("finder-icons", "Finder", "Finder list-view settings", "Match the reference: list view, no groups, Date Modified sorting, large icons, text 13, selected columns, relative dates and previews. Existing folder overrides may remain.", dependencies: ["finder-list"], action: .finderIcons),
        SetupTask("finder-reset-views", "Finder", "Reset saved folder view overrides (optional)",
                  "Back up and clear .DS_Store view metadata in Desktop, Documents, Downloads, Movies, Music and Pictures. Resets folder icon positions and other per-folder customizations; excludes Library, hidden directories, packages and symlinks.",
                  dependencies: ["finder-icons"], action: .finderResetFolderViews),
        SetupTask("finder-view-check", "Finder", "Folder list-view behavior", "Check the folder-specific Always open and Browse in list view options from the reference.", dependencies: ["finder-icons"], action: .guide(url: nil, app: "Finder", instructions: [
            "Open Macintosh HD (or your startup disk) and press Command+J. Enable Always open in list view and Browse in list view.",
            "Check Group By: None; Sort By: Date Modified; large icons; text size 13; only Date Modified, Size and Kind columns besides Name; relative dates and icon previews enabled; Calculate all sizes disabled. Click Use as Defaults.",
            "Existing folders may override the global defaults in .DS_Store. Use the separate Reset saved folder view overrides task to back up and clear those overrides for your home folders. This also resets custom icon placement."
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
        SetupTask("menu-bar", "Appearance", "Hide the system menu bar", "Set menu-bar auto-hide to Always. Log out and back in if the visible menu bar has not refreshed.", action: .preferences([
            Preference("NSGlobalDomain", "_HIHideMenuBar", true),
            Preference("NSGlobalDomain", "AppleMenuBarVisibleInFullscreen", false),
            Preference("NSGlobalDomain", "AppleMenuBarVisibleInDesktop", false)
        ], restart: "SystemUIServer")),
        SetupTask("menu-bar-background", "Appearance", "Native menu bar background",
                  "On macOS 26 and newer, make the system menu bar visually distinct from SketchyBar when revealed.",
                  dependencies: ["menu-bar"],
                  action: menuBarBackgroundAction(macOSMajorVersion:
                      ProcessInfo.processInfo.operatingSystemVersion.majorVersion)),
        SetupTask("trackpad", "Appearance", "Two-finger secondary click", "Enable two-finger right-click and disable corner secondary clicks for built-in and Bluetooth trackpads. Tap-to-click is preserved; a logout may be needed.", action: .preferences([
            Preference("com.apple.AppleMultitouchTrackpad", "TrackpadRightClick", true),
            Preference("com.apple.AppleMultitouchTrackpad", "TrackpadCornerSecondaryClick", 0),
            Preference("com.apple.driver.AppleBluetoothMultitouch.trackpad", "TrackpadRightClick", true),
            Preference("com.apple.driver.AppleBluetoothMultitouch.trackpad", "TrackpadCornerSecondaryClick", 0)
        ], restart: nil)),
        SetupTask("appearance-details", "Appearance", "Default icon colors and Liquid Glass", "Use the default icon appearance and the most transparent available glass style.", action: .guide(url: "x-apple.systempreferences:com.apple.Appearance-Settings.extension", app: nil,
                         instructions: appearanceInstructions(macOSMajorVersion:
                             ProcessInfo.processInfo.operatingSystemVersion.majorVersion))),
        SetupTask("desktop-widgets", "Appearance", "Hide desktop widgets", "Disable desktop widgets while preserving Stage Manager widget settings. Log out if widgets have not refreshed.", action: desktopWidgetAction(macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)),
        SetupTask("wallpaper-tools", "Appearance", "Wallpaper color dependencies", "Install Python and ImageMagick for local accent extraction.", dependencies: ["homebrew"], action: .install(packages: ["python", "imagemagick"], cask: false, app: nil)),
        SetupTask("wallpaper-colors", "Appearance", "Match SketchyBar accent to wallpaper", "Extract an accent locally from the current wallpaper and update SketchyBar. Run again after a wallpaper change.", dependencies: ["wallpaper-tools", "sketchybar-profile"], action: .accent),
        SetupTask("wallpaper-watcher", "Appearance", "Automatic wallpaper color updates", "Use the existing WallpaperAccentWatcher.app and its user-level login service. No replacement watcher is installed.", dependencies: ["wallpaper-tools", "sketchybar-start"], action: .wallpaperWatcher),
        SetupTask("wallpaper-access", "Appearance", "WallpaperAccentWatcher permissions and test", "Approve wallpaper access for WallpaperAccentWatcher itself, then verify automatic color changes.", dependencies: ["wallpaper-watcher"], action: .guide(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles", app: nil, instructions: [
            "Change to another static wallpaper and check that the focused SketchyBar workspace changes color after a few seconds.",
            "If the accent does not change, open permission settings below. Add WallpaperAccentWatcher.app from Applications (or your user Applications folder) and enable it when your wallpaper provider needs protected-file access.",
            "Approve the macOS authentication prompt yourself; permission given to Mac Setup does not authorize WallpaperAccentWatcher.",
            "Quit and reopen WallpaperAccentWatcher after approving access. Change the wallpaper again and mark this task complete only after you see the accent update.",
            "Do not run another wallpaper watcher alongside WallpaperAccentWatcher. Permissions are never granted automatically."
        ])),
        SetupTask("startup-login", "Apps", "Start essential apps at login",
                  "Register installed AeroSpace, Karabiner-Elements and Raycast in Open at Login without removing existing items. SketchyBar and the wallpaper accent watcher keep their own background services.",
                  action: .loginItems(names: StartupLoginItems.appNames))
    ]

    /// Apple exposes this switch through System Settings rather than a documented
    /// stable defaults key. Avoid writing speculative preferences system-wide.
    public static func menuBarBackgroundAction(macOSMajorVersion: Int) -> TaskAction {
        guard macOSMajorVersion >= 26 else {
            return .guide(url: nil, app: nil, instructions: [
                "This macOS version already provides a native menu bar background. No extra setting is required."
            ])
        }
        return .guide(url: "x-apple.systempreferences:com.apple.MenuBar-Settings.extension",
                      app: nil, instructions: [
            "Open System Settings > Menu Bar.",
            "Enable Show menu bar background. This adds a native blurred layer when the auto-hidden menu bar is revealed over SketchyBar.",
            "Move the pointer to the top edge to confirm that macOS menu titles are legible. This keeps Liquid Glass and SketchyBar's own design unchanged."
        ])
    }

    public static func appearanceInstructions(macOSMajorVersion: Int) -> [String] {
        var instructions = [
            "Keep dark appearance and use the default icon appearance if that option exists on this Mac."
        ]
        if macOSMajorVersion >= 26 {
            instructions.append("Select Clear Liquid Glass, if available, and keep Reduce Transparency off under Accessibility > Display. Wallpaper and macOS affect the result.")
        } else {
            instructions.append("Liquid Glass is only available on macOS 26 or newer. Do not search for that setting on this Mac; simply verify the available dark appearance options.")
        }
        return instructions
    }

    public static func desktopWidgetAction(macOSMajorVersion: Int) -> TaskAction {
        if macOSMajorVersion >= 14 {
            return .preferences([Preference("com.apple.WindowManager", "StandardHideWidgets", true)], restart: nil)
        }
        return .guide(url: nil, app: nil, instructions: ["Desktop widgets require macOS 14 or newer; this setting is unavailable on this Mac."])
    }

    public static func task(_ id: String) throws -> SetupTask {
        guard let task = tasks.first(where: { $0.id == id }) else { throw SetupError("Unknown task '\(id)'. Run mac-setup list.") }
        return task
    }

    public static func ordered(_ ids: [String], includingDependencies: Bool = true) throws -> [SetupTask] {
        let requested = Set(ids)
        var result: [SetupTask] = []; var visiting = Set<String>(); var visited = Set<String>()
        func visit(_ id: String) throws {
            if visited.contains(id) { return }
            guard visiting.insert(id).inserted else { throw SetupError("Task dependency cycle: \(id)") }
            let item = try task(id)
            for dependency in item.dependencies where includingDependencies || requested.contains(dependency) { try visit(dependency) }
            visiting.remove(id); visited.insert(id); result.append(item)
        }
        for id in ids { try visit(id) }
        return result
    }
}
