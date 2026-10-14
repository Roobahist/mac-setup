import Foundation
import MacSetupCore

// The bundled fallback is a user-level LaunchAgent, not a new login app.
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
    try WallpaperWatcher.runBuiltIn(engine: engine)
} catch {
    fputs("Wallpaper watcher could not start: \(error)\n", stderr)
    exit(1)
}
