import AppKit
import SwiftUI

/// SketchyBar uses 0xAARRGGBB; preserve alpha in its transparent bar colors.
enum WorkspaceColor {
    static func swiftUI(_ hex: String) -> Color {
        let raw = String(hex.dropFirst(2))
        guard let value = UInt32(raw, radix: 16) else { return .white }
        return Color(.sRGB,
                     red: Double((value >> 16) & 0xff) / 255,
                     green: Double((value >> 8) & 0xff) / 255,
                     blue: Double(value & 0xff) / 255,
                     opacity: Double((value >> 24) & 0xff) / 255)
    }

    static func argb(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else {
            return "0xffffffff"
        }
        func byte(_ value: CGFloat) -> Int {
            Int((max(0, min(1, value)) * 255).rounded())
        }
        return String(format: "0x%02x%02x%02x%02x",
                      byte(rgb.alphaComponent), byte(rgb.redComponent),
                      byte(rgb.greenComponent), byte(rgb.blueComponent))
    }
}
