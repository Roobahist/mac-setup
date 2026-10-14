import Foundation

/// SketchyBar's manual accent is separate from the macOS global accent.
public final class DesktopAccentService {
    private let engine: Engine

    public init(engine: Engine) {
        self.engine = engine
    }

    public var manualColorFile: URL {
        engine.paths.home.appendingPathComponent(".cache/sketchybar/highlight-color")
    }

    public func currentColor() -> String? {
        guard let raw = try? String(contentsOf: manualColorFile, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^0xff[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            return nil
        }
        return String(value.suffix(6)).uppercased()
    }

    public func watcherIsRunning() throws -> Bool {
        try WallpaperWatcher.runningLabel(journal: engine.journal) != nil
    }

    public func setWatcherEnabled(_ enabled: Bool) throws {
        let lock = try SetupLock(paths: engine.paths)
        defer { withExtendedLifetime(lock) {} }
        try WallpaperWatcher.setEnabled(enabled, engine: engine)
    }

    @discardableResult
    public func setManualColor(_ hex: String) throws -> String {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            throw SetupError("Enter a six-digit RGB color.")
        }
        guard try !watcherIsRunning() else {
            throw SetupError("Turn off automatic wallpaper colors before setting a manual accent.")
        }

        let lock = try SetupLock(paths: engine.paths)
        defer { withExtendedLifetime(lock) {} }
        let transaction = try engine.journal.begin("appearance.manualAccent")
        let data = Data(("0xff" + cleaned.uppercased() + "\n").utf8)
        try engine.journal.write(manualColorFile, data: data, transaction: transaction)
        try engine.journal.finish(transaction)
        // A missing or temporarily unresponsive bar must not invalidate a saved color.
        try? refreshSketchyBar()
        return transaction
    }

    public func refreshSketchyBar() throws {
        guard let sketchybar = executable("sketchybar") else { return }
        if let aerospace = executable("aerospace") {
            let focused = try engine.runner.run(aerospace, ["list-workspaces", "--focused"])
            if focused.status == 0 && !focused.text.isEmpty {
                _ = try? engine.runner.run(sketchybar,
                    ["--trigger", "aerospace_workspace_change", "FOCUSED_WORKSPACE=" + focused.text])
            }
        }
        // The profile reads the cache on its workspace event. A standalone
        // SketchyBar install may need its own color integration.
    }
}
