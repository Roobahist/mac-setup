import XCTest
@testable import MacSetupCore

final class DisplayAndGuideTests: XCTestCase {
    func testDisplayHelperResolutionFollowsInstalledCLISymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let version = root.appendingPathComponent("versions/installed")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let actualExecutable = version.appendingPathComponent("mac-setup")
        try Data().write(to: actualExecutable)
        let helper = version.appendingPathComponent("mac-setup-display")
        try "#!/bin/sh\\nexit 0\\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("current"), withDestinationURL: version)
        let invokedExecutable = bin.appendingPathComponent("mac-setup")
        try FileManager.default.createSymbolicLink(
            at: invokedExecutable, withDestinationURL: root.appendingPathComponent("current/mac-setup"))

        let resolved = AppResources.helperURL(
            named: "mac-setup-display",
            bundleURL: root.appendingPathComponent("Not An App"),
            executableURL: invokedExecutable)
        XCTAssertEqual(resolved?.resolvingSymlinksInPath(), helper)
    }

    func testDisplayHelperResolutionPrefersAppBundleHelper() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Mac Setup.app")
        let helper = bundle.appendingPathComponent("Contents/Helpers/mac-setup-display")
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\\nexit 0\\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        XCTAssertEqual(
            AppResources.helperURL(named: "mac-setup-display",
                                   bundleURL: bundle, executableURL: nil),
            helper)
    }

    func testGuidedPermissionActionsRouteToCorrespondingSettings() throws {
        let task = try Catalog.task("karabiner-access")
        let services = GuideStepRouting.destination(task: task, index: 0)
        let driver = GuideStepRouting.destination(task: task, index: 1)
        let accessibility = GuideStepRouting.destination(task: task, index: 2)
        let input = GuideStepRouting.destination(task: task, index: 3)
        let app = GuideStepRouting.destination(task: task, index: 4)
        XCTAssertEqual(services?.url, "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        XCTAssertEqual(driver?.url, services?.url)
        XCTAssertTrue(accessibility?.url?.contains("Privacy_Accessibility") == true)
        XCTAssertTrue(input?.url?.contains("Privacy_ListenEvent") == true)
        XCTAssertEqual(app?.app, "Karabiner-Elements")
        XCTAssertNil(GuideStepRouting.destination(task: task, index: 6))
        let raycast = try Catalog.task("raycast-access")
        XCTAssertEqual(GuideStepRouting.destination(task: raycast, index: 1)?.app, "Raycast")
        let vorssaint = try Catalog.task("vorssaint-access")
        XCTAssertTrue(GuideStepRouting.destination(task: vorssaint, index: 1)?.url?
            .contains("Privacy_Accessibility") == true)
        XCTAssertTrue(GuideStepRouting.destination(task: vorssaint, index: 2)?.url?
            .contains("LoginItems") == true)
        XCTAssertNil(GuideStepRouting.destination(task: task, index: -1))
        let finder = try Catalog.task("finder-sidebar")
        XCTAssertEqual(GuideStepRouting.destination(task: finder, index: 0)?.app, "Finder")
    }

    func testTimedCommandsRespectTheirIndividualBudget() throws {
        let brief = ProcessRunner(timeout: 0.03)
        let result = try brief.runTimed("/bin/sleep", ["0.12"], timeout: 1, input: nil)
        XCTAssertEqual(result.status, 0)
        XCTAssertThrowsError(try brief.runTimed("/bin/sleep", ["0.4"], timeout: 0.05, input: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("within 0 seconds") ||
                          String(describing: error).contains("did not respond"))
        }
    }

    func testRoundedFloatingPreferencesPreserveMeaningfulDifferences() {
        let expected = NSNumber(value: 0.73999999999999999)
        let float32 = NSNumber(value: Float(0.74))
        XCTAssertTrue(equalPreference(float32, expected))
        XCTAssertFalse(equalPreference(NSNumber(value: 0.70), expected))
        XCTAssertFalse(equalPreference(NSNumber(value: true), expected))
        XCTAssertTrue(equalPreference("resolution", "resolution"))
    }

    func testNativeMenuBarBackgroundStepOnlyRequiresTahoe() {
        let older = Catalog.menuBarBackgroundAction(macOSMajorVersion: 15)
        let tahoe = Catalog.menuBarBackgroundAction(macOSMajorVersion: 26)
        guard case let .guide(oldURL, _, oldInstructions) = older,
              case let .guide(newURL, _, newInstructions) = tahoe else {
            return XCTFail("Expected guided native menu bar instructions")
        }
        XCTAssertNil(oldURL)
        XCTAssertEqual(newURL, "x-apple.systempreferences:")
        XCTAssertTrue(oldInstructions.joined().contains("No extra setting"))
        XCTAssertTrue(newInstructions.joined().contains("Show menu bar background"))
    }

    func testAppearanceInstructionsRespectOSAvailability() {
        let earlier = Catalog.appearanceInstructions(macOSMajorVersion: 15)
        let newer = Catalog.appearanceInstructions(macOSMajorVersion: 26)
        XCTAssertTrue(earlier.joined(separator: " ").contains("only available"))
        XCTAssertFalse(earlier.joined(separator: " ").contains("Select Clear Liquid Glass"))
        XCTAssertTrue(newer.joined(separator: " ").contains("Clear Liquid Glass"))
    }

    func testReferenceGlyphsAndFontsMatchTheHost() {
        let expected = ["robot": "􀴽", "music": "􀑬", "chat": "􀌲", "notes": "􀈫", "clock": "􀐯"]
        for (name, character) in expected {
            XCTAssertEqual(WorkspaceConfiguration.symbol(for: name), character)
            XCTAssertEqual(WorkspaceConfiguration.font(for: name), "SF Pro:Regular:14.5")
        }
        XCTAssertEqual(WorkspaceConfiguration.font(for: "1"), "Hack Nerd Font:Bold:14.5")
    }

    func testNotchIsNotReservedTwiceAndScaledHeightsArePreserved() {
        let external = DisplayMetrics(name: "External", statusThickness: 22, safeTop: 0)
        let laptop = DisplayMetrics(name: "Built-in", statusThickness: 22, safeTop: 38)
        XCTAssertEqual(external.height, 22)
        XCTAssertEqual(external.gap, 24)
        XCTAssertEqual(laptop.height, 38)
        XCTAssertEqual(laptop.gap, 2)
        let geometry = DisplayGeometry(displays: [laptop, external])
        XCTAssertEqual(geometry.baseHeight, 22)
        XCTAssertEqual(geometry.notchHeight, 38)
        XCTAssertTrue(geometry.gapLine.contains("monitor.\"^Built-in$\" = 2"))
        XCTAssertTrue(geometry.gapLine.contains("monitor.\"^External$\" = 24"))
        let large = DisplayMetrics(name: "Scaled", statusThickness: 24, safeTop: 0)
        XCTAssertEqual(DisplayGeometry(displays: [large]).baseHeight, 24)
        XCTAssertEqual(large.gap, 26)
    }

    func testGeometryOverlaySurvivesCanonicalSourceRefresh() {
        let raw = "source \"$PLUGIN_DIR/colors.sh\"\nsketchybar --bar \\\n  height=30 \\\n  topmost=off \\\n  hidden=off\n"
        let output = DisplayGeometry.barShell(raw)
        XCTAssertTrue(output.contains("height=\"$BAR_HEIGHT\""))
        XCTAssertTrue(output.contains("notch_display_height=\"$NOTCH_HEIGHT\""))
        XCTAssertTrue(output.contains("topmost=window"))
        XCTAssertTrue(output.contains("display_change system_woke"))
        XCTAssertEqual(DisplayGeometry.barShell(output), output)
    }

    func testDisplayNamesKeepRegexAndTOMLEscaping() {
        let geometry = DisplayGeometry(displays: [.init(name: "Display (Left) \"4K\"", statusThickness: 22, safeTop: 0)])
        let generated = geometry.applying(to: "[gaps]\nouter.top = 32\nouter.left = 2\n")
        XCTAssertTrue(generated.contains("Display \\\\(Left\\\\)"))
        XCTAssertTrue(generated.contains("\\\"4K\\\""))
        XCTAssertTrue(generated.contains("outer.left = 2"))
        XCTAssertEqual(geometry.applying(to: generated), generated)
    }

    func testAdaptiveGapChangesStillAllowRestoreButOtherEditsAreProtected() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        let engine = try Engine(paths: paths, runner: FakeRunner(), tools: { _ in nil })
        let id = try engine.apply(Catalog.task("aerospace-profile"))
        let config = paths.config.appendingPathComponent("aerospace/aerospace.toml")
        let before = try String(contentsOf: config, encoding: .utf8)
        let geometry = DisplayGeometry(displays: [.init(name: "New display", statusThickness: 28, safeTop: 0)])
        try geometry.applying(to: before).write(to: config, atomically: true, encoding: .utf8)
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .done)
        try engine.journal.restore(id)
        XCTAssertFalse(Journal.exists(config))
        let next = try engine.apply(Catalog.task("aerospace-profile"))
        var userEdit = try String(contentsOf: config, encoding: .utf8)
        userEdit = userEdit.replacingOccurrences(of: "alt-1 = 'workspace 1'", with: "alt-1 = 'workspace 3'")
        try userEdit.write(to: config, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try engine.journal.restore(next))
    }

    func testRaycastReleasesOnlySpotlightSearchAndRestoresExistingShortcuts() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeRunner()
        let engine = try Engine(paths: Paths(home: home), runner: runner)
        let original: [String: Any] = [
            "64": ["enabled": true, "value": ["parameters": [65535, 49, 1048576], "type": "standard"]],
            "65": ["enabled": true, "value": ["parameters": [65535, 49, 1572864], "type": "standard"]],
            "999": ["enabled": true]
        ]
        runner.preferences["com.apple.symbolichotkeys"] = ["AppleSymbolicHotKeys": original]
        runner.preferences["com.raycast.macos"] = ["raycastGlobalHotkey": "Option-15"]
        let id = try engine.apply(Catalog.task("raycast-profile"))
        XCTAssertTrue(try engine.spotlightSearchEnabled())
        let updated = try engine.journal.preference("com.apple.symbolichotkeys", "AppleSymbolicHotKeys") as! [String: Any]
        XCTAssertTrue(equalPlist(updated["65"], original["65"]))
        XCTAssertTrue(equalPlist(updated["999"], original["999"]))
        XCTAssertEqual(try engine.state(Catalog.task("raycast-profile")), .done)
        XCTAssertTrue(try engine.checkGuide(Catalog.task("raycast-access")).ready)
        try engine.journal.restore(id)
        XCTAssertTrue(equalPlist(try engine.journal.preference("com.apple.symbolichotkeys", "AppleSymbolicHotKeys"), original))
        XCTAssertEqual(runner.preferences["com.raycast.macos"]?["raycastGlobalHotkey"] as? String, "Option-15")
    }

    func testPermissionButtonsOpenSystemSettingsInsteadOfDocumentation() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runner = FakeRunner()
        let engine = try Engine(paths: Paths(home: home), runner: runner)
        try engine.openGuideSettings(Catalog.task("karabiner-access"))
        try engine.openGuideSettings(Catalog.task("raycast-access"))
        XCTAssertTrue(runner.calls.contains(["/usr/bin/open", "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"]))
        XCTAssertTrue(runner.calls.contains(["/usr/bin/open", "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"]))
        XCTAssertFalse(runner.calls.contains { $0.contains(where: { $0.hasPrefix("https:") }) })
    }

    func testGuidedChecklistPersistsPartialStepsAndObservedPermissions() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        var progress = GuideProgress()
        progress.completedSteps["karabiner-access"] = ["Background services"]
        progress.observedRequirements["karabiner-access"] = [.init("driver", "Driver Extension", false)]
        try progress.save(to: paths)
        let loaded = try GuideProgress.load(from: paths)
        XCTAssertEqual(loaded.completedSteps["karabiner-access"], ["Background services"])
        XCTAssertEqual(loaded.observedRequirements["karabiner-access"]?.first?.ready, false)
    }
}
