import AppKit

// A vector-drawn Mac Setup icon; no downloaded assets or font dependency.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func render(_ pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
    NSGradient(starting: color(0x5379ef), ending: color(0x253c87))!.draw(in: tile, angle: -70)
    color(0xf4f7ff).setFill()
    NSBezierPath(roundedRect: NSRect(x: 206, y: 335, width: 612, height: 404), xRadius: 45, yRadius: 45).fill()
    color(0x182b63).setFill()
    NSBezierPath(roundedRect: NSRect(x: 232, y: 361, width: 560, height: 352), xRadius: 25, yRadius: 25).fill()
    color(0xabc5ff).setFill()
    NSBezierPath(roundedRect: NSRect(x: 260, y: 647, width: 504, height: 38), xRadius: 12, yRadius: 12).fill()
    color(0x648cff).setFill()
    NSBezierPath(roundedRect: NSRect(x: 260, y: 392, width: 212, height: 227), xRadius: 18, yRadius: 18).fill()
    color(0xf4f7ff).setFill()
    for y in [CGFloat(514), CGFloat(392)] {
        NSBezierPath(roundedRect: NSRect(x: 500, y: y, width: 264, height: 105), xRadius: 18, yRadius: 18).fill()
    }
    NSBezierPath(roundedRect: NSRect(x: 458, y: 264, width: 108, height: 85), xRadius: 14, yRadius: 14).fill()
    NSBezierPath(roundedRect: NSRect(x: 360, y: 245, width: 304, height: 33), xRadius: 16, yRadius: 16).fill()
    color(0x182b63).setFill()
    NSBezierPath(ovalIn: NSRect(x: 652, y: 180, width: 252, height: 252)).fill()
    color(0x58dcaa).setFill()
    NSBezierPath(ovalIn: NSRect(x: 668, y: 196, width: 220, height: 220)).fill()
    let check = NSBezierPath()
    check.move(to: NSPoint(x: 716, y: 310)); check.line(to: NSPoint(x: 757, y: 268)); check.line(to: NSPoint(x: 841, y: 352))
    check.lineWidth = 27; check.lineCapStyle = .round; check.lineJoinStyle = .round
    color(0x123a3a).setStroke(); check.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try render(points * scale).write(to: destination.appendingPathComponent(name))
    }
}
