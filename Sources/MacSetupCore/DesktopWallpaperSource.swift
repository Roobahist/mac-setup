import AppKit
import CoreGraphics
import Foundation

/// AppKit reports a Space's desktop slot, which may be the system placeholder.
/// Resolve the configured image for the primary display before trusting that slot.
enum DesktopWallpaperSource {
    static let systemFallback = "/System/Library/CoreServices/DefaultDesktop.heic"

    static func resolve(reported: URL?, configured: URL?) throws -> URL {
        if let configured { return configured }
        if let reported, reported.standardizedFileURL.path != systemFallback { return reported }
        throw SetupError("The current Space has no confirmed desktop image; preserving the wallpaper accent.")
    }

    static func configuredImage(
        wallpapers: [String: Any], spaces: [String: Any], displayUUID: String, isPrimary: Bool
    ) -> URL? {
        // These preference files are not a public API. Decode only known image
        // records for this display and the recorded active desktop; never scan
        // historical Spaces or borrow another display's wallpaper.
        guard let configuration = spaces["SpacesDisplayConfiguration"] as? [String: Any],
              let management = configuration["Management Data"] as? [String: Any],
              let monitors = management["Monitors"] as? [[String: Any]],
              let monitor = monitors.first(where: {
                  let id = $0["Display Identifier"] as? String
                  return id == displayUUID || (isPrimary && id == "Main")
              }),
              let current = monitor["Current Space"] as? [String: Any],
              current["type"] as? Int == 0,
              let uuid = current["uuid"] as? String,
              let allSpaces = wallpapers["Spaces"] as? [String: Any],
              let space = allSpaces[uuid] as? [String: Any] else { return nil }
        let spaceDisplays = space["Displays"] as? [String: Any]
        let displays = wallpapers["Displays"] as? [String: Any]
        let nodes = [space["Default"], spaceDisplays?[displayUUID],
                     displays?[displayUUID], wallpapers["AllSpacesAndDisplays"]]
        var choices: [(Date, URL?)] = []
        for case let node as [String: Any] in nodes {
            guard let desktop = node["Desktop"] as? [String: Any],
                  let date = desktop["LastSet"] as? Date else { continue }
            let content = desktop["Content"] as? [String: Any]
            let records = content?["Choices"] as? [[String: Any]]
            var image: URL?
            if let records, records.count == 1,
               records[0]["Provider"] as? String == "com.apple.wallpaper.choice.image",
               let data = records[0]["Configuration"] as? Data,
               let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               value["type"] as? String == "imageFile",
               let url = value["url"] as? [String: Any],
               let relative = url["relative"] as? String,
               let candidate = URL(string: relative), candidate.isFileURL {
                image = candidate
            }
            choices.append((date, image))
        }
        guard let newest = choices.map({ $0.0 }).max() else { return nil }
        // A newer dynamic/unknown selection must not revive an older still image.
        let latest = choices.filter { $0.0 == newest }
        guard let image = latest.first?.1,
              latest.allSatisfy({ $0.1 == image }) else { return nil }
        return image
    }

    static func current(home: URL) throws -> URL {
        // NSScreen.main follows the focused window. A global bar accent must
        // consistently use the primary display instead of following app focus.
        guard let screen = NSScreen.screens.first,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { throw SetupError("The primary display is unavailable.") }
        let id = number.uint32Value
        let reported = NSWorkspace.shared.desktopImageURL(for: screen)
        if let reported, reported.standardizedFileURL.path != systemFallback { return reported }
        var configured: URL?
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            func plist(_ path: String) -> [String: Any]? {
                guard let data = try? Data(contentsOf: home.appendingPathComponent(path)) else { return nil }
                return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            }
            if let wallpapers = plist("Library/Application Support/com.apple.wallpaper/Store/Index.plist"),
               let spaces = plist("Library/Preferences/com.apple.spaces.plist") {
                configured = configuredImage(wallpapers: wallpapers, spaces: spaces,
                    displayUUID: CFUUIDCreateString(nil, uuid) as String, isPrimary: id == CGMainDisplayID())
                if let image = configured, !FileManager.default.isReadableFile(atPath: image.path) {
                    configured = nil
                }
            }
        }
        return try resolve(reported: reported, configured: configured)
    }
}
