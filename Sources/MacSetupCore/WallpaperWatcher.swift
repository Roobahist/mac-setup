import Foundation
import AppKit
import Darwin

public struct WallpaperFingerprint: Equatable {
    public let path: String
    public let size: Int
    public let modified: Date
    public init(path: String, size: Int, modified: Date) { self.path = path; self.size = size; self.modified = modified }
    public init(image: URL) throws {
        let values = try image.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        self.init(path: image.path, size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast)
    }
}

/// Apply at startup, debounce subsequent changes, and retry failed images.
/// Kept separate from the run loop so no real wallpaper is needed in tests.
public struct WallpaperPolicy {
    private var applied: WallpaperFingerprint?
    private var pending: WallpaperFingerprint?
    private var stable = 0
    private var failed: WallpaperFingerprint?
    private var retryAfter = Date.distantPast
    public init() {}

    public mutating func shouldApply(_ image: WallpaperFingerprint, now: Date) -> Bool {
        guard image != applied else { return false }
        if image == failed && now < retryAfter { return false }
        if applied == nil { return true }
        if image == pending { stable += 1 } else { pending = image; stable = 1 }
        return stable >= 2
    }
    public mutating func succeeded(_ image: WallpaperFingerprint) {
        applied = image; pending = nil; failed = nil; stable = 0
    }
    public mutating func failed(_ image: WallpaperFingerprint, now: Date) {
        failed = image; retryAfter = now.addingTimeInterval(15)
    }
}

public final class WallpaperWatcher {
    public static let label = "io.github.roobahist.mac-setup.wallpaper"
    public static let legacyLabel = "com.roobahist.wallpaper-watcher"
    private let engine: Engine
    private let imageOverride: URL?
    private var policy = WallpaperPolicy()
    private var lastError = Date.distantPast
    private var timer: Timer?

    public init(engine: Engine, image: URL? = nil) { self.engine = engine; imageOverride = image }
    public func run(once: Bool = false) throws {
        if once { try check(); return }
        print("Watching the main display wallpaper every two seconds. Press Control+C to stop a foreground watcher.")
        do { try check() } catch { logError(error) }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            do { try self.check() } catch { self.logError(error) }
        }
        RunLoop.main.run()
    }

    private func check() throws {
        let image: URL
        if let imageOverride { image = imageOverride }
        else {
            guard let screen = NSScreen.main, let active = NSWorkspace.shared.desktopImageURL(for: screen) else {
                throw SetupError("The current wallpaper is unavailable. Use a static image or --image with an accessible local image.")
            }
            image = active
        }
        let fingerprint = try WallpaperFingerprint(image: image)
        guard policy.shouldApply(fingerprint, now: Date()) else { return }
        do {
            let lock = try SetupLock(paths: engine.paths)
            defer { withExtendedLifetime(lock) {} }
            try engine.refreshAccent(image: image)
            policy.succeeded(fingerprint)
            print("Updated the SketchyBar accent configuration at \(Date().ISO8601Format()).")
            fflush(stdout)
        } catch {
            policy.failed(fingerprint, now: Date())
            throw error
        }
    }

    private func logError(_ error: Error) {
        guard Date().timeIntervalSince(lastError) >= 15 else { return }
        lastError = Date()
        fputs("\(Date().ISO8601Format()) Watcher: \(error)\n", stderr)
    }

    public static func launchPlist(paths: Paths, image: URL? = nil) throws -> Data {
        let runtime = paths.state.appendingPathComponent("watcher-runtime")
        var arguments = [runtime.appendingPathComponent("mac-setup").path, "watch"]
        if let image { arguments += ["--image", image.path] }
        let properties: [String: Any] = [
            "Label": label, "ProgramArguments": arguments,
            "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 15,
            "LimitLoadToSessionType": "Aqua",
            "EnvironmentVariables": ["XDG_CONFIG_HOME": paths.config.path],
            "StandardOutPath": paths.state.appendingPathComponent("wallpaper-watcher.log").path,
            "StandardErrorPath": paths.state.appendingPathComponent("wallpaper-watcher-errors.log").path
        ]
        return try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
    }
}
