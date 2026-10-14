import Foundation
import MacSetupCore

// The shared watcher is a user-level LaunchAgent, not a new login app.
// It shares Mac Setup's wallpaper color calculation and never edits dotfiles.
if CommandLine.arguments.contains("--self-check") {
    let paths = Paths()
    guard FileManager.default.fileExists(atPath: paths.profile.appendingPathComponent("unsplash/get_wallpaper_accent.py").path) else {
        fputs("Bundled wallpaper extractor is missing.\n", stderr)
        exit(1)
    }
    print("Wallpaper helper and resources available.")
    exit(0)
}

do {
    let engine = try Engine()
    let image = ProcessInfo.processInfo.environment["WALLPAPER_ACCENT_IMAGE"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    try WallpaperWatcher.runBuiltIn(engine: engine, image: image)
} catch {
    fputs("Wallpaper watcher could not start: \(error)\n", stderr)
    exit(1)
}
