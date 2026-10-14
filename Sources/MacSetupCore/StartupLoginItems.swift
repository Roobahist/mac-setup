import Foundation

/// Manages the user-facing "Open at Login" list without modifying other items.
/// System Events may require macOS Automation consent on the first invocation.
public enum StartupLoginItems {
    public static let appNames = ["AeroSpace", "Karabiner-Elements", "Raycast"]

    /// Keep application startup distinct from background daemons. SketchyBar
    /// runs through its Homebrew service; the wallpaper accent watcher has a
    /// dedicated LaunchAgent; Karabiner helpers manage their own background jobs.
    public static func installedPaths(home: URL, resolve: (String, URL) -> String? = appPath) -> [String] {
        appNames.compactMap { resolve($0, home) }
    }

    public static let script = """
    on run argv
        set operationName to item 1 of argv
        set desiredPath to item 2 of argv
        tell application "System Events"
            repeat with candidate in login items
                try
                    if (path of candidate as text) is desiredPath then
                        if operationName is "remove" then
                            delete candidate
                            return "removed"
                        end if
                        return "present"
                    end if
                end try
            end repeat
            if operationName is "add" then
                make new login item at end with properties {path:desiredPath, hidden:true}
                return "added"
            end if
        end tell
        return "missing"
    end run
    """

    public static func arguments(_ operation: String, path: String) -> [String] {
        ["-e", script, operation, path]
    }

    public static func query(_ path: String, runner: CommandRunning) throws -> Bool {
        let result = try runner.run("/usr/bin/osascript", arguments("check", path: path))
        guard result.status == 0 else {
            throw SetupError("Cannot inspect Open at Login items. Allow Mac Setup to control System Events in Privacy & Security > Automation, then retry. \(result.text)")
        }
        switch result.text {
        case "present": return true
        case "missing": return false
        default: throw SetupError("Unexpected response while reading Open at Login for \(URL(fileURLWithPath: path).lastPathComponent).")
        }
    }

    public static func update(_ path: String, enabled: Bool, runner: CommandRunning) throws {
        let operation = enabled ? "add" : "remove"
        let result = try runner.run("/usr/bin/osascript", arguments(operation, path: path))
        guard result.status == 0 else {
            throw SetupError("Could not update Open at Login for \(URL(fileURLWithPath: path).lastPathComponent). Approve System Events automation and retry. \(result.text)")
        }
        guard result.text == (enabled ? "added" : "removed") || result.text == (enabled ? "present" : "missing") else {
            throw SetupError("Unexpected response while updating the login item.")
        }
        guard try query(path, runner: runner) == enabled else {
            throw SetupError("macOS did not retain the login item. Check System Settings > General > Login Items & Extensions.")
        }
    }
}
