import SwiftUI
import MacSetupCore

struct WorkspaceColorControl: View {
    let title: String
    @Binding var hex: String
    @LocalViewState private var rgbDraft = ""
    @LocalViewState private var invalid = false
    @FocusState private var editing: Bool

    private var color: BarColor { BarColor(hex) ?? BarColor("0xffffffff")! }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).fontWeight(.medium)
            HStack(spacing: 8) {
                ColorPicker(title + " color", selection: Binding(
                    get: { WorkspaceColor.swiftUI(color.opaque.hex) },
                    set: { selected in
                        if let rgb = BarColor(WorkspaceColor.argb(selected)),
                           let updated = color.replacingRGB(rgb.rgbHex) {
                            hex = updated.hex
                        }
                    }), supportsOpacity: false)
                    .labelsHidden()
                TextField("#RRGGBB", text: $rgbDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($editing).onSubmit(commitRGB)
                    .accessibilityLabel(title + " RGB color")
            }
            HStack {
                Text("Opacity").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((color.opacity * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { color.opacity * 100 },
                                  set: { hex = color.replacingOpacity($0 / 100).hex }),
                   in: 0...100, step: 1)
                .accessibilityLabel(title + " opacity")
            if invalid {
                Text("Enter six hexadecimal digits, for example #000000.")
                    .font(SetupDesign.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { rgbDraft = color.rgbHex }
        .onChange(of: hex) { _ in
            if !editing { rgbDraft = color.rgbHex; invalid = false }
        }
        .onChange(of: editing) { focused in if !focused { commitRGB() } }
    }

    private func commitRGB() {
        guard let updated = color.replacingRGB(rgbDraft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            invalid = true
            return
        }
        hex = updated.hex
        rgbDraft = updated.rgbHex
        invalid = false
    }
}
