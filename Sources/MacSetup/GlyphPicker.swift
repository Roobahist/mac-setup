import SwiftUI
import MacSetupCore

// Keep the property wrapper available to source builds using Command Line Tools.
private typealias PickerStateObject<Object: ObservableObject> = SwiftUI.StateObject<Object>

private final class GlyphPickerModel: ObservableObject {
    @Published var fonts: [GlyphFont] = []
    @Published var font: GlyphFont?
    @Published var glyphs: [FontGlyph] = []
    @Published var selected: FontGlyph?
    @Published var search = ""
    @Published var fontSearch = ""
    @Published var iconsOnly = false
    @Published var busy = true
    @Published var error = ""
    @Published var notice = ""
    private let original: FontGlyphSelection
    private let worker = DispatchQueue(label: "mac-setup.font-glyphs", qos: .userInitiated)
    private var cache: [String: [FontGlyph]] = [:]

    init(selection: FontGlyphSelection) {
        original = selection
        worker.async {
            let fonts = FontGlyphCatalog.fonts()
            DispatchQueue.main.async {
                self.fonts = fonts
                if let initial = fonts.first(where: { $0.id == selection.font.id }) {
                    self.chooseFont(initial)
                } else if let initial = fonts.first(where: { $0.family == "Hack Nerd Font" && $0.style == "Bold" }) ?? fonts.first {
                    self.notice = "The current font \(selection.font.title) is not installed. Choose a glyph from another installed font."
                    self.chooseFont(initial)
                } else { self.busy = false; self.error = "No installed fonts could be loaded." }
            }
        }
    }

    var matchingFonts: [GlyphFont] {
        let words = fontSearch.split(whereSeparator: \.isWhitespace)
        return fonts.filter { font in words.allSatisfy { font.title.localizedCaseInsensitiveContains($0) || font.id.localizedCaseInsensitiveContains($0) } }
    }

    var matches: [FontGlyph] { FontGlyphCatalog.matching(glyphs, query: search, iconsOnly: iconsOnly) }

    func chooseFont(_ choice: GlyphFont) {
        font = choice; selected = nil; glyphs = []; busy = true; error = ""
        worker.async {
            do {
                let glyphs: [FontGlyph]
                if let cached = self.cache[choice.id] { glyphs = cached }
                else { glyphs = try FontGlyphCatalog.glyphs(in: choice); self.cache[choice.id] = glyphs }
                DispatchQueue.main.async {
                    guard self.font?.id == choice.id else { return }
                    self.glyphs = glyphs; self.busy = false
                    if choice == self.original.font {
                        self.selected = glyphs.first { $0.symbol == self.original.symbol }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.font?.id == choice.id else { return }
                    self.error = String(describing: error); self.busy = false
                }
            }
        }
    }
}

struct GlyphPicker: View {
    let workspaceName: String
    let save: (FontGlyphSelection) -> Void
    @Environment(\.dismiss) private var dismiss
    @PickerStateObject private var model: GlyphPickerModel

    init(workspace: WorkspaceDefinition, save: @escaping (FontGlyphSelection) -> Void) {
        workspaceName = workspace.name; self.save = save
        _model = PickerStateObject(wrappedValue: GlyphPickerModel(selection: workspace.resolvedIcon))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Glyph for \(workspaceName)").font(SetupDesign.sheetTitle)
            Text("Browse installed fonts. Search the font's glyph names, Unicode names or code points, or paste a character.").foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Font").fontWeight(.medium)
                    TextField("Find a font", text: $model.fontSearch).textFieldStyle(.roundedBorder)
                    List(model.matchingFonts) { font in
                        Button { model.chooseFont(font) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(font.family).lineLimit(1)
                                Text(font.style).font(.system(size: 12)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                             .background(model.font?.id == font.id ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).accessibilityLabel("Font: \(font.title)")
                    }
                }.frame(width: 220)
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.font?.title ?? "Loading fonts…").fontWeight(.medium)
                    TextField("Search glyphs or paste a character", text: $model.search).textFieldStyle(.roundedBorder)
                    HStack {
                        Toggle("Icons and symbols only", isOn: $model.iconsOnly).toggleStyle(.checkbox)
                        Spacer()
                        Text("\(model.matches.count) of \(model.glyphs.count)").foregroundStyle(.secondary)
                    }
                    if model.busy { ProgressView("Reading font glyphs…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                                ForEach(model.matches) { glyph in
                                    Button { model.selected = glyph } label: {
                                        VStack(spacing: 6) {
                                            Text(glyph.symbol).font(.custom(glyph.selection.font.postScriptName, size: 28)).frame(height: 38)
                                            Text(glyph.name).font(.system(size: 12)).lineLimit(1)
                                            Text(glyph.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity).padding(8)
                                         .background(model.selected?.id == glyph.id ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain).help("\(glyph.name) · \(glyph.id)\n\(glyph.unicodeName ?? "No Unicode name")")
                                     .accessibilityLabel("\(glyph.name), \(glyph.id)")
                                }
                            }.padding(4)
                        }.id(model.font?.id)
                        if model.matches.isEmpty && model.error.isEmpty {
                            Text("No matching glyphs. Try another name or code point, or turn off the symbols filter.").foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity)
            }.frame(maxHeight: .infinity)
            if !model.notice.isEmpty { Text(model.notice).font(.system(size: 13)).foregroundStyle(.secondary) }
            if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
            Divider()
            HStack {
                if let glyph = model.selected {
                    Text(glyph.symbol).font(.custom(glyph.selection.font.postScriptName, size: 36)).frame(width: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(glyph.name).lineLimit(1)
                        Text("\(glyph.id) · \(glyph.selection.font.title)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else { Text("Select a glyph to use in this workspace.").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use glyph") {
                    guard let glyph = model.selected else { return }
                    save(glyph.selection); dismiss()
                }.disabled(model.selected == nil || model.busy).keyboardShortcut(.defaultAction)
            }
            Text("Names come from the font and Unicode. Some fonts provide internal code names rather than descriptions. Only characters with a Unicode mapping can be used in the bar.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(24).font(SetupDesign.body).frame(width: 760, height: 640)
    }
}
