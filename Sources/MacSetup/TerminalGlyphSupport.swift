import AppKit
import Foundation

/// Terminal applications do not expose a standard API for their configured font.
/// Checking installed font families avoids printing unreadable private-use code
/// points on machines without Hack Nerd Font. Users whose terminal is configured
/// differently can override detection without changing the workspace glyphs.
enum TerminalGlyphSupport {
    static func enabled(fontFamilies: [String] = NSFontManager.shared.availableFontFamilies,
                        environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        switch environment["MAC_SETUP_GLYPHS"]?.lowercased() {
        case "show", "on", "1": return true
        case "hide", "off", "0": return false
        default:
            return fontFamilies.contains {
                $0.replacingOccurrences(of: " ", with: "")
                    .localizedCaseInsensitiveContains("HackNerdFont")
            }
        }
    }
}
