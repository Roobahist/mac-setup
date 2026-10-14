import Foundation

public extension Engine {
    func spotlightSearchEnabled() throws -> Bool {
        let keys = try journal.preference("com.apple.symbolichotkeys", "AppleSymbolicHotKeys") as? [String: Any]
        let search = keys?["64"] as? [String: Any]
        return search?["enabled"] as? Bool ?? true
    }

    func releaseSpotlightShortcut(transaction: String) throws {
        let old = try journal.preference("com.apple.symbolichotkeys", "AppleSymbolicHotKeys")
        guard old == nil || old is [String: Any] else { throw SetupError("Could not decode the existing system shortcuts. Disable Show Spotlight search in Keyboard Shortcuts manually.") }
        var keys = old as? [String: Any] ?? [:]
        var search = keys["64"] as? [String: Any] ?? ["value": ["type": "standard", "parameters": [32, 49, 1048576]]]
        search["enabled"] = false
        keys["64"] = search
        try journal.setPreference("com.apple.symbolichotkeys", "AppleSymbolicHotKeys", keys, transaction: transaction)
        let refresh = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        if FileManager.default.isExecutableFile(atPath: refresh) { try runner.checked(refresh, ["-u"]) }
    }
}
