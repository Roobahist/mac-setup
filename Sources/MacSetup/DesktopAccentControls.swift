import AppKit
import SwiftUI
import MacSetupCore

struct DesktopAccentControls: View {
    let engine: Engine
    @LocalViewState private var watcherEnabled = false
    @LocalViewState private var selectedColor = Color.purple
    @LocalViewState private var working = false
    @LocalViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Desktop accent").font(.headline)
            Text("Choose whether SketchyBar follows your wallpaper or uses your own highlight color.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("Match wallpaper automatically", isOn: Binding(
                get: { watcherEnabled },
                set: { updateWatcher($0) }))
                .disabled(working)
            HStack {
                ColorPicker("Manual highlight color", selection: $selectedColor, supportsOpacity: false)
                    .disabled(watcherEnabled || working)
                Button("Apply color") { applyColor() }
                    .disabled(watcherEnabled || working)
            }
            if watcherEnabled {
                Text("Turn off automatic updates to choose a fixed color.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .onAppear(perform: reload)
    }

    private func reload() {
        let service = DesktopAccentService(engine: engine)
        watcherEnabled = (try? service.watcherIsRunning()) ?? false
        if let hex = service.currentColor(), let value = Int(hex, radix: 16) {
            selectedColor = Color(red: Double((value >> 16) & 255) / 255,
                                  green: Double((value >> 8) & 255) / 255,
                                  blue: Double(value & 255) / 255)
        }
    }

    private func updateWatcher(_ enabled: Bool) {
        working = true
        let service = DesktopAccentService(engine: engine)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try service.setWatcherEnabled(enabled) }
            DispatchQueue.main.async {
                working = false
                reload()
                switch result {
                case .success: status = enabled ? "Wallpaper watcher enabled." : "Wallpaper watcher disabled."
                case .failure(let error): status = "Could not change watcher: \(error)"
                }
            }
        }
    }

    private func applyColor() {
        let rgb = NSColor(selectedColor).usingColorSpace(.deviceRGB)
        guard let rgb else { status = "Unable to convert this color."; return }
        let value = String(format: "%02X%02X%02X",
                           Int((rgb.redComponent * 255).rounded()),
                           Int((rgb.greenComponent * 255).rounded()),
                           Int((rgb.blueComponent * 255).rounded()))
        working = true
        let service = DesktopAccentService(engine: engine)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try service.setManualColor(value) }
            DispatchQueue.main.async {
                working = false
                switch result {
                case .success: status = "Accent applied. A recovery record was saved."
                case .failure(let error): status = "Could not apply color: \(error)"
                }
            }
        }
    }
}

