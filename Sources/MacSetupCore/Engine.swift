import Foundation
import AppKit

public enum TaskState: String { case ready = "Ready", done = "Verified", guided = "Guided", confirmed = "User confirmed", blocked = "Needs prerequisite" }

public final class Engine {
    public let paths: Paths
    public let runner: CommandRunning
    public let journal: Journal
    private let runtimeSource: URL?
    private let resolveTool: (String) -> String?

    public init(paths: Paths = Paths(), runner: CommandRunning = ProcessRunner(), runtimeSource: URL? = nil, tools: @escaping (String) -> String? = executable) throws {
        self.paths = paths; self.runner = runner
        journal = try Journal(paths: paths, runner: runner)
        self.runtimeSource = runtimeSource ?? Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        resolveTool = tools
    }

    public func state(_ task: SetupTask) throws -> TaskState {
        switch task.action {
        case let .install(packages, cask, app):
            if let app, appPath(app, home: paths.home) != nil { return .done }
            guard let brew = resolveTool("brew") else { return .blocked }
            return try packages.allSatisfy { package in
                let result = try runner.run(brew, ["list", cask ? "--cask" : "--formula", "--versions", package])
                return result.status == 0 && !result.text.isEmpty
            } ? .done : .ready
        case let .profile(directories):
            if directories.contains("aerospace"), Journal.exists(paths.home.appendingPathComponent(".aerospace.toml")) { return .blocked }
            return try directories.allSatisfy { try profileMatches($0) } ? .done : .ready
        case let .preferences(preferences, _):
            return try preferences.allSatisfy { equalPlist(try journal.preference($0.domain, $0.key), $0.value) } ? .done : .ready
        case .vorssaint:
            let values = try journal.preferences("com.vorssaint.utils")
            return try vorssaintPreferences().allSatisfy { equalPlist(values[$0.key], $0.value) } ? .done : .ready
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
            guard resolveTool("sketchybar") != nil else { return .blocked }
            return try journal.serviceStarted() ? .done : .ready
        case .accent: return .ready // A new wallpaper needs a new extraction.
        case .wallpaperWatcher:
            guard try journal.launchAgentLoaded(WallpaperWatcher.label), let runtimeSource else { return .ready }
            let runtime = paths.state.appendingPathComponent("watcher-runtime")
            for name in ["mac-setup", "MacSetup_MacSetupCore.bundle"] {
                let actual = try Journal.fingerprint(runtime.appendingPathComponent(name))
                let expected = try Journal.fingerprint(runtimeSource.appendingPathComponent(name))
                if actual == nil || actual != expected { return .ready }
            }
            return .done
        case .finderIcons:
            let values = try journal.preference("com.apple.finder", "StandardViewSettings") as? [String: Any]
            let list = values?["ListViewSettings"] as? [String: Any]
            return equalPlist(list?["iconSize"], 32.0) ? .done : .ready
        case .guide:
            if task.id == "homebrew" { return resolveTool("brew") != nil ? .done : .guided }
            let recorded = journal.transactions.contains { $0.task == task.id && $0.complete && $0.changes.isEmpty }
            return recorded ? .confirmed : .guided
        }
    }

    public func preview(_ task: SetupTask) throws -> [String] {
        var lines = [task.summary]
        switch task.action {
        case let .install(packages, cask, _):
            lines.append("Homebrew installs: " + packages.joined(separator: ", ") + (cask ? " (casks)" : " (formulae)"))
            lines.append("App installations can request administrator approval. Installed packages are not automatically uninstalled by restore.")
        case let .profile(directories):
            for name in directories {
                lines.append("Merge bundled files into \(paths.config.appendingPathComponent(name).path). Existing unrelated files are preserved.")
            }
            lines.append("Existing folder contents or symlinks are backed up. Linked personal repositories are detached, not edited.")
        case let .preferences(preferences, restart):
            lines += preferences.map { "\($0.domain) / \($0.key) → \($0.value)" }
            if let restart { lines.append("Restart \(restart) after saving preferences. Finish active Finder file operations first.") }
            lines.append("Verification checks stored preferences; confirm the visible result on this macOS version.")
        case .vorssaint:
            lines.append("Merge \(try vorssaintPreferences().count) portable settings into com.vorssaint.utils. Quit Vorssaint first; launch it afterwards.")
            lines.append("The native 3.4.1 export includes default values and quit-on-close exceptions. No snippets, bookmarks, device IDs, private presets or account data are included.")
        case .gitIgnore:
            lines.append("Append missing macOS rules to the currently configured ignore file, or ~/.gitignore_global if none is configured.")
        case .atuinShell: lines.append("Append the managed zsh block to \(shellRC().path). An existing Atuin initialization is preserved.")
        case .service: lines.append("Start or restart the SketchyBar user service. Never run Homebrew as root.")
        case .accent:
            lines.append("Read the current wallpaper locally; run Python + ImageMagick; save the accent in SketchyBar's colors.sh. No background watcher is installed.")
        case .wallpaperWatcher:
            lines.append("Copy the executable and resource bundle to \(paths.state.appendingPathComponent("watcher-runtime").path). Register \(WallpaperWatcher.label) for this user only.")
            lines.append("Stop the old WallpaperAccentWatcher first if it is running. Restore unregisters this watcher and restores its previous runtime/plist; the last derived accent stays until changed or restored separately.")
            lines.append("Registration is verified separately from wallpaper access. Use watcher-status and the wallpaper-access guided task to test the visible result.")
        case .finderIcons:
            lines.append("Change only StandardViewSettings > ListViewSettings > iconSize to 32. Preserve columns, sorting, text size and other view defaults. Restart Finder; finish active file operations first.")
            lines.append("This preference layout matches the source Mac. Use finder-view-check to verify behavior on the recipient's macOS version.")
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
            case let .install(packages, cask, app):
                guard let brew = resolveTool("brew") else { throw SetupError("Install Homebrew using its guided task first.") }
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
                        }
                    }
                }
                guard try state(task) == .done else { throw SetupError("Installation could not be verified.") }
            case let .profile(directories):
                if directories.contains("aerospace"), Journal.exists(paths.home.appendingPathComponent(".aerospace.toml")) {
                    throw SetupError("~/.aerospace.toml exists. AeroSpace refuses ambiguous config locations. Move that file aside yourself, then retry.")
                }
                for name in directories { try installProfile(name, transaction: id) }
                guard try state(task) == .done else { throw SetupError("Profile verification failed.") }
                if directories.contains("aerospace"), let tool = resolveTool("aerospace") {
                    let running = try runner.run(tool, ["list-workspaces", "--all"])
                    if running.status == 0 { try runner.checked(tool, ["reload-config"]) }
                }
            case let .preferences(preferences, restart):
                for preference in preferences { try journal.setPreference(preference.domain, preference.key, preference.value, transaction: id) }
                if let restart { try runner.checked("/usr/bin/killall", [restart]) }
            case .vorssaint:
                if try runner.run("/usr/bin/pgrep", ["-x", "Vorssaint"]).status == 0 {
                    throw SetupError("Quit Vorssaint from its menu before applying the profile, then retry. Its private contents will remain local.")
                }
                try journal.setPreferences(vorssaintPreferences(), transaction: id)
            case .gitIgnore: try applyGitIgnore(transaction: id)
            case .atuinShell: try applyAtuinShell(transaction: id)
            case .service: try journal.startService(transaction: id)
            case .accent: try applyAccent(transaction: id, image: image)
            case .wallpaperWatcher: try installWallpaperWatcher(transaction: id, image: image)
            case .finderIcons:
                let existing = try journal.preference("com.apple.finder", "StandardViewSettings")
                guard existing == nil || existing is [String: Any] else { throw SetupError("Unrecognized Finder View Options schema; use the guided View Options UI.") }
                var values = existing as? [String: Any] ?? [:]
                guard values["ListViewSettings"] == nil || values["ListViewSettings"] is [String: Any] else { throw SetupError("Unrecognized Finder list-view schema; use View Options in Finder.") }
                var list = values["ListViewSettings"] as? [String: Any] ?? [:]
                list["iconSize"] = 32.0; values["ListViewSettings"] = list
                try journal.setPreference("com.apple.finder", "StandardViewSettings", values, transaction: id)
                try runner.checked("/usr/bin/killall", ["Finder"])
            case .guide: break
            }
            try journal.finish(id)
            return id
        } catch {
            throw SetupError("\(error)\nRecovery record: \(id). Run mac-setup restore \(id) to undo recorded changes; installed apps remain installed.")
        }
    }

    public func confirm(_ task: SetupTask) throws {
        guard task.guided else { throw SetupError("Only guided tasks can be confirmed manually.") }
        let id = try journal.begin(task.id); try journal.finish(id)
    }

    public func openGuide(_ task: SetupTask) throws {
        guard case let .guide(url, app, _) = task.action else { return }
        if let app { try runner.checked("/usr/bin/open", ["-a", app]) }
        if let url {
            let result = try runner.run("/usr/bin/open", [url])
            if result.status != 0, url.hasPrefix("x-apple.systempreferences:") {
                try runner.checked("/usr/bin/open", ["-a", "System Settings"])
            } else if result.status != 0 { throw SetupError("Could not open \(url).") }
        }
    }

    public func updateTasks() -> [String] {
        Catalog.tasks.filter { task in
            let isProfile: Bool
            switch task.action { case .profile, .vorssaint, .wallpaperWatcher: isProfile = true; default: isProfile = false }
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
        let targetRoot = paths.config.appendingPathComponent(name)
        if (try? FileManager.default.attributesOfItem(atPath: targetRoot.path)[.type] as? FileAttributeType) == .typeSymbolicLink { return false }
        let root = paths.profile.appendingPathComponent(name)
        let files = try bundledFiles(name)
        guard !files.isEmpty else { return false }
        return try files.allSatisfy { file in
            let relative = String(file.path.dropFirst(root.path.count + 1))
            let target = paths.config.appendingPathComponent(name).appendingPathComponent(relative)
            guard let actual = try? Data(contentsOf: target) else { return false }
            if relative == "plugins/colors.sh" { return String(decoding: actual, as: UTF8.self).contains("HIGHLIGHT_COLOR=") }
            return actual == (try materialized(file))
        }
    }

    private func materialized(_ file: URL) throws -> Data {
        let original = try String(contentsOf: file, encoding: .utf8)
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
        try journal.replace(target, with: staging, transaction: transaction)
    }

    public func vorssaintPreferences() throws -> [Preference] {
        let data = try Data(contentsOf: paths.profile.appendingPathComponent("vorssaint/preferences.plist"))
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw SetupError("Invalid Vorssaint profile.") }
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

    private func applyAccent(transaction: String, image: URL?) throws {
        try refreshAccent(image: image, transaction: transaction)
    }

    public func refreshAccent(image: URL? = nil, transaction: String? = nil) throws {
        guard let python = resolveTool("python3"), resolveTool("magick") != nil else { throw SetupError("Install wallpaper-tools first.") }
        let wallpaper: URL
        if let image { wallpaper = image }
        else {
            guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { throw SetupError("Current wallpaper is unavailable. Supply --image with an accessible image file.") }
            wallpaper = url
        }
        let bytes: Data
        do { bytes = try Data(contentsOf: wallpaper) }
        catch { throw SetupError("Cannot read the wallpaper. Use --image with a local copy you can access. No privacy permissions are changed automatically.") }
        let result = try runner.checked(python, [paths.profile.appendingPathComponent("unsplash/get_wallpaper_accent.py").path, "-"], input: bytes)
        let color = result.text
        guard color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { throw SetupError("Accent extractor returned an invalid color.") }
        let target = paths.config.appendingPathComponent("sketchybar/plugins/colors.sh")
        let old = try String(contentsOf: target, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: "(?m)^export HIGHLIGHT_COLOR=.*$")
        guard expression.numberOfMatches(in: old, range: NSRange(old.startIndex..., in: old)) == 1 else { throw SetupError("Cannot locate a unique HIGHLIGHT_COLOR in SketchyBar config.") }
        let updated = expression.stringByReplacingMatches(in: old, range: NSRange(old.startIndex..., in: old), withTemplate: "export HIGHLIGHT_COLOR=0xff" + color.dropFirst())
        if let transaction { try journal.write(target, data: Data(updated.utf8), transaction: transaction) }
        else {
            // A background process must never follow config symlinks into a personal repo.
            var check = target
            while check.path != paths.home.path && check.path != "/" {
                if (try? FileManager.default.attributesOfItem(atPath: check.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                    throw SetupError("The watcher refuses a symlinked color configuration. Apply sketchybar-profile to create a backed-up local copy first.")
                }
                check.deleteLastPathComponent()
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            try Data(updated.utf8).write(to: target, options: .atomic)
            if let permissions = attributes[.posixPermissions] { try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
        }
        if let sketchybar = resolveTool("sketchybar"), let aerospace = resolveTool("aerospace") {
            let focused = try runner.checked(aerospace, ["list-workspaces", "--focused"])
            guard !focused.text.isEmpty && !focused.text.contains("\n") else { throw SetupError("AeroSpace returned an invalid focused workspace; the watcher will retry.") }
            try runner.checked(sketchybar, ["--trigger", "aerospace_workspace_change", "FOCUSED_WORKSPACE=" + focused.text])
        }
    }

    private func installWallpaperWatcher(transaction: String, image: URL?) throws {
        guard !(try journal.launchAgentLoaded(WallpaperWatcher.legacyLabel)) else {
            throw SetupError("The old WallpaperAccentWatcher job is loaded. Stop it first, then retry; mac-setup will not disable another tool's job automatically.")
        }
        guard let runtimeSource, FileManager.default.isExecutableFile(atPath: runtimeSource.appendingPathComponent("mac-setup").path),
              FileManager.default.fileExists(atPath: runtimeSource.appendingPathComponent("MacSetup_MacSetupCore.bundle").path) else {
            throw SetupError("Watcher installation needs the compiled mac-setup executable beside its resource bundle. Use an extracted release or the Swift build output.")
        }
        let plist = paths.home.appendingPathComponent("Library/LaunchAgents/" + WallpaperWatcher.label + ".plist")
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for name in ["mac-setup", "MacSetup_MacSetupCore.bundle"] {
            try FileManager.default.copyItem(at: runtimeSource.appendingPathComponent(name), to: staging.appendingPathComponent(name))
        }
        try journal.suspendLaunchAgent(WallpaperWatcher.label, plist: plist, transaction: transaction)
        try journal.replace(paths.state.appendingPathComponent("watcher-runtime"), with: staging, transaction: transaction)
        try journal.write(plist, data: WallpaperWatcher.launchPlist(paths: paths, image: image), transaction: transaction)
        try journal.loadLaunchAgent(plist)
        guard try journal.launchAgentLoaded(WallpaperWatcher.label) else { throw SetupError("Wallpaper watcher registration could not be verified.") }
    }
}
