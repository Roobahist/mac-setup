import Foundation
import CoreGraphics

/// Sample state stays attached to workspace identities when cards are reordered.
public struct BarPreviewSample {
    public let focusedID: String?
    public let occupiedIDs: Set<String>

    public init(ids: [String], mixed: Bool, seed: UInt64) {
        guard mixed else { focusedID = nil; occupiedIDs = Set(ids); return }
        var random = PreviewRandom(state: seed)
        let shuffled = ids.sorted().shuffled(using: &random)
        focusedID = shuffled.first
        occupiedIDs = Set(shuffled.enumerated().compactMap { index, id in index == 0 || index % 2 == 0 ? id : nil })
    }
}

private struct PreviewRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Top-left drawing coordinates for the image as macOS places it on the desktop.
public enum WallpaperPreviewGeometry {
    public static func imageRect(image: CGSize, screen: CGSize, fill: Bool, stretch: Bool = false, actualSize: Bool = false) -> CGRect {
        guard image.width > 0, image.height > 0, screen.width > 0, screen.height > 0 else { return .zero }
        if stretch { return CGRect(origin: .zero, size: screen) }
        let ratios = [screen.width / image.width, screen.height / image.height]
        let scale = actualSize ? 1 : (fill ? ratios.max()! : ratios.min()!)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (screen.width - size.width) / 2, y: (screen.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
