import Foundation
import AppKit

public enum TaskState: String { case ready = "Ready", done = "Verified", guided = "Guided", confirmed = "User confirmed", blocked = "Needs prerequisite" }

public final class Engine {
    public let paths: Paths
    public let runner: CommandRunning
    public let journal: Journal
    public let dotfiles: LinkedDotfiles
    /// Optional task choices captured from the setup checklist. A nil value
    /// retains all saved workspaces for standalone profile reapplication.
    public var selectedWorkspaceTaskIDs: Set<String>?
    public var deferRestarts = false
    /// Tunable for headless integration tests and slower desktop reloads.
    public var workspaceVerificationAttempts = 10
    public var workspaceVerificationRetryDelay: TimeInterval = 0.2
    public private(set) var pendingRestarts = Set<String>()
    private let displayHelper: URL?
    private var brewRefreshed = false
    private let tools: (String) -> String?

    public init(paths: Paths = Paths(), runner: CommandRunning = ProcessRunner(), dotfilesSource: DotfilesSource? = nil, displayHelper: URL? = AppResources.displayHelperURL, tools: @escaping (String) -> String? = executable) throws {
        self.paths = paths; self.runner = runner; self.tools = tools; self.displayHelper = displayHelper
        let record = try Journal(paths: paths, runner: runner)
        journal = record
        dotfiles = LinkedDotfiles(paths: paths, runner: runner, journal: record, source: dotfilesSource)
    }

    public func state(_ task: SetupTask) throws -> TaskState {
        switch task.action {
        case .homebrew: return tools("brew") != nil ? .done : .ready
        case .finderResetFolderViews:
            return .ready // This opt-in operation always requires an explicit run.
        case .finderIcons:
            let views = try journal.preference("com.apple.finder", "StandardViewSettings") as? [String: Any] ?? [:]
            let grouping = try journal.preference("com.apple.finder", "FXPreferredGroupBy")
            let view = try journal.preference("com.apple.finder", "FXPreferredViewStyle")
            return equalPlist(views, Self.finderListDefaults(views)) && equalPlist(grouping, "None") && equalPlist(view, "Nlsv") ? .done : .ready
        case let .install(packages, cask, app):
            if let app, appPath(app, home: paths.home) != nil { return .done }
            guard let brew = tools("brew") else { return .blocked }
            // A failed cask pkg install can leave a Homebrew registration behind,
            // even though the application itself was never installed.
            if app != nil { return .ready }
            return try packages.allSatisfy { package in
                let result = try runner.run(brew, ["list", cask ? "--cask" : "--formula", "--versions", package])
                return result.status == 0 && !result.text.isEmpty
            } ? .done : .ready
        case let .appStore(app, _):
            return appPath(app, home: paths.home) != nil ? .done : .guided
        case .linkedDotfiles:
            return dotfiles.status()
        case let .profile(directories):
            if directories.contains("aerospace"), Journal.exists(paths.home.appendingPathComponent(".aerospace.toml")) { return .blocked }
            for name in directories {
                let target = paths.config.appendingPathComponent(name)
                let generated = ["aerospace", "sketchybar", "karabiner"].contains(name)
                if dotfiles.isSymlink(target) {
                    if dotfiles.source.isLinked(name, config: paths.config),
                       Journal.exists(dotfiles.source.checkout.appendingPathComponent(name)) {
                        // Managed workspace profiles are local copies, not links into a Git checkout.
                        if generated { return .ready }
                        continue
                    }
                    return .blocked
                }
                if dotfiles.status() == .done && !generated { return .ready }
                if try !profileMatches(name) { return .ready }
            }
            return .done
        case let .preferences(preferences, _):
            if task.id == "raycast-profile" {
                let shortcuts = try shortcutSettings()
                if shortcuts.usesSpotlightKey {
                    if try spotlightSearchEnabled() { return .ready }
                }
                return equalPlist(try journal.preference("com.raycast.macos", "raycastGlobalHotkey"),
                                  shortcuts.raycastHotkey) ? .done : .ready
            }
            return try preferences.allSatisfy { equalPlist(try journal.preference($0.domain, $0.key), $0.value) } ? .done : .ready
        case .vorssaint:
            let stored = try journal.preferences("com.vorssaint.utils")
            return try vorssaintPreferences().allSatisfy {
                equalPreference(stored[$0.key], $0.value)
            } ? .done : .ready
        case .gitIgnore:
            let values = try journal.gitValues("core.excludesfile")
            guard values.count == 1 else { return .ready }
            let target = expandedPath(values[0])
            guard let text = try? String(contentsOf: target, encoding: .utf8) else { return .ready }
            let lines = Set(text.components(separatedBy: "\n"))
            return Self.ignoreRules.allSatisfy(lines.contains) ? .done : .ready
        case .atuinShell:
            let file = shellRC()
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            return hasAtuinInit(text) ? .done : .ready
        case .service:
            guard tools("sketchybar") != nil else { return .blocked }
            return try journal.serviceStarted() ? .done : .ready
        case .wallpaperWatcher:
            if try WallpaperWatcher.isCurrent(engine: self) { return .done }
            return WallpaperWatcher.bundledExecutable(paths: paths) != nil ? .ready : .blocked
        case let .loginItems(names):
            // Inspect only our own journal during initial inventory, never
            // prompt System Events just to draw the feature-selection screen.
            let apps = StartupLoginItems.installedPaths(names: names, home: paths.home)
            guard !apps.isEmpty else { return .ready }
            return journal.transactions.contains { record in
                record.task == task.id && record.complete &&
                apps.allSatisfy { app in
                    record.changes.contains { $0.kind == .loginItem && $0.target == app && !$0.restored }
                }
            } ? .done : .ready
        case .accent: return .ready // A new wallpaper needs a new extraction.
        case .guide:
            if ["aerospace-access", "karabiner-access", "raycast-access"].contains(task.id),
               try !checkGuide(task).ready { return .guided }
            let recorded = journal.transactions.contains { $0.task == task.id && $0.complete && $0.changes.isEmpty }
            return recorded ? .confirmed : .guided
        }
    }

    public func preview(_ task: SetupTask) throws -> [String] {
        var lines = [task.summary]
        switch task.action {
        case .homebrew:
            lines.append("Download https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh to a temporary file, then run the official installer interactively with /bin/bash.")
            lines.append("The installer may request administrator authentication or Command Line Tools approval. mac-setup stays a normal user process.")
            lines.append("Back up and append a managed brew shellenv block to zsh's .zprofile. Installation itself is not undone by restore; shell configuration is.")
        case .finderResetFolderViews:
            lines.append("Opt-in reset for existing Finder per-folder view overrides under user folders. All removed .DS_Store files are backed up for restore.")
            lines.append("Also resets folder icon layout and other per-folder customizations. Hidden paths, packages, symlinks, system and Library folders are excluded.")
        case .finderIcons:
            lines.append("Back up Finder view defaults. Apply list view, no grouping, Date Modified sorting, large icons, text size 13, Date Modified/Size/Kind columns, relative dates and previews. Preserve widths and unrelated settings. Restart Finder; finish active file operations first.")
        case let .install(packages, cask, _):
            lines.append("Homebrew installs: " + packages.joined(separator: ", ") + (cask ? " (casks)" : " (formulae)"))
            lines.append("App installations can request administrator approval. Installed packages are not automatically uninstalled by restore.")
        case let .appStore(app, url):
            lines.append("Install \(app) from the Mac App Store: \(url)")
            lines.append("App Store installation requires user interaction. No Apple ID or purchase is automated.")
        case .linkedDotfiles:
            lines.append("Clone public dot-files into \(dotfiles.source.checkout.path) if it is not there already.")
            lines.append("Only profiles selected later are linked into \(paths.config.path). Existing local folders are backed up.")
            lines.append("Links pointing to a different repository are never changed automatically.")
        case let .profile(directories):
            for name in directories {
                lines.append("Merge bundled files into \(paths.config.appendingPathComponent(name).path). Existing unrelated files are preserved.")
            }
            lines.append("Portable application profiles can be linked from dot-files. AeroSpace, SketchyBar and Karabiner are rendered as local, backed-up copies so personal shortcuts never alter your Git checkout.")
            lines.append("Existing directories are backed up. Unrelated symlinks are never overwritten.")
        case let .preferences(preferences, restart):
            if task.id == "raycast-profile" {
                lines.append("com.raycast.macos / raycastGlobalHotkey: \(try shortcutSettings().raycastHotkey)")
            } else {
                lines += preferences.map { "\($0.domain) / \($0.key) → \($0.value)" }
            }
            if let restart { lines.append("Restart \(restart) after saving preferences. Finish active Finder file operations first.") }
            lines.append("Verification checks stored preferences; confirm the visible result on this macOS version.")
        case .vorssaint:
            lines.append("Merge \(try vorssaintPreferences().count) portable settings into com.vorssaint.utils. Quit Vorssaint first; launch it afterwards.")
            lines.append("The bundled native Vorssaint export is included. Personal snippets, private bookmarks, and device-specific preferences are omitted.")
        case .gitIgnore:
            lines.append("Append missing macOS rules to the currently configured ignore file, or ~/.gitignore_global if none is configured.")
        case .atuinShell: lines.append("Append the managed zsh block to \(shellRC().path). An existing Atuin initialization is preserved.")
        case .service: lines.append("Start or restart the SketchyBar user service. Never run Homebrew as root.")
        case .accent:
            lines.append("Read the current wallpaper locally and write a validated accent into the local cache, without editing tracked dotfiles. No background watcher is installed.")
        case let .loginItems(names):
            let installed = StartupLoginItems.installedPaths(names: names, home: paths.home)
            lines.append("Register installed apps in System Settings > General > Login Items & Extensions > Open at Login, preserving other items.")
            lines += installed.map { "Add at login if missing: \($0)" }
            lines.append("System Events may request macOS Automation approval. SketchyBar starts through Homebrew and the shared wallpaper watcher through its LaunchAgent; no duplicate entries are created for those background jobs.")
        case .wallpaperWatcher:
            lines.append("Use the shared watcher helper packaged with Mac Setup on every Mac.")
            lines.append("Back up and remove the old watcher startup entry, stop it, and register the shared helper with a two-second wallpaper-change check. The old app stays on disk.")
            lines.append("Use watcher-status to check logs, watcher-disable to disable it across logins, and watcher-enable to resume. Restore only undoes changes recorded by mac-setup.")
        case let .guide(url, app, instructions):
            if let app { lines.append("Open \(app).") }
            if let url { lines.append("Open: \(url)") }
            lines += instructions
        }
        return lines
    }

    @discardableResult
    public func apply(_ task: SetupTask, image: URL? = nil) throws -> String {
        guard !task.guided else { throw SetupError("This is a guided task; use the interactive CLI.") }
        let id = try journal.begin(task.id)
        do {
            switch task.action {
            case .homebrew: try installHomebrew(transaction: id)
            case .finderResetFolderViews:
                let roots = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
                    .map { paths.home.appendingPathComponent($0) }
                let files = try FolderViewOverrides.discover(in: roots)
                for file in files { try journal.remove(file, transaction: id) }
                try restart("Finder")
            case .finderIcons:
                var views = try journal.preference("com.apple.finder", "StandardViewSettings") as? [String: Any] ?? [:]
                views = Self.finderListDefaults(views)
                try journal.setPreference("com.apple.finder", "StandardViewSettings", views, transaction: id)
                try journal.setPreference("com.apple.finder", "FXPreferredGroupBy", "None", transaction: id)
                try journal.setPreference("com.apple.finder", "FXPreferredViewStyle", "Nlsv", transaction: id)
                try restart("Finder")
                guard try state(task) == .done else { throw SetupError("Finder icon size verification failed.") }
            case let .install(packages, cask, app):
                guard let brew = tools("brew") else { throw SetupError("Install Homebrew first.") }
                if task.id == "vorssaint" {
                    #if arch(x86_64)
                    throw SetupError("Vorssaint requires Apple silicon.")
                    #endif
                    guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 else { throw SetupError("Vorssaint requires macOS 14 or later.") }
                }
                if app == nil || appPath(app!, home: paths.home) == nil {
                    for package in packages {
                        let installed = try runner.run(brew, ["list", cask ? "--cask" : "--formula", "--versions", package])
                        if installed.status != 0 || installed.text.isEmpty {
                            try runner.checked(brew, ["install"] + (cask ? ["--cask"] : []) + [package], interactive: true)
                        } else if cask, let app, appPath(app, home: paths.home) == nil {
                            // Resume a partially installed cask without disturbing
                            // packages whose installed application is already present.
                            try runner.checked(brew, ["reinstall", "--cask", package], interactive: true)
                        }
                    }
                }
                guard try state(task) == .done else { throw SetupError("Installation could not be verified.") }
            case .appStore: break // App Store installation requires explicit user action.
            case .linkedDotfiles:
                try dotfiles.install(transaction: id)
                guard dotfiles.status() == .done else { throw SetupError("Dotfiles installation could not be verified.") }
            case let .profile(directories):
                for name in directories where dotfiles.isSymlink(paths.config.appendingPathComponent(name)) &&
                    !dotfiles.source.isLinked(name, config: paths.config) {
                    throw SetupError("\(name) uses an unrelated configuration symlink. Resolve it manually.")
                }
                if directories.contains("aerospace"), Journal.exists(paths.home.appendingPathComponent(".aerospace.toml")) {
                    throw SetupError("~/.aerospace.toml exists. AeroSpace refuses ambiguous config locations. Move that file aside yourself, then retry.")
                }
                for name in directories {
                    if dotfiles.status() == .done && !["aerospace", "sketchybar", "karabiner"].contains(name) {
                        try dotfiles.link(name, transaction: id)
                    } else {
                        try installProfile(name, transaction: id)
                    }
                }
                guard try state(task) == .done else { throw SetupError("Profile verification failed.") }
                if directories.contains("sketchybar") {
                    // The running bar is the authority, not Homebrew's service
                    // status. Users can run SketchyBar independently of brew
                    // services. A successful file copy must refresh that bar.
                    if let sketchybar = tools("sketchybar") {
                        let running = try runner.run(sketchybar, ["--query", "bar"])
                        if running.status == 0 {
                            try runner.checked(sketchybar, ["--reload"])
                            // A zero exit code only confirms receipt of the reload request.
                            // Wait for the active bar to expose the new item order.
                            let expected = try WorkspaceConfiguration.load(from: paths).workspaces.map(\.id)
                            var issue: String?
                            let attempts = max(1, workspaceVerificationAttempts)
                            for attempt in 0..<attempts {
                                let query = try runner.run(sketchybar, ["--query", "bar"])
                                issue = query.status == 0
                                    ? WorkspaceRuntimeVerification.sketchyBarOrderIssue(
                                        query: query.output, expectedIDs: expected)
                                    : "SketchyBar did not respond after reload."
                                if issue == nil { break }
                                if attempt + 1 < attempts {
                                    Thread.sleep(forTimeInterval: max(0, workspaceVerificationRetryDelay))
                                }
                            }
                            if let issue { throw SetupError("SketchyBar reload was not verified: \(issue)") }
                        } else if (try? journal.serviceStarted()) == true {
                            throw SetupError("SketchyBar service is registered but its bar is unavailable. Restart SketchyBar and retry.")
                        }
                    }
                }
                if directories.contains("aerospace"), let tool = tools("aerospace") {
                    let running = try runner.run(tool, ["list-workspaces", "--all"])
                    if running.status == 0 { try runner.checked(tool, ["reload-config"]) }
                }
            case let .preferences(preferences, restart):
                if task.id == "raycast-profile" {
                    let shortcuts = try shortcutSettings()
                    try quitForPreferences("com.raycast.macos")
                    if shortcuts.usesSpotlightKey { try releaseSpotlightShortcut(transaction: id) }
                    try journal.setPreference("com.raycast.macos", "raycastGlobalHotkey",
                                              shortcuts.raycastHotkey, transaction: id)
                } else {
                    for preference in preferences {
                        try journal.setPreference(preference.domain, preference.key, preference.value, transaction: id)
                    }
                }
                if let restart { try self.restart(restart) }
            case .vorssaint:
                try quitForPreferences("com.vorssaint.utils")
                for preference in try vorssaintPreferences() { try journal.setPreference(preference.domain, preference.key, preference.value, transaction: id) }
            case .gitIgnore: try applyGitIgnore(transaction: id)
            case .atuinShell: try applyAtuinShell(transaction: id)
            case .service: try journal.startService(transaction: id)
            case .accent: try applyAccent(transaction: id, image: image)
            case .wallpaperWatcher: try installWallpaperWatcher(transaction: id, image: image)
            case let .loginItems(names):
                for path in StartupLoginItems.installedPaths(names: names, home: paths.home) {
                    try journal.registerLoginItem(path, transaction: id)
                }
            case .guide: break
            }
            try journal.finish(id)
            return id
        } catch {
            throw SetupError("\(error)\nRecovery record: \(id). Run mac-setup restore \(id) to undo recorded changes; installed apps remain installed.")
        }
    }

    public static func finderListDefaults(_ original: [String: Any]) -> [String: Any] {
        var views = original
        let existing = ["ListViewSettings", "ExtendedListViewSettingsV2"].filter { views[$0] is [String: Any] }
        let visible: Set<String> = ["name", "dateModified", "size", "kind"]
        let identifiers = ["name", "dateModified", "size", "kind", "dateCreated", "dateLastOpened", "dateAdded", "version", "comments", "label", "ubiquity", "shareOwner", "shareLastEditor", "invitationStatus"]
        for key in existing.isEmpty ? ["ListViewSettings"] : existing {
            var list = views[key] as? [String: Any] ?? [:]
            list["iconSize"] = 32.0; list["textSize"] = 13.0
            list["sortColumn"] = "dateModified"
            list["useRelativeDates"] = true; list["calculateAllSizes"] = false; list["showIconPreview"] = true
            if var columns = list["columns"] as? [[String: Any]] {
                for index in columns.indices {
                    if let identifier = columns[index]["identifier"] as? String {
                        columns[index]["visible"] = visible.contains(identifier)
                        if identifier == "dateModified" { columns[index]["ascending"] = false }
                    }
                }
                for identifier in identifiers where !columns.contains(where: { $0["identifier"] as? String == identifier }) {
                    columns.append(["identifier": identifier, "visible": visible.contains(identifier), "ascending": identifier != "dateModified"])
                }
                list["columns"] = columns
            } else {
                var columns = list["columns"] as? [String: [String: Any]] ?? [:]
                for (index, identifier) in identifiers.enumerated() {
                    var column = columns[identifier] ?? ["index": index]
                    column["visible"] = visible.contains(identifier)
                    if identifier == "dateModified" { column["ascending"] = false }
                    columns[identifier] = column
                }
                for identifier in Array(columns.keys) where !visible.contains(identifier) { columns[identifier]?["visible"] = false }
                list["columns"] = columns
            }
            views[key] = list
        }
        return views
    }

    private func installHomebrew(transaction: String) throws {
        if tools("brew") == nil {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let script = directory.appendingPathComponent("install.sh")
            try runner.checked("/usr/bin/curl", ["--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--tlsv1.2", "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh", "--output", script.path])
            guard !(try Data(contentsOf: script)).isEmpty else { throw SetupError("Homebrew installer download was empty.") }
            try runner.checked("/bin/bash", [script.path], interactive: true)
        }
        guard let brew = tools("brew") else { throw SetupError("Homebrew installation could not be verified. Finish the installer requirements and retry.") }
        let profile: URL
        if let zdot = ProcessInfo.processInfo.environment["ZDOTDIR"], !zdot.isEmpty, paths.home == FileManager.default.homeDirectoryForCurrentUser {
            profile = expandedPath(zdot).appendingPathComponent(".zprofile")
        } else { profile = paths.home.appendingPathComponent(".zprofile") }
        let old = Journal.exists(profile) ? try String(contentsOf: profile, encoding: .utf8) : ""
        if !old.contains("# >>> mac-setup: Homebrew >>>") && !old.contains("brew shellenv") {
            let quoted = "'" + brew.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
            let block = "\n# >>> mac-setup: Homebrew >>>\neval \"$(" + quoted + " shellenv)\"\n# <<< mac-setup: Homebrew <<<\n"
            try journal.write(profile, data: Data((old + block).utf8), transaction: transaction)
        }
    }

    public func upgradePreview(_ task: SetupTask) throws -> [String] {
        guard task.updatable else { throw SetupError("\(task.title) does not support package updates.") }
        if task.id == "homebrew" { return ["Update Homebrew: brew update", "Refresh Homebrew itself and package metadata. Installed packages are not all upgraded."] }
        guard case let .install(packages, cask, _) = task.action else { throw SetupError("Not a package task.") }
        return ["Update \(task.title): brew upgrade \(cask ? "--cask" : "--formula") \(packages.joined(separator: " "))", "Only these packages are requested. Homebrew can update their required dependencies. Package updates cannot be rolled back by mac-setup restore."]
    }

    @discardableResult
    public func upgrade(_ task: SetupTask) throws -> String {
        _ = try upgradePreview(task)
        guard let brew = tools("brew") else { throw SetupError("Install Homebrew before updating packages.") }
        if case let .install(packages, cask, _) = task.action {
            for package in packages {
                let result = try runner.run(brew, ["list", cask ? "--cask" : "--formula", "--versions", package])
                guard result.status == 0 && !result.text.isEmpty else {
                    throw SetupError("\(package) is not managed by Homebrew. Use the app's own updater or select its installation separately.")
                }
            }
        }
        let id = try journal.begin("upgrade:" + task.id)
        if !brewRefreshed || task.id == "homebrew" {
            try runner.checked(brew, ["update"], interactive: true)
            brewRefreshed = true
        }
        if case let .install(packages, cask, _) = task.action {
            try runner.checked(brew, ["upgrade", cask ? "--cask" : "--formula"] + packages, interactive: true)
        }
        try journal.finish(id)
        return id
    }

    public func confirm(_ task: SetupTask) throws {
        guard task.guided else { throw SetupError("Only guided tasks can be confirmed manually.") }
        let check = try checkGuide(task)
        guard check.ready else { throw SetupError(check.message) }
        let id = try journal.begin(task.id); try journal.finish(id)
    }

    public func openGuide(_ task: SetupTask) throws {
        if case let .appStore(_, url) = task.action {
            try runner.checked("/usr/bin/open", [url]); return
        }
        guard case let .guide(url, app, _) = task.action else { return }
        if let app {
            try runner.checked("/usr/bin/open", ["-a", app])
            if task.id == "karabiner-access" {
                let cli = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
                if FileManager.default.isExecutableFile(atPath: cli) {
                    try runner.checked(cli, ["--select-profile", "Portable"])
                }
            }
            return
        }
        if let url {
            let result = try runner.run("/usr/bin/open", [url])
            if result.status != 0, url.hasPrefix("x-apple.systempreferences:") {
                try runner.checked("/usr/bin/open", ["-a", "System Settings"])
            } else if result.status != 0 { throw SetupError("Could not open \(url).") }
        }
    }

    private func quitForPreferences(_ bundleID: String) throws {
        // A temporary test home must never affect apps in the real session.
        guard paths.home == FileManager.default.homeDirectoryForCurrentUser else { return }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in apps { app.terminate() }
        for _ in 0..<30 {
            if apps.allSatisfy(\.isTerminated) { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw SetupError("Quit \(bundleID) so its saved settings can be updated, then retry.")
    }

    private func restart(_ process: String) throws {
        if deferRestarts { pendingRestarts.insert(process); return }
        let result = try runner.run("/usr/bin/killall", [process])
        guard result.status == 0 || result.text.contains("No matching processes") else {
            throw SetupError("Could not refresh \(process): \(result.text)")
        }
    }

    public func finishRestarts() throws {
        for process in pendingRestarts.sorted() {
            let result = try runner.run("/usr/bin/killall", [process])
            guard result.status == 0 || result.text.contains("No matching processes") else {
                throw SetupError("Could not refresh \(process): \(result.text)")
            }
            pendingRestarts.remove(process)
        }
    }

    /// Inspect the currently running applications, not just the generated files.
    /// An unavailable app or stale bar stays visible as a verification issue.
    public func workspaceRuntimeIssues(checkAeroSpace: Bool, checkSketchyBar: Bool) -> [String] {
        guard checkAeroSpace || checkSketchyBar else { return [] }
        let layout: WorkspaceConfiguration
        do { layout = try WorkspaceConfiguration.load(from: paths) }
        catch { return ["Unable to read saved workspaces: \(error)"] }

        let expected = layout.workspaces.map(\.id)
        var issues: [String] = []
        if checkAeroSpace {
            if let aerospace = tools("aerospace") {
                do {
                    let config = try runner.run(aerospace, ["config", "--config-path"])
                    let expectedPath = paths.config.appendingPathComponent("aerospace/aerospace.toml")
                        .standardizedFileURL.path
                    let actualPath = config.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if config.status != 0 || URL(fileURLWithPath: actualPath).standardizedFileURL.path != expectedPath {
                        issues.append("AeroSpace is not using the managed configuration at \(expectedPath). Active path: \(actualPath.isEmpty ? "unknown" : actualPath).")
                    }
                    let active = try runner.run(aerospace, ["list-workspaces", "--all"])
                    if active.status != 0 {
                        issues.append("AeroSpace did not respond to a live workspace query.")
                    } else {
                        let missing = WorkspaceRuntimeVerification.missingAeroSpaceIDs(
                            output: active.text, expectedIDs: expected)
                        if !missing.isEmpty {
                            issues.append("AeroSpace is missing configured workspaces: "
                                + missing.joined(separator: ", "))
                        }
                    }
                } catch { issues.append("Unable to verify running AeroSpace: \(error)") }
            } else {
                issues.append("AeroSpace is not installed or its command is unavailable; its live configuration was not verified.")
            }
        }
        if checkSketchyBar {
            if let sketchybar = tools("sketchybar") {
                do {
                    let running = try runner.run(sketchybar, ["--query", "bar"])
                    if running.status != 0 {
                        issues.append("SketchyBar is not responding; configuration files were written but the running bar could not be verified.")
                    } else if let issue = WorkspaceRuntimeVerification.sketchyBarOrderIssue(
                        query: running.output, expectedIDs: expected) {
                        issues.append(issue)
                    }
                } catch { issues.append("Unable to verify running SketchyBar: \(error)") }
            } else {
                issues.append("SketchyBar is not installed or its command is unavailable; its live workspace order was not verified.")
            }
        }
        return issues
    }

    public func updateTasks() -> [String] {
        Catalog.tasks.filter { task in
            let isProfile: Bool
            switch task.action { case .profile, .vorssaint: isProfile = true; default: isProfile = false }
            return isProfile && journal.transactions.contains {
                $0.task == task.id && $0.complete && $0.changes.contains(where: { !$0.restored })
            }
        }.map(\.id)
    }

    private func bundledFiles(_ name: String) throws -> [URL] {
        let root = paths.profile.appendingPathComponent(name)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { throw SetupError("Missing bundled profile: \(name)") }
        return try enumerator.compactMap { $0 as? URL }.filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
    }

    private func profileMatches(_ name: String) throws -> Bool {
        let root = paths.profile.appendingPathComponent(name)
        let files = try bundledFiles(name)
        guard !files.isEmpty else { return false }
        if name == "sketchybar" {
            guard let displayHelper,
                  let actual = try? Data(contentsOf: paths.config.appendingPathComponent("sketchybar/plugins/mac-setup-display")),
                  actual == (try Data(contentsOf: displayHelper)) else { return false }
        }
        return try files.allSatisfy { file in
            let relative = String(file.path.dropFirst(root.path.count + 1))
            let target = paths.config.appendingPathComponent(name).appendingPathComponent(relative)
            guard let actual = try? Data(contentsOf: target) else { return false }
            if name == "aerospace", relative == "aerospace.toml" {
                return DisplayGeometry.stableConfiguration(actual) == DisplayGeometry.stableConfiguration(try materialized(file))
            }
            if relative == "plugins/colors.sh" { return String(decoding: actual, as: UTF8.self).contains("HIGHLIGHT_COLOR=") }
            return actual == (try materialized(file))
        }
    }

    private func shortcutSettings() throws -> ShortcutSettings {
        let template = try String(contentsOf: paths.profile.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
        return try ShortcutSettings.load(from: paths, aerospaceTemplate: template)
    }

    private func materialized(_ file: URL) throws -> Data {
        let original = try String(contentsOf: file, encoding: .utf8)
        if file.lastPathComponent == "karabiner.json",
           file.deletingLastPathComponent().lastPathComponent == "karabiner" {
            return try shortcutSettings().karabinerData(from: Data(original.utf8))
        }
        if file.lastPathComponent == "colors.sh",
           file.deletingLastPathComponent().lastPathComponent == "plugins",
           file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "sketchybar" {
            let style = try WorkspaceConfiguration.load(from: paths).barStyle
            return Data(try style.colorsShell(from: original).utf8)
        }
        // Render user-specific workspace settings without writing into public dotfiles.
        if file.lastPathComponent == "aerospace.toml",
           file.deletingLastPathComponent().lastPathComponent == "aerospace" {
            return Data(try WorkspaceConfiguration.load(from: paths)
                .forSelectedTasks(selectedWorkspaceTaskIDs,
                                  installedBundleIDs: Set(ApplicationDiscovery.scan(home: paths.home).map(\.bundleID)))
                .aerospaceTOML(from: try shortcutSettings().aerospaceTemplateApplying(to: original)).utf8)
        }
        if file.lastPathComponent == "sketchybarrc",
           file.deletingLastPathComponent().lastPathComponent == "sketchybar" {
            return Data(try WorkspaceConfiguration.load(from: paths)
                .forSelectedTasks(selectedWorkspaceTaskIDs,
                                  installedBundleIDs: Set(ApplicationDiscovery.scan(home: paths.home).map(\.bundleID)))
                .sketchybarShell(from: original).utf8)
        }
        if file.lastPathComponent == "geometry.sh" {
            let quoted = "'" + paths.config.appendingPathComponent("aerospace/aerospace.toml").path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
            return Data(original.replacingOccurrences(of: "AEROSPACE_CONFIG=auto", with: "AEROSPACE_CONFIG=" + quoted).utf8)
        }
        // Alacritty's import path is resolved against the recipient's configuration directory.
        if file.lastPathComponent == "alacritty.toml" {
            let importPath = paths.config.appendingPathComponent("alacritty/themes/themes/github_dark.toml").path
            let escaped = importPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return Data(original.replacingOccurrences(of: "~/.config/alacritty/themes/themes/github_dark.toml", with: escaped).utf8)
        }
        return Data(original.utf8)
    }

    private func installProfile(_ name: String, transaction: String) throws {
        guard !name.contains("/") && name != ".." else { throw SetupError("Invalid profile directory.") }
        let root = paths.profile.appendingPathComponent(name)
        let target = paths.config.appendingPathComponent(name)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        if FileManager.default.fileExists(atPath: target.path) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw SetupError("Config path is not a directory: \(target.path)") }
            try FileManager.default.copyItem(at: target.resolvingSymlinksInPath(), to: staging)
        } else { try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true) }
        for file in try bundledFiles(name) {
            let relative = String(file.path.dropFirst(root.path.count + 1))
            let output = staging.appendingPathComponent(relative)
            // Detach any copied parent symlink before writing into the staging tree.
            var parent = output.deletingLastPathComponent()
            var parents: [URL] = []
            while parent.path != staging.path { parents.append(parent); parent.deleteLastPathComponent() }
            for parent in parents.reversed() {
                if (try? FileManager.default.attributesOfItem(atPath: parent.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                    let resolved = parent.resolvingSymlinksInPath()
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.copyItem(at: resolved, to: copy)
                    try FileManager.default.removeItem(at: parent)
                    try FileManager.default.moveItem(at: copy, to: parent)
                }
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            if Journal.exists(output) { try FileManager.default.removeItem(at: output) }
            try materialized(file).write(to: output)
            let mode = file.pathExtension == "sh" || file.pathExtension == "py" || file.lastPathComponent == "sketchybarrc" ? 0o755 : 0o644
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: output.path)
        }
        if name == "sketchybar" {
            guard let displayHelper else { throw SetupError("This build is missing mac-setup-display. Rebuild or download the complete app package.") }
            let output = staging.appendingPathComponent("plugins/mac-setup-display")
            if Journal.exists(output) { try FileManager.default.removeItem(at: output) }
            try FileManager.default.copyItem(at: displayHelper, to: output)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: output.path)
        }
        try journal.replace(target, with: staging, transaction: transaction)
    }

    public func vorssaintPreferences() throws -> [Preference] {
        let data = try Data(contentsOf: paths.profile.appendingPathComponent("vorssaint/preferences.plist"))
        guard let backup = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw SetupError("Invalid Vorssaint profile.")
        }
        // Native exports store settings in a nested dictionary. Older flat
        // snapshots remain supported for existing installations.
        let values = backup["settings"] as? [String: Any] ?? backup
        guard values["autoQuitEnabled"] != nil, values["launchAtLoginWanted"] != nil else {
            throw SetupError("The bundled Vorssaint export is incomplete.")
        }
        return values.keys.sorted().map { Preference("com.vorssaint.utils", $0, values[$0]!) }
    }

    public static let ignoreRules = [".DS_Store", ".AppleDouble", ".LSOverride", "Icon\r", "._*", ".Spotlight-V100", ".Trashes", ".fseventsd", ".TemporaryItems", ".DocumentRevisions-V100", ".VolumeIcon.icns", ".com.apple.timemachine.donotpresent"]

    private func expandedPath(_ path: String) -> URL {
        if path == "~" { return paths.home }
        if path.hasPrefix("~/") { return paths.home.appendingPathComponent(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path)
    }

    private func applyGitIgnore(transaction: String) throws {
        let current = try journal.gitValues("core.excludesfile")
        guard current.count <= 1 else { throw SetupError("Multiple global core.excludesfile values exist. Resolve the ambiguity first.") }
        if let path = current.first, !path.hasPrefix("/") && !path.hasPrefix("~/") {
            throw SetupError("The global Git ignore path is relative. Set an explicit absolute path before applying this task.")
        }
        let target = current.first.map(expandedPath) ?? paths.home.appendingPathComponent(".gitignore_global")
        let old: String
        if Journal.exists(target) { old = try String(contentsOf: target, encoding: .utf8) } else { old = "" }
        let lines = Set(old.components(separatedBy: "\n"))
        let missing = Self.ignoreRules.filter { !lines.contains($0) }
        if !missing.isEmpty {
            let updated = old + (old.isEmpty || old.hasSuffix("\n") ? "" : "\n") + "\n# mac-setup: macOS files\n" + missing.joined(separator: "\n") + "\n"
            try journal.write(target, data: Data(updated.utf8), transaction: transaction)
        }
        if current.isEmpty { try journal.setGit("core.excludesfile", target.path, transaction: transaction) }
    }

    public func shellRC() -> URL {
        if let zdot = ProcessInfo.processInfo.environment["ZDOTDIR"], !zdot.isEmpty, paths.home == FileManager.default.homeDirectoryForCurrentUser { return expandedPath(zdot).appendingPathComponent(".zshrc") }
        return paths.home.appendingPathComponent(".zshrc")
    }

    private func applyAtuinShell(transaction: String) throws {
        let target = shellRC()
        let old = Journal.exists(target) ? try String(contentsOf: target, encoding: .utf8) : ""
        if hasAtuinInit(old) { return }
        let block = "\n# >>> mac-setup: atuin >>>\nif command -v atuin >/dev/null 2>&1; then\n  eval \"$(atuin init zsh)\"\nfi\n# <<< mac-setup: atuin <<<\n"
        try journal.write(target, data: Data((old + (old.isEmpty || old.hasSuffix("\n") ? "" : "\n") + block).utf8), transaction: transaction)
    }

    private func hasAtuinInit(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.hasPrefix("#") && line.contains("atuin init zsh")
        }
    }

    private func wallpaperAccentData(image: URL?) throws -> (URL, Data) {
        guard let python = tools("python3"), tools("magick") != nil else { throw SetupError("Install wallpaper-tools first.") }
        let wallpaper: URL
        if let image { wallpaper = image }
        else {
            guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { throw SetupError("Current wallpaper is unavailable. Supply --image with an accessible image file.") }
            wallpaper = url
        }
        let bytes: Data
        do { bytes = try Data(contentsOf: wallpaper) }
        catch { throw SetupError("Cannot read the wallpaper. Use --image with a local copy you can access. No privacy permissions are changed automatically.") }
        let extractor = paths.profile.appendingPathComponent("unsplash/get_wallpaper_accent.py").path
        // Huge compressed wallpapers need a larger, but still bounded, budget.
        // Ordinary setup commands retain their existing timeout.
        let result: CommandResult
        do {
            result = try runner.runTimed(python, [extractor, "-"], timeout: 120, input: bytes)
        } catch {
            throw SetupError("Wallpaper accent extraction could not finish within its bounded processing window. \(error)")
        }
        guard result.status == 0 else {
            throw SetupError("Wallpaper accent extraction failed (exit \(result.status)): \(result.text). Check ImageMagick and the wallpaper file, then retry.")
        }
        let color = result.text
        guard color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { throw SetupError("Accent extractor returned an invalid color.") }
        let envCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
        let cacheRoot = envCache.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? paths.home.appendingPathComponent(".cache")
        let target = cacheRoot.appendingPathComponent("sketchybar/highlight-color")
        let value = "0xff" + String(color.dropFirst()) + "\n"
        return (target, Data(value.utf8))
    }

    private func notifyWallpaperAccentChange() throws {
        if let sketchybar = tools("sketchybar"), let aerospace = tools("aerospace") {
            let focused = try runner.run(aerospace, ["list-workspaces", "--focused"])
            if focused.status == 0 && !focused.text.isEmpty {
                try runner.checked(sketchybar, ["--trigger", "aerospace_workspace_change", "FOCUSED_WORKSPACE=" + focused.text])
            }
        }
    }
    private func applyAccent(transaction: String, image: URL?) throws {
        let (target, data) = try wallpaperAccentData(image: image)
        try journal.write(target, data: data, transaction: transaction)
        try notifyWallpaperAccentChange()
    }

    /// Runtime updates are derived cache files, not setup preferences. Avoid
    /// creating a backup transaction for every wallpaper transition.
    @discardableResult
    public func refreshWallpaperAccent(image: URL?) throws -> Bool {
        let (target, data) = try wallpaperAccentData(image: image)
        if (try? Data(contentsOf: target)) == data { return false }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        try notifyWallpaperAccentChange()
        return true
    }

    private func installWallpaperWatcher(transaction: String, image: URL?) throws {
        // Resolve the replacement before touching a working legacy service.
        let chosen = try WallpaperWatcher.source(paths: paths)
        let legacyPlist = paths.home.appendingPathComponent("Library/LaunchAgents/\(WallpaperWatcher.label).plist")
        let legacyLoaded = try journal.launchAgentLoaded(WallpaperWatcher.label)
        guard !legacyLoaded || Journal.exists(legacyPlist) else {
            throw SetupError("The old watcher is running without its startup plist. Stop it before migration so its configuration can be restored safely.")
        }
        // Older personal profiles read only the static export. Add the same
        // validated cache loader as the portable profile, without replacing
        // the palette. Follow config links just as the old watcher did; the
        // actual file is journaled so restoring also restores linked profiles.
        let colors = paths.config.appendingPathComponent("sketchybar/plugins/colors.sh").resolvingSymlinksInPath()
        var cacheUpdate: Data?
        if Journal.exists(colors) {
            let existing = try String(contentsOf: colors, encoding: .utf8)
            if !existing.contains("sketchybar/highlight-color") {
                let profile = try String(contentsOf: paths.profile.appendingPathComponent("sketchybar/plugins/colors.sh"), encoding: .utf8)
                guard let loader = profile.range(of: "# Match the source dotfiles palette and accept the current wallpaper accent.") else {
                    throw SetupError("The packaged wallpaper accent cache loader is missing. Reinstall Mac Setup.")
                }
                cacheUpdate = Data((existing + "\n" + profile[loader.lowerBound...]).utf8)
            }
        }
        // Retain an intentionally pinned image when restarting or migrating.
        let currentPlist = paths.home.appendingPathComponent("Library/LaunchAgents/\(chosen.label).plist")
        let previousPlist = Journal.exists(legacyPlist) ? legacyPlist : currentPlist
        let previous = (try? Data(contentsOf: previousPlist))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let environment = previous?["EnvironmentVariables"] as? [String: String]
        let selectedImage = image ?? environment?["WALLPAPER_ACCENT_IMAGE"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        if Journal.exists(legacyPlist) || legacyLoaded {
            try journal.suspendLaunchAgent(WallpaperWatcher.label, plist: legacyPlist,
                                          transaction: transaction, reload: false)
            try journal.remove(legacyPlist, transaction: transaction)
        }

        if let cacheUpdate { try journal.write(colors, data: cacheUpdate, transaction: transaction) }
        let extractor = paths.config.appendingPathComponent("unsplash/get_wallpaper_accent.py")
        if !Journal.exists(extractor) {
            try journal.write(extractor,
                              data: Data(contentsOf: paths.profile.appendingPathComponent("unsplash/get_wallpaper_accent.py")),
                              transaction: transaction)
        }
        let plist = paths.home.appendingPathComponent("Library/LaunchAgents/\(chosen.label).plist")
        let proposed = try WallpaperWatcher.launchPlist(source: chosen, paths: paths, image: selectedImage)
        try journal.suspendLaunchAgent(chosen.label, plist: plist, transaction: transaction)

        // A stale service might still refer to a deleted app. Preserve its
        // original plist in the recovery journal before making a repair.
        let needsUpdate = try !Journal.exists(plist) || Data(contentsOf: plist) != proposed
        if needsUpdate {
            try journal.write(plist, data: proposed, transaction: transaction)
        }
        try runner.checked("/bin/launchctl", ["enable", "gui/\(getuid())/\(chosen.label)"])
        try journal.loadLaunchAgent(plist)
        guard try journal.launchAgentLoaded(chosen.label) else {
            throw SetupError("Wallpaper watcher registration could not be verified. Inspect mac-setup watcher-status.")
        }
    }
}
