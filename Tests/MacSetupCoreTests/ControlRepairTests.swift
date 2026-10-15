import XCTest
@testable import MacSetupCore

final class ControlRepairTests: XCTestCase {
    func testBundledApplicationShortcutsResolveEveryIconTarget() {
        let targets = ["Alacritty": "org.alacritty", "Visual Studio Code": "com.microsoft.VSCode",
                       "Finder": "com.apple.finder", "Telegram": "ru.keepcoder.Telegram",
                       "WhatsApp": "net.whatsapp.WhatsApp"]
        XCTAssertEqual(Set(ShortcutSettings.scripts.map(\.name)), Set(targets.keys))
        for (action, bundleID) in targets {
            let shortcut = ManagedShortcut(provider: .karabiner, action: action, shortcut: .init(key: "t", modifiers: ["alt"]))
            XCTAssertEqual(shortcut.applicationBundleID, bundleID)
        }
        let custom = ManagedShortcut(provider: .karabiner, action: "open:com.apple.Safari", shortcut: .init(key: "s", modifiers: ["alt"]))
        XCTAssertEqual(custom.applicationBundleID, "com.apple.Safari")
    }

    func testRGBAndOpacityEditsPreserveTheOtherChannel() throws {
        let empty = try XCTUnwrap(BarColor("0x30000000"))
        XCTAssertEqual(empty.rgbHex, "#000000")
        XCTAssertEqual(Int((empty.opacity * 100).rounded()), 19)
        XCTAssertEqual(empty.replacingRGB("#21a4ff")?.hex, "0x3021a4ff")
        XCTAssertEqual(empty.replacingOpacity(1).hex, "0xff000000")
        let background = try XCTUnwrap(BarColor("0x35aabbcc"))
        XCTAssertEqual(background.replacingOpacity(0).hex, "0x00aabbcc")
        XCTAssertEqual(background.replacingOpacity(0.5).hex, "0x80aabbcc")
        XCTAssertEqual(background.replacingOpacity(2).hex, "0xffaabbcc")
        XCTAssertNil(background.replacingRGB("#gg0000"))
        XCTAssertNil(background.replacingRGB("#abc"))
        XCTAssertNil(BarColor("0x000000"))
    }

    func testNativeMenuHeightWinsOverGenericStatusThickness() {
        let display = DisplayMetrics(name: "Scaled", statusThickness: 22, safeTop: 0, menuBarHeight: 30)
        XCTAssertEqual(display.height, 30)
        XCTAssertEqual(display.gap, 32)
        let notch = DisplayMetrics(name: "Notched", statusThickness: 22, safeTop: 38, menuBarHeight: 30)
        XCTAssertEqual(notch.height, 38)
        XCTAssertEqual(notch.gap, 2)
    }

    func testRefreshRepairsWholeBarWhenGapIsAlreadyCorrect() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("aerospace.toml")
        let geometry = DisplayGeometry(displays: [.init(name: "Display", statusThickness: 22, safeTop: 0, menuBarHeight: 30)])
        let text = "[gaps]\n" + geometry.gapLine + "\nouter.left = 2\n"
        try text.write(to: config, atomically: true, encoding: .utf8)
        let runner = FakeRunner()
        try geometry.refresh(config: config, runner: runner, sketchybar: "/fake/sketchybar", aerospace: "/fake/aerospace")
        XCTAssertTrue(runner.calls.contains { $0.contains("height=30") && $0.contains("--bar") })
        XCTAssertFalse(runner.calls.contains { $0.contains("reload-config") })
        XCTAssertEqual(try String(contentsOf: config), text)
        runner.calls = []
        XCTAssertThrowsError(try DisplayGeometry(displays: []).refresh(config: config, runner: runner, sketchybar: "/fake/sketchybar", aerospace: nil))
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testRefreshUpdatesOnlyOwnedGapsAndProtectsLinkedFiles() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("aerospace.toml")
        let geometry = DisplayGeometry(displays: [.init(name: "Display", statusThickness: 22, safeTop: 0, menuBarHeight: 30)])
        let text = "[gaps]\nouter.top = 24 \(DisplayGeometry.marker)\nouter.left = 2\n"
        try text.write(to: config, atomically: true, encoding: .utf8)
        let runner = FakeRunner()
        try geometry.refresh(config: config, runner: runner, sketchybar: "/fake/sketchybar", aerospace: "/fake/aerospace")
        XCTAssertEqual(try String(contentsOf: config), geometry.applying(to: text))
        XCTAssertTrue(runner.calls.contains { $0.contains("reload-config") })
        let link = root.appendingPathComponent("linked.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: config)
        XCTAssertThrowsError(try geometry.refresh(config: link, runner: runner, sketchybar: "/fake/sketchybar", aerospace: nil))
        let personal = "[gaps]\nouter.top = 99\n"
        try personal.write(to: config, atomically: true, encoding: .utf8)
        try geometry.refresh(config: config, runner: runner, sketchybar: "/fake/sketchybar", aerospace: nil)
        XCTAssertEqual(try String(contentsOf: config), personal)
    }
    func testGeneratedBarUsesMeasurementsAndKeepsSourceHeightOnHelperFailure() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "".write(to: root.appendingPathComponent("colors.sh"), atomically: true, encoding: .utf8)
        try "exit 0\n".write(to: root.appendingPathComponent("geometry.sh"), atomically: true, encoding: .utf8)
        let helper = root.appendingPathComponent("mac-setup-display")
        let script = root.appendingPathComponent("sketchybarrc")
        let raw = """
        PLUGIN_DIR="\(root.path)"
        sketchybar() { printf '%s\\n' "$@"; }
        source "$PLUGIN_DIR/colors.sh"
        sketchybar --bar \\
          height=30 \\
          topmost=off
        """
        let generated = DisplayGeometry.barShell(raw)
        XCTAssertEqual(DisplayGeometry.barShell(generated), generated)
        try generated.write(to: script, atomically: true, encoding: .utf8)
        for (body, expected) in [("echo '34 38'", "height=34"), ("exit 1", "height=30"),
                                 ("echo 'invalid 0'", "height=30")] {
            try ("#!/bin/bash\n" + body + "\n").write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
            let result = try ProcessRunner().run("/bin/bash", [script.path])
            XCTAssertEqual(result.status, 0)
            XCTAssertTrue(result.text.components(separatedBy: "\n").contains(expected), result.text)
        }
    }

}
