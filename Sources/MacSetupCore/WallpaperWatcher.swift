import AppKit
import Foundation
import Darwin

/// Prefer the user's existing watcher. The bundled helper is only used when
/// no existing watcher application is available.
public enum WallpaperWatcher {
    public static let label = "com.roobahist.wallpaper-watcher"
    public static let replacementLabel = "io.github.roobahist.mac-setup.wallpaper"

    public struct Source: Equatable {
        public let label: String
        public let executable: URL
        public let bundled: Bool
    }

    public static func executable(paths: Paths) -> URL? {
        let candidates = [
            paths.home.appendingPathComponent("Applications/WallpaperAccentWatcher.app"),
            URL(fileURLWithPath: "/Applications/WallpaperAccentWatcher.app")
        ]
        return candidates.map { $0.appendingPathComponent("Contents/MacOS/WallpaperAccentWatcher") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static func bundledExecutable(paths: Paths) -> URL? {
        let name = "mac-setup-wallpaper-watcher"
        let candidates = [
            paths.home.appendingPathComponent("Applications/Mac Setup.app/Contents/Helpers/\(name)"),
            URL(fileURLWithPath: "/Applications/Mac Setup.app/Contents/Helpers/\(name)"),
            paths.home.appendingPathComponent(".local/lib/mac-setup/current/\(name)"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static func source(paths: Paths) throws -> Source {
        if let installed = executable(paths: paths) {
            return Source(label: label, executable: installed, bundled: false)
        }
        if let bundled = bundledExecutable(paths: paths) {
            return Source(label: replacementLabel, executable: bundled, bundled: true)
        }
        throw SetupError("The wallpaper watcher helper is missing from Mac Setup. Reinstall the current Mac Setup release, then retry Automatic wallpaper color updates.")
    }

    public static func runningLabel(journal: Journal) throws -> String? {
        if try journal.launchAgentLoaded(label) { return label }
        if try journal.launchAgentLoaded(replacementLabel) { return replacementLabel }
        return nil
    }

    public static func installedLabel(paths: Paths) -> String {
        let original = paths.home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
        let fallback = paths.home.appendingPathComponent("Library/LaunchAgents/\(replacementLabel).plist")
        // A stale plist may remain after the original app is removed. Prefer
        // the available executable's intended service rather than its plist.
        if let preferred = try? source(paths: paths) {
            let matching = preferred.label == label ? original : fallback
            if Journal.exists(matching) { return preferred.label }
        }
        if Journal.exists(original) { return label }
        if Journal.exists(fallback) { return replacementLabel }
        return executable(paths: paths) != nil ? label : replacementLabel
    }

    public static func run(engine: Engine, image: URL? = nil, once: Bool = false) throws {
        guard try runningLabel(journal: engine.journal) == nil else {
            throw SetupError("A startup watcher is already running. Stop it before starting a foreground watcher.")
        }
        if let original = executable(paths: engine.paths) {
            var arguments = [
                "WALLPAPER_ACCENT_EXTRACTOR=" + engine.paths.config.appendingPathComponent("unsplash/get_wallpaper_accent.py").path,
                "WALLPAPER_ACCENT_COLORS=" + engine.paths.config.appendingPathComponent("sketchybar/plugins/colors.sh").path
            ]
            if once { arguments.append("WALLPAPER_ACCENT_ONESHOT=1") }
            if let image { arguments.append("WALLPAPER_ACCENT_IMAGE=" + image.path) }
            arguments.append(original.path)
            try engine.runner.checked("/usr/bin/env", arguments, interactive: true)
        } else {
            guard bundledExecutable(paths: engine.paths) != nil else {
                throw SetupError("The bundled watcher helper is missing. Reinstall Mac Setup and retry.")
            }
            try runBuiltIn(engine: engine, image: image, once: once)
        }
    }

    public struct Observation: Equatable {
        public let url: URL
        public let stamp: WallpaperStamp

        public init(url: URL, stamp: WallpaperStamp) {
            self.url = url
            self.stamp = stamp
        }
    }

    /// Run the watcher with injectable observation, clock, and waiting policies.
    /// Sampling again after the debounce ensures we process the wallpaper that
    /// is actually visible, not an outdated URL captured before a Space change.
    public static func monitor(
        once: Bool = false,
        maxPolls: Int? = nil,
        observe: () throws -> Observation,
        apply: (URL) throws -> Void,
        wait: (TimeInterval) -> Void,
        now: () -> Date = Date.init,
        report: (String) -> Void
    ) throws {
        var lastApplied: WallpaperStamp?
        var failedStamp: WallpaperStamp?
        var retryAt = Date.distantPast
        var lastObserved: WallpaperStamp?
        var lastHeartbeat = now()
        var pollNumber = 0

        while maxPolls.map({ pollNumber < $0 }) ?? true {
            pollNumber += 1
            do {
                let candidate = try observe()
                if candidate.stamp != lastObserved {
                    report("Detected wallpaper: \(candidate.url.lastPathComponent) (size=\(candidate.stamp.size), modified=\(candidate.stamp.modified.timeIntervalSince1970))")
                    lastObserved = candidate.stamp
                }
                if candidate.stamp != lastApplied &&
                   (candidate.stamp != failedStamp || now() >= retryAt) {
                    if !once {
                        wait(2)
                        let confirmed = try observe()
                        if confirmed != candidate {
                            report("Wallpaper changed during debounce; checking the latest image")
                            continue
                        }
                    }
                    do {
                        try apply(candidate.url)
                        lastApplied = candidate.stamp
                        failedStamp = nil
                        report("Accent updated: \(candidate.url.lastPathComponent)")
                    } catch {
                        report("Accent update failed: \(error)")
                        failedStamp = candidate.stamp
                        retryAt = now().addingTimeInterval(60)
                        if once { throw error }
                    }
                }

                if now().timeIntervalSince(lastHeartbeat) >= 60 {
                    report("Watcher alive; current wallpaper: \(candidate.url.lastPathComponent)")
                    lastHeartbeat = now()
                }
            } catch {
                if once { throw error }
                report("Could not inspect desktop wallpaper: \(error)")
            }

            if once { return }
            wait(2)
        }
    }

    /// Keep the main thread's AppKit run loop alive while waiting. Sleeping
    /// this thread prevents AppKit from processing display and Space updates;
    /// desktopImageURL(for:) can then keep reporting the first observed image.
    public static func waitForDesktopEvents(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in }
        RunLoop.current.add(timer, forMode: .default)
        RunLoop.current.run(until: deadline)
        timer.invalidate()
    }

    public static func runBuiltIn(engine: Engine, image: URL? = nil, once: Bool = false) throws {
        let log: (String) -> Void = { message in
            print("[\(ISO8601DateFormatter().string(from: Date()))] \(message)")
            fflush(stdout)
        }
        try monitor(
            once: once,
            observe: {
                let wallpaper = try image ?? currentWallpaper()
                return Observation(url: wallpaper, stamp: try WallpaperStamp.read(wallpaper))
            },
            apply: { wallpaper in
                if try !engine.refreshWallpaperAccent(image: wallpaper) {
                    log("The newly selected wallpaper produced the same accent color as the previous image")
                }
            },
            wait: waitForDesktopEvents,
            report: log
        )
    }

    private static func currentWallpaper() throws -> URL {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            throw SetupError("No accessible wallpaper image was returned for the current display.")
        }
        return url
    }

    public struct WallpaperStamp: Equatable {
        let path: String
        let size: Int64
        let modified: Date

        public static func read(_ url: URL) throws -> WallpaperStamp {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date else {
                throw SetupError("Cannot inspect wallpaper file metadata at \(url.path).")
            }
            return WallpaperStamp(path: url.standardizedFileURL.path,
                                  size: size.int64Value, modified: modified)
        }
    }

    public static func setEnabled(_ enabled: Bool, engine: Engine) throws {
        let active = try runningLabel(journal: engine.journal)
        let selected = active ?? installedLabel(paths: engine.paths)
        let plist = engine.paths.home.appendingPathComponent("Library/LaunchAgents/\(selected).plist")
        if enabled && !Journal.exists(plist) {
            throw SetupError("Run setup wallpaper-watcher before enabling it.")
        }
        let other = selected == label ? replacementLabel : label
        if try enabled && engine.journal.launchAgentLoaded(other) {
            throw SetupError("A different wallpaper watcher is already running. Stop it before enabling another.")
        }
        try engine.runner.checked("/bin/launchctl", [
            enabled ? "enable" : "disable", "gui/\(getuid())/\(selected)"
        ])
        if enabled {
            if !(try engine.journal.launchAgentLoaded(selected)) {
                try engine.journal.loadLaunchAgent(plist)
            }
        } else {
            try engine.journal.stopLaunchAgent(selected)
        }
    }

    public static func launchPlist(paths: Paths, image: URL? = nil) throws -> Data {
        let chosen = try source(paths: paths)
        return try launchPlist(source: chosen, paths: paths, image: image)
    }

    public static func launchPlist(source: Source, paths: Paths, image: URL? = nil) throws -> Data {
        var environment = [
            "HOME": paths.home.path,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "WALLPAPER_ACCENT_EXTRACTOR": paths.config.appendingPathComponent("unsplash/get_wallpaper_accent.py").path,
            "WALLPAPER_ACCENT_COLORS": paths.config.appendingPathComponent("sketchybar/plugins/colors.sh").path
        ]
        if let image { environment["WALLPAPER_ACCENT_IMAGE"] = image.path }
        let properties: [String: Any] = [
            "Label": source.label,
            "ProgramArguments": [source.executable.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 10,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "EnvironmentVariables": environment,
            "StandardOutPath": "/tmp/wallpaper-accent-watcher.stdout.log",
            "StandardErrorPath": "/tmp/wallpaper-accent-watcher.stderr.log"
        ]
        return try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
    }
}
