import AppKit
import ImageIO
import SwiftUI
import MacSetupCore

struct WorkspaceBarPreview: View {
    let layout: WorkspaceConfiguration
    let mixed: Bool
    let time: String
    let engine: Engine
    @ObservedObject var backdrop: PreviewWallpaper
    @LocalViewState private var seed = UInt64.random(in: 0...UInt64.max)

    var body: some View {
        let sample = BarPreviewSample(ids: layout.workspaces.map(\.id), mixed: mixed, seed: seed)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SKETCHYBAR PREVIEW").font(SetupDesign.caption.weight(.semibold))
                Spacer()
                if mixed { Button("Shuffle sample") { seed = .random(in: 0...UInt64.max) }.buttonStyle(.borderless) }
            }.foregroundStyle(.secondary)
            GeometryReader { proxy in
                canvas(sample: sample, width: proxy.size.width)
            }
            .frame(height: backdrop.barHeight)
            .clipped()
            HStack(alignment: .top) {
                Text(mixed ? "Sample windows: occupied, empty and one focused." : "All workspaces occupied; none focused.")
                Spacer()
                Text("\(Int(backdrop.barHeight)) pt bar height")
            }.font(SetupDesign.caption).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(backdrop.exactImage ? "Top edge of the available wallpaper image. Live wallpapers and macOS blur may differ." :
                        backdrop.loading ? "Loading the wallpaper image…" : "Wallpaper image unavailable; preview uses the desktop background color.")
                    .font(SetupDesign.caption).foregroundStyle(.secondary)
                if !backdrop.exactImage && !backdrop.loading {
                    Spacer()
                    Button("Choose wallpaper image") { backdrop.chooseImage(engine: engine) }.buttonStyle(.borderless)
                }
            }
        }
        .onAppear { backdrop.refresh(engine: engine) }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in backdrop.refresh(engine: engine) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in backdrop.refresh(engine: engine, force: true) }
    }

    private func canvas(sample: BarPreviewSample, width: CGFloat) -> some View {
        let style = layout.barStyle
        return ZStack(alignment: .topLeading) {
            wallpaper(width: width)
                .frame(height: backdrop.barHeight, alignment: .top).clipped()
            wallpaper(width: width).blur(radius: CGFloat(style.blurRadius))
                .frame(height: backdrop.barHeight, alignment: .top).clipped()
            Rectangle().fill(WorkspaceColor.swiftUI(style.backgroundColor)).frame(height: backdrop.barHeight)
            HStack(spacing: 0) {
                ForEach(layout.workspaces, id: \.id) { workspace in
                    Text(workspace.resolvedIcon.symbol)
                        .font(.custom(workspace.resolvedIcon.font.postScriptName, size: 14.5))
                        .foregroundStyle(workspace.id == sample.focusedID ? backdrop.accent :
                            WorkspaceColor.swiftUI(sample.occupiedIDs.contains(workspace.id) ? style.occupiedColor : style.emptyColor))
                        .frame(width: CGFloat(style.itemWidth), height: backdrop.barHeight)
                        .accessibilityLabel(workspace.name + (workspace.id == sample.focusedID ? ": focused" : sample.occupiedIDs.contains(workspace.id) ? ": occupied" : ": empty"))
                }
                Spacer(minLength: 0)
                Text(time).font(.custom("HackNFM-Bold", size: 14))
                    .foregroundStyle(WorkspaceColor.swiftUI(style.occupiedColor))

            }
            .padding(.horizontal, 20)
            .frame(width: width, height: backdrop.barHeight)
        }
        .frame(width: width, height: backdrop.barHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func wallpaper(width: CGFloat) -> some View {
        if let image = backdrop.strip {
            Image(decorative: image, scale: 2).resizable().interpolation(.high)
                .frame(width: width, height: 340, alignment: .topLeading)
                .accessibilityHidden(true)
        } else {
            backdrop.fill.frame(width: width, height: 340)
        }
    }
}

final class PreviewWallpaper: ObservableObject {
    @Published var strip: CGImage?
    @Published var exactImage = false
    @Published var fill = Color.black
    @Published var accent = WorkspaceColor.swiftUI("0xff7873b6")
    @Published var screenSize = CGSize(width: 1680, height: 1050)
    @Published var barHeight: CGFloat = 30
    @Published var loading = false
    private var fingerprint = ""
    private var requestID = UUID()
    private var inFlight = false
    private var chosenURL: URL?

    func chooseImage(engine: Engine) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the image to use behind the bar preview. This does not change your wallpaper."
        if panel.runModal() == .OK, let url = panel.url {
            chosenURL = url
            refresh(engine: engine, force: true)
        }
    }

    func refresh(engine: Engine, force: Bool = false) {
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        let geometry = DisplayGeometry.current()
        barHeight = CGFloat(geometry.displays.first { $0.name == screen.localizedName }?.height ?? geometry.previewHeight)
        screenSize = screen.frame.size
        let service = DesktopAccentService(engine: engine)
        if let rgb = service.currentColor() { accent = WorkspaceColor.swiftUI("0xff" + rgb.replacingOccurrences(of: "#", with: "")) }
        let url = chosenURL ?? NSWorkspace.shared.desktopImageURL(for: screen)
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let fillColor = options[.fillColor] as? NSColor ?? .black
        fill = Color(nsColor: fillColor)
        let scaling = (options[.imageScaling] as? NSNumber)?.uintValue ?? NSImageScaling.scaleProportionallyUpOrDown.rawValue
        let clipping = options[.allowClipping] as? Bool ?? false
        guard let url else { strip = nil; exactImage = false; return }
        guard !inFlight || force else { return }
        inFlight = true
        let request = UUID(), oldFingerprint = fingerprint, size = screenSize
        let background = (fillColor.usingColorSpace(.sRGB) ?? .black).cgColor
        requestID = request
        loading = strip == nil
        // File access can wait for a cloud download or macOS file permission.
        // Never let ImageIO's synchronous open block navigation or editing.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let stamp = "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)|\(size)|\(scaling)|\(clipping)|\(background.components ?? [])"
            if !force && stamp == oldFingerprint {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.requestID == request else { return }
                    self.inFlight = false; self.loading = false
                }
                return
            }
            let image = Self.render(url: url, screenSize: size, scaling: scaling, clipping: clipping, background: background)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestID == request else { return }
                if image != nil { self.fingerprint = stamp }
                self.inFlight = false; self.loading = false
                self.strip = image; self.exactImage = image != nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.requestID == request, self.inFlight else { return }
            self.loading = false
        }
    }

    private static func render(url: URL, screenSize: CGSize, scaling: UInt, clipping: Bool, background: CGColor) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let originalWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(cg.width)
        let originalHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(cg.height)
        let originalScale = max(originalWidth, originalHeight) / Double(max(cg.width, cg.height))
        let image = NSImage(cgImage: cg, size: CGSize(width: Double(cg.width) * originalScale, height: Double(cg.height) * originalScale))
        let rect = WallpaperPreviewGeometry.imageRect(image: image.size, screen: screenSize, fill: clipping,
            stretch: scaling == NSImageScaling.scaleAxesIndependently.rawValue,
            actualSize: scaling == NSImageScaling.scaleNone.rawValue)
        let size = CGSize(width: screenSize.width, height: 340)
        guard let context = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.scaleBy(x: 2, y: 2)
        context.setFillColor(background)
        context.fill(CGRect(origin: .zero, size: size))
        context.interpolationQuality = .high
        // Convert the top-left desktop rectangle into bitmap coordinates.
        context.draw(cg, in: CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height))
        return context.makeImage()
    }
}
