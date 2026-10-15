import Foundation

/// SketchyBar colors are alpha followed by sRGB, each stored as one byte.
public struct BarColor: Equatable {
    public let value: UInt32

    public init?(_ hex: String) {
        guard hex.hasPrefix("0x"), hex.count == 10,
              let value = UInt32(hex.dropFirst(2), radix: 16) else { return nil }
        self.value = value
    }

    private init(value: UInt32) { self.value = value }
    public var hex: String { String(format: "0x%08x", value) }
    public var rgbHex: String { String(format: "#%06x", value & 0xffffff) }
    public var opacity: Double { Double(value >> 24) / 255 }
    public var opaque: BarColor { BarColor(value: value | 0xff000000) }

    public func replacingRGB(_ hex: String) -> BarColor? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let rgb = UInt32(digits, radix: 16) else { return nil }
        return BarColor(value: (value & 0xff000000) | rgb)
    }

    public func replacingOpacity(_ opacity: Double) -> BarColor {
        let alpha = UInt32((max(0, min(1, opacity.isFinite ? opacity : 0)) * 255).rounded())
        return BarColor(value: (alpha << 24) | (value & 0xffffff))
    }
}
