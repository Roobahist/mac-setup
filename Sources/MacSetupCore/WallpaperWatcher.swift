import Foundation
import Darwin

/// Integrate the existing app; mac-setup does not run a second wallpaper timer.
public enum WallpaperWatcher {
    public static let label = "com.roobahist.wallpaper-watcher"
    public static let replacementLabel = "io.github.roobahist.mac-setup.wallpaper"

    public static func executable(paths: Paths) -> URL? {
        let candidates = [paths.home.appendingPathComponent("Applications/WallpaperAccentWatcher.app"), URL(fileURLWithPath: "/Applications/WallpaperAccentWatcher.app")]
        return candidates.map { $0.appendingPathComponent("Contents/MacOS/WallpaperAccentWatcher") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static func run(engine: Engine, image: URL? = nil, once: Bool = false) throws {
        guard let executable = executable(paths: engine.paths) else {
            throw SetupError("Install WallpaperAccentWatcher.app in ~/Applications or /Applications first.")
        }
        guard !(try engine.journal.launchAgentLoaded(label)), !(try engine.journal.launchAgentLoaded(replacementLabel)) else {
            throw SetupError("A startup watcher is already running. Stop it before starting a foreground watcher.")
        }
        var arguments = ["WALLPAPER_ACCENT_EXTRACTOR=" + engine.paths.config.appendingPathComponent("unsplash/get_wallpaper_accent.py").path,
                         "WALLPAPER_ACCENT_COLORS=" + engine.paths.config.appendingPathComponent("sketchybar/plugins/colors.sh").path]
        if once { arguments.append("WALLPAPER_ACCENT_ONESHOT=1") }
        if let image { arguments.append("WALLPAPER_ACCENT_IMAGE=" + image.path) }
        arguments.append(executable.path)
        try engine.runner.checked("/usr/bin/env", arguments, interactive: true)
    }

    public static func setEnabled(_ enabled: Bool, engine: Engine) throws {
        let plist = engine.paths.home.appendingPathComponent("Library/LaunchAgents/" + label + ".plist")
        if enabled && !Journal.exists(plist) { throw SetupError("Run setup wallpaper-watcher before enabling it.") }
        if enabled, try engine.journal.launchAgentLoaded(replacementLabel) {
            throw SetupError("Stop the mac-setup replacement watcher before enabling WallpaperAccentWatcher.")
        }
        try engine.runner.checked("/bin/launchctl", [enabled ? "enable" : "disable", "gui/\(getuid())/\(label)"])
        if enabled {
            if !(try engine.journal.launchAgentLoaded(label)) { try engine.journal.loadLaunchAgent(plist) }
        } else { try engine.journal.stopLaunchAgent(label) }
    }

    public static func launchPlist(paths: Paths, image: URL? = nil) throws -> Data {
        guard let executable = executable(paths: paths) else {
            throw SetupError("Install WallpaperAccentWatcher.app in ~/Applications or /Applications first.")
        }
        var environment = ["HOME": paths.home.path,
                           "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                           "WALLPAPER_ACCENT_EXTRACTOR": paths.config.appendingPathComponent("unsplash/get_wallpaper_accent.py").path,
                           "WALLPAPER_ACCENT_COLORS": paths.config.appendingPathComponent("sketchybar/plugins/colors.sh").path]
        if let image { environment["WALLPAPER_ACCENT_IMAGE"] = image.path }
        let properties: [String: Any] = [
            "Label": label, "ProgramArguments": [executable.path],
            "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10,
            "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive",
            "EnvironmentVariables": environment,
            "StandardOutPath": "/tmp/wallpaper-accent-watcher.stdout.log",
            "StandardErrorPath": "/tmp/wallpaper-accent-watcher.stderr.log"
        ]
        return try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
    }
}
