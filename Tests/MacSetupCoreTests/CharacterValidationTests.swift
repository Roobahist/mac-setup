import XCTest
@testable import MacSetupCore

/// These must run under -O as well as -Onone. A bound CharacterSet.contains
/// reference produced false ID failures in optimized builds on the tested SDK.
final class CharacterValidationTests: XCTestCase {
    func testValidWorkspaceAndBundleIDsSurviveOptimizedValidation() throws {
        for id in ["ai", "chatgpt", "AI_2", "notes-2"] {
            let layout = WorkspaceConfiguration(workspaces: [
                .init(id: id, name: "Research", glyph: "book", apps: ["com.example.App-2"])
            ])
            XCTAssertNoThrow(try layout.validate(), id)
        }
    }

    func testUnsafeWorkspaceAndBundleIDsAreStillRejected() {
        for id in ["with spaces", "bad;command", "bad/name", "bad\nname", ""] {
            let layout = WorkspaceConfiguration(workspaces: [.init(id: id, name: "Test", glyph: "book")])
            XCTAssertThrowsError(try layout.validate(), id)
        }
        let layout = WorkspaceConfiguration(workspaces: [.init(id: "safe", name: "Test", glyph: "book", apps: ["bad app"] )])
        XCTAssertThrowsError(try layout.validate())
    }

    func testSafeFontsAndUnicodeLabelsAreAcceptedAndControlsRejected() throws {
        for family in ["SF Pro", "Hack Nerd Font", "Helvetica"] {
            let font = GlyphFont(postScriptName: "Safe-Regular", family: family, style: "Regular")
            XCTAssertNoThrow(try font.validate())
        }
        var layout = WorkspaceConfiguration.defaultLayout
        XCTAssertNoThrow(try layout.renameWorkspace("ai", to: "Research"))
        XCTAssertNoThrow(try layout.renameWorkspace("research", to: "مطالعه"))
        XCTAssertThrowsError(try layout.renameWorkspace(layout.workspaces[0].id, to: "bad\nname"))
        XCTAssertThrowsError(try GlyphFont(postScriptName: "Safe", family: "bad:font", style: "Regular").validate())
        XCTAssertThrowsError(try GlyphFont(postScriptName: "Safe", family: "bad\nfont", style: "Regular").validate())
    }
}
