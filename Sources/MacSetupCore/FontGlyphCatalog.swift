import Foundation
import CoreText

public struct GlyphFont: Codable, Equatable, Hashable, Identifiable {
    public var postScriptName: String
    public var family: String
    public var style: String
    public var id: String { postScriptName }
    public var title: String { "\(family) · \(style)" }
    public var sketchybarFont: String { "\(family):\(style):14.5" }

    public init(postScriptName: String, family: String, style: String) {
        self.postScriptName = postScriptName; self.family = family; self.style = style
    }

    init(_ font: CTFont) {
        postScriptName = CTFontCopyPostScriptName(font) as String
        family = CTFontCopyFamilyName(font) as String
        style = (CTFontCopyName(font, kCTFontStyleNameKey) as String?) ?? "Regular"
    }

    public func validate() throws {
        for name in [postScriptName, family, style] {
            guard !name.isEmpty, name.count <= 254, !name.contains(":"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SetupError("Font names must be nonempty and cannot contain colons or control characters.")
            }
        }
    }
}

public struct FontGlyphSelection: Codable, Equatable {
    public var font: GlyphFont
    public var symbol: String

    public init(font: GlyphFont, symbol: String) { self.font = font; self.symbol = symbol }

    public func validate() throws {
        try font.validate()
        guard symbol.unicodeScalars.count == 1, let scalar = symbol.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
            throw SetupError("Choose one visible Unicode character from the font.")
        }
    }

    public var codePoint: String {
        symbol.unicodeScalars.first.map { String(format: "U+%04X", $0.value) } ?? ""
    }
}

public struct FontGlyph: Identifiable, Equatable {
    public let selection: FontGlyphSelection
    public let glyphName: String?
    public let unicodeName: String?
    public let id: String
    private let searchText: String
    public var name: String { glyphName ?? unicodeName ?? id }
    public var symbol: String { selection.symbol }
    public var isIcon: Bool {
        guard let scalar = symbol.unicodeScalars.first else { return false }
        return scalar.properties.generalCategory == .privateUse || scalar.properties.generalCategory == .otherSymbol
    }

    public init(selection: FontGlyphSelection, glyphName: String?, unicodeName: String?) {
        self.selection = selection; self.glyphName = glyphName; self.unicodeName = unicodeName
        id = selection.codePoint
        searchText = "\(glyphName ?? "") \(unicodeName ?? "") \(selection.codePoint)".lowercased()
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    public func matches(_ query: String) -> Bool {
        matches(GlyphSearch(query))
    }

    fileprivate func matches(_ search: GlyphSearch) -> Bool {
        search.query.isEmpty || search.query == symbol || search.codePoint == symbol.unicodeScalars.first?.value
            || search.words.allSatisfy { searchText.contains($0) }
    }
}

fileprivate struct GlyphSearch {
    let query: String
    let codePoint: UInt32?
    let words: [Substring]
    init(_ query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = self.query.lowercased()
        codePoint = UInt32(lower.replacingOccurrences(of: "u+", with: "").replacingOccurrences(of: "0x", with: ""), radix: 16)
        words = lower.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
    }
}

/// Reads installed faces, Unicode coverage and glyph names through Core Text.
/// No curated icon aliases or assumed font versions are used in the picker.
public enum FontGlyphCatalog {
    public static func matching(_ glyphs: [FontGlyph], query: String, iconsOnly: Bool = false) -> [FontGlyph] {
        let search = GlyphSearch(query)
        return glyphs.filter { (!iconsOnly || $0.isIcon) && $0.matches(search) }
    }
    public static func fonts() -> [GlyphFont] {
        let names = CTFontManagerCopyAvailablePostScriptNames() as! [String]
        return names.compactMap { name in
            let font = GlyphFont(CTFontCreateWithName(name as CFString, 14.5, nil))
            return (try? font.validate()) == nil ? nil : font
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public static func metadata(_ selection: FontGlyphSelection) -> FontGlyph? {
        guard let scalar = selection.symbol.unicodeScalars.first,
              let font = resolvedFont(selection.font) else { return nil }
        return entry(scalar, font: font, face: selection.font)
    }

    private static func resolvedFont(_ face: GlyphFont) -> CTFont? {
        let font = CTFontCreateWithName(face.postScriptName as CFString, 14.5, nil)
        // Never enumerate Helvetica or another fallback under the requested font's name.
        guard CTFontCopyPostScriptName(font) as String == face.postScriptName else { return nil }
        return font
    }

    private static func entry(_ scalar: Unicode.Scalar, font: CTFont, face: GlyphFont) -> FontGlyph? {
        let selection = FontGlyphSelection(font: face, symbol: String(scalar))
        guard (try? selection.validate()) != nil else { return nil }
        let characters = Array(selection.symbol.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count),
              let glyph = glyphs.first, glyph != 0 else { return nil }
        let name = CTFontCopyNameForGlyph(font, glyph) as String?
        return FontGlyph(selection: selection, glyphName: name == ".notdef" ? nil : name,
                         unicodeName: scalar.properties.name)
    }

    public static func glyphs(in face: GlyphFont) throws -> [FontGlyph] {
        guard let font = resolvedFont(face) else { throw SetupError("\(face.title) is not installed. Choose an installed font.") }
        let characters = CTFontCopyCharacterSet(font)
        var result: [FontGlyph] = []
        for plane in 0...16 where CFCharacterSetHasMemberInPlane(characters, plane) {
            let start = UInt32(plane) << 16
            for value in start..<(start + 65536) where CFCharacterSetIsLongCharacterMember(characters, value) {
                if let scalar = Unicode.Scalar(value), let glyph = entry(scalar, font: font, face: face) {
                    result.append(glyph)
                }
            }
        }
        return result
    }
}
