import Foundation
import MacSetupCore

// The bundled fallback is a user-level LaunchAgent, not a new login app.
// It shares Mac Setup's wallpaper color calculation and never edits dotfiles.
do {
    let engine = try Engine()
    try WallpaperWatcher.runBuiltIn(engine: engine)
} catch {
    fputs("Wallpaper watcher could not start: \(error)\n", stderr)
    exit(1)
}
