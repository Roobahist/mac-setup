import AppKit
import Foundation
import Darwin

/// All installations use the packaged runtime. The old label is retained only
/// to migrate and restore installations of the standalone watcher app.
public enum WallpaperWatcher {
    public static let label = "com.roobahist.wallpaper-watcher"
    public static let replacementLabel = "io.github.roobahist.mac-setup.wallpaper"

    public struct Source: Equatable {
        public let label: String
        public let executable: URL
    }

    public static func bundledExecutable(paths: Paths) -> URL? {
        let name = "mac-setup-wallpaper-watcher"
        // Prefer the helper shipped beside the calling CLI/app, including
        // installations under a custom prefix. Isolated homes never use it.
        let local: [URL]
        if paths.home == FileManager.default.homeDirectoryForCurrentUser {
            local = [Bundle.main.executableURL?.resolvingSymlinksInPath()
                .deletingLastPathComponent().appendingPathComponent(name),
                Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)")]
                .compactMap { $0 }
        } else { local = [] }
        let candidates = local + [
            paths.home.appendingPathComponent(".local/lib/mac-setup/current/\(name)"),
            paths.home.appendingPathComponent("Applications/Mac Setup.app/Contents/Helpers/\(name)"),
            URL(fileURLWithPath: "/Applications/Mac Setup.app/Contents/Helpers/\(name)")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static func source(paths: Paths) throws -> Source {
        if let bundled = bundledExecutable(paths: paths) {
            return Source(label: replacementLabel, executable: bundled)
        }
        throw SetupError("The wallpaper watcher helper is missing from Mac Setup. Reinstall the current Mac Setup release, then retry Automatic wallpaper color updates.")
    }

    public static func runningLabel(journal: Journal) throws -> String? {
        if try journal.launchAgentLoaded(replacementLabel) { return replacementLabel }
        if try journal.launchAgentLoaded(label) { return label }
        return nil
    }

    public static func isCurrent(engine: Engine) throws -> Bool {
        guard let helper = bundledExecutable(paths: engine.paths),
              try engine.journal.launchAgentLoaded(replacementLabel),
              try !engine.journal.launchAgentLoaded(label) else { return false }
        let agents = engine.paths.home.appendingPathComponent("Library/LaunchAgents")
        guard !Journal.exists(agents.appendingPathComponent("\(label).plist")),
              let data = try? Data(contentsOf: agents.appendingPathComponent("\(replacementLabel).plist")),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        let environment = values["EnvironmentVariables"] as? [String: String]
        let identity = try runtimeIdentity(helper)
        return values["ProgramArguments"] as? [String] == [helper.path] &&
            environment?["MAC_SETUP_WATCHER_BUILD"] == identity
    }

    private static func runtimeIdentity(_ executable: URL) throws -> String {
        guard let fingerprint = try Journal.fingerprint(executable) else {
            throw SetupError("The packaged wallpaper watcher disappeared. Reinstall Mac Setup.")
        }
        return fingerprint.map { String(format: "%02x", $0) }.joined()
    }

    public static func run(engine: Engine, image: URL? = nil, once: Bool = false) throws {
        guard try runningLabel(journal: engine.journal) == nil else {
            throw SetupError("A startup watcher is already running. Stop it before starting a foreground watcher.")
        }
        try runBuiltIn(engine: engine, image: image, once: once)
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
        if enabled {
            // Setup journals the migration and removes the old startup entry.
            // Reapply even when loaded so updates restart the executable.
            let recovery = try engine.apply(Catalog.task("wallpaper-watcher"))
            print("Watcher recovery record: \(recovery)")
        } else {
            for selected in [label, replacementLabel] {
                try engine.runner.checked("/bin/launchctl", ["disable", "gui/\(getuid())/\(selected)"])
                try engine.journal.stopLaunchAgent(selected)
            }
        }
    }

    public static func launchPlist(paths: Paths, image: URL? = nil) throws -> Data {
        let chosen = try source(paths: paths)
        return try launchPlist(source: chosen, paths: paths, image: image)
    }

    public static func launchPlist(source: Source, paths: Paths, image: URL? = nil) throws -> Data {
        var environment = [
            "HOME": paths.home.path,
            "MAC_SETUP_WATCHER_BUILD": try runtimeIdentity(source.executable),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
