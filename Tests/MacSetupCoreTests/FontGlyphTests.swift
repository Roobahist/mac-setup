import XCTest
import CoreText
@testable import MacSetupCore

final class FontGlyphTests: XCTestCase {
    private var font: GlyphFont { GlyphFont(CTFontCreateWithName("Helvetica" as CFString, 14.5, nil)) }

    func testCatalogUsesRealFontCoverageAndEmbeddedNames() throws {
        let glyphs = try FontGlyphCatalog.glyphs(in: font)
        let a = try XCTUnwrap(glyphs.first { $0.symbol == "A" })
        let native = CTFontCreateWithName(font.postScriptName as CFString, 14.5, nil)
        var glyph: CGGlyph = 0
        var character: UniChar = 65
        XCTAssertTrue(CTFontGetGlyphsForCharacters(native, &character, &glyph, 1))
        XCTAssertEqual(a.glyphName, CTFontCopyNameForGlyph(native, glyph) as String?)
        XCTAssertEqual(a.selection.font, font)
        XCTAssertFalse(glyphs.contains { $0.symbol == "\n" || $0.symbol == " " })
        XCTAssertTrue(FontGlyphCatalog.matching(glyphs, query: "latin capital letter a").contains { $0.symbol == "A" })
        XCTAssertEqual(FontGlyphCatalog.matching(glyphs, query: "U+0041").first?.symbol, "A")
        XCTAssertEqual(FontGlyphCatalog.matching(glyphs, query: "0x0041").first?.symbol, "A")
    }

    func testSupplementaryCharactersAndMissingNamesAreSearchable() {
        let icon = FontGlyph(selection: .init(font: font, symbol: "􀴽"), glyphName: nil, unicodeName: nil)
        XCTAssertEqual(icon.name, "U+100D3D")
        XCTAssertTrue(icon.matches("100D3D"))
        XCTAssertTrue(icon.matches("􀴽"))
        XCTAssertFalse(icon.matches("robot"))
        let robot = FontGlyph(selection: .init(font: font, symbol: "󰚩"), glyphName: "md-robot", unicodeName: nil)
        XCTAssertTrue(robot.matches("md robot"))
        XCTAssertTrue(robot.matches("ROBOT"))
        XCTAssertEqual(FontGlyphCatalog.matching([icon, robot], query: "", iconsOnly: true).count, 2)
    }

    func testUnavailableFontIsRejectedInsteadOfEnumeratingFallback() {
        let missing = GlyphFont(postScriptName: "MacSetupTestMissingFont-123", family: "Missing", style: "Regular")
        XCTAssertThrowsError(try FontGlyphCatalog.glyphs(in: missing))
        XCTAssertNil(FontGlyphCatalog.metadata(.init(font: missing, symbol: "A")))
    }

    func testNewGlyphSelectionPersistsAndOldLayoutsKeepTheirAppearance() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        var config = WorkspaceConfiguration.defaultLayout
        XCTAssertEqual(config.workspaces[0].resolvedIcon.symbol, "􀴽")
        XCTAssertEqual(config.workspaces[0].resolvedIcon.font.family, "SF Pro")
        config.workspaces[0].icon = .init(font: font, symbol: "A")
        try config.save(to: paths)
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths), config)
        let json = Data("""
        {"workspaces":[{"id":"ai","name":"AI","glyph":"robot","apps":[]}]}
        """.utf8)
        let old = try JSONDecoder().decode(WorkspaceConfiguration.self, from: json)
        XCTAssertNil(old.workspaces[0].icon)
        XCTAssertEqual(old.workspaces[0].resolvedIcon.symbol, "􀴽")
    }

    func testChosenFontAndQuotedCharactersAreEmittedSafely() throws {
        var config = WorkspaceConfiguration.defaultLayout
        let choice = FontGlyphSelection(font: .init(postScriptName: "Sample-Regular", family: "Sample's Font", style: "Regular"), symbol: "'")
        config.workspaces[0].icon = choice
        let template = try String(contentsOf: Paths().profile.appendingPathComponent("sketchybar/sketchybarrc"), encoding: .utf8)
        let output = try config.sketchybarShell(from: template)
        let start = try XCTUnwrap(output.range(of: "workspace_icon() {"))
        let end = try XCTUnwrap(output.range(of: "##### AeroSpace Workspaces #####", range: start.lowerBound..<output.endIndex))
        let functions = String(output[start.lowerBound..<end.lowerBound])
        let result = try ProcessRunner().checked("/bin/bash", ["-c", functions + "\nworkspace_icon chatgpt\nworkspace_font chatgpt"])
        XCTAssertEqual(result.text, "'\nSample's Font:Regular:14.5")
    }

    func testInvalidGlyphOrFontCannotBecomeShellConfiguration() {
        for symbol in ["", "AB", "\n", " "] {
            XCTAssertThrowsError(try FontGlyphSelection(font: font, symbol: symbol).validate())
        }
        let bad = GlyphFont(postScriptName: "Test", family: "Font:Bad", style: "Regular")
        XCTAssertThrowsError(try FontGlyphSelection(font: bad, symbol: "A").validate())
    }

    func testDragOrderPreservesHiddenWorkspacesIconsAndCustomShortcuts() throws {
        var config = WorkspaceConfiguration.defaultLayout
        let research = WorkspaceDefinition(id: "research", name: "Research", glyph: "book",
            shortcuts: .init(switchTo: .init(key: "r", modifiers: ["ctrl", "alt"])), icon: .init(font: font, symbol: "R"))
        config.workspaces.append(research)
        config.moveWorkspace("research", to: "chatgpt", selectedTasks: ["aerospace-profile"])
        XCTAssertEqual(config.workspaces.first, research)
        XCTAssertEqual(config.workspaces[12].id, "timer", "Hidden optional workspaces keep their saved position")
        XCTAssertEqual(config.forSelectedTasks(["aerospace-profile"]).workspaces.last?.id, "notes")
        XCTAssertEqual(config.shortcuts(at: 0).switchTo?.binding, "ctrl-alt-r")
        try config.validate()
        let before = config
        config.moveWorkspace("research", to: "timer", selectedTasks: ["aerospace-profile"])
        config.moveWorkspace("not-present", to: "research")
        XCTAssertEqual(config, before)
        config.moveWorkspace("research", to: "notes", selectedTasks: ["aerospace-profile"])
        XCTAssertEqual(config.forSelectedTasks(["aerospace-profile"]).workspaces.last, research)
    }
}
