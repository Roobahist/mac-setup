import Foundation
import XCTest
@testable import MacSetupCore

final class WorkspaceRuntimeVerificationTests: XCTestCase {
    func testLiveBarOrderIgnoresUnrelatedItemsButPreservesWorkspaceOrder() throws {
        let response = Data(#"{"items":["clock","space.notes","workspace_observer","space.1","space.ai"]}"#.utf8)
        XCTAssertEqual(try WorkspaceRuntimeVerification.sketchyBarWorkspaceIDs(from: response),
                       ["notes", "1", "ai"])
        XCTAssertNil(WorkspaceRuntimeVerification.sketchyBarOrderIssue(
            query: response, expectedIDs: ["notes", "1", "ai"]))
        let issue = try XCTUnwrap(WorkspaceRuntimeVerification.sketchyBarOrderIssue(
            query: response, expectedIDs: ["1", "notes", "ai"]))
        XCTAssertTrue(issue.contains("different workspace order"))
    }

    func testMissingOrMalformedLiveBarItemsNeverCountAsSuccess() {
        for response in [#"{}"#, #"{"items":null}"#, #"{"items":["space.1"]"#, #"{"items":{}}"#] {
            XCTAssertNotNil(WorkspaceRuntimeVerification.sketchyBarOrderIssue(
                query: Data(response.utf8), expectedIDs: ["1"]))
        }
        XCTAssertNotNil(WorkspaceRuntimeVerification.sketchyBarOrderIssue(
            query: Data(#"{"items":[]}"#.utf8), expectedIDs: ["1"]))
    }

    func testAeroSpaceEnumerationIsASetNotAnOrderingOracle() {
        let output = "ai\nnotes\n1\n"
        XCTAssertEqual(WorkspaceRuntimeVerification.missingAeroSpaceIDs(
            output: output, expectedIDs: ["notes", "1", "ai"]), [])
        XCTAssertEqual(WorkspaceRuntimeVerification.missingAeroSpaceIDs(
            output: output, expectedIDs: ["notes", "4", "1", "5"]), ["4", "5"])
    }

    func testProfileSettingsReplaceValuesWithoutDependingOnOriginalDefaults() throws {
        let paths = Paths()
        var layout = WorkspaceConfiguration.defaultLayout
        layout.barStyle = WorkspaceBarStyle(
            itemWidth: 39, blurRadius: 30,
            backgroundColor: "0x70112233",
            occupiedColor: "0xffabcdef",
            emptyColor: "0x33123456")
        let baseBar = try String(contentsOf:
            paths.profile.appendingPathComponent("sketchybar/sketchybarrc"), encoding: .utf8)
        let changedBar = baseBar
            .replacingOccurrences(of: "label.width=21", with: "label.width=27")
            .replacingOccurrences(of: "blur_radius=50", with: "blur_radius=60")
        let generatedBar = try layout.sketchybarShell(from: changedBar)
        XCTAssertTrue(generatedBar.contains("label.width=39 \\"))
        XCTAssertTrue(generatedBar.contains("blur_radius=30 \\"))

        let baseColors = try String(contentsOf:
            paths.profile.appendingPathComponent("sketchybar/plugins/colors.sh"), encoding: .utf8)
        let changedColors = baseColors.replacingOccurrences(
            of: "export BAR_COLOR=0x35000000", with: "export BAR_COLOR=0x12345678")
        let generatedColors = try layout.barStyle.colorsShell(from: changedColors)
        XCTAssertTrue(generatedColors.contains("export BAR_COLOR=0x70112233"))
        XCTAssertTrue(generatedColors.contains("export HIGHLIGHT_COLOR=0xff7873B6"))
    }

    func testIncompleteProfileRejectsEditsRatherThanSilentlyIgnoringThem() throws {
        let paths = Paths()
        let bar = try String(contentsOf:
            paths.profile.appendingPathComponent("sketchybar/sketchybarrc"), encoding: .utf8)
        let colors = try String(contentsOf:
            paths.profile.appendingPathComponent("sketchybar/plugins/colors.sh"), encoding: .utf8)
        XCTAssertThrowsError(try WorkspaceConfiguration.defaultLayout.sketchybarShell(
            from: bar.replacingOccurrences(of: "label.width=21", with: "width.unsupported=21")))
        XCTAssertThrowsError(try WorkspaceBarStyle().colorsShell(
            from: colors.replacingOccurrences(of: "export BASE_GRAY=", with: "export MISSING_GRAY=")))
        XCTAssertThrowsError(try WorkspaceBarStyle().colorsShell(
            from: colors + "\nexport BAR_COLOR=0xff010203\n"))
    }
}

private final class WorkspaceProbeRunner: CommandRunning {
    var replies: [String: CommandResult] = [:]
    var calls: [String] = []

    func run(_ executable: String, _ arguments: [String], interactive: Bool,
             input: Data?) throws -> CommandResult {
        let call = ([executable] + arguments).joined(separator: " ")
        calls.append(call)
        return replies[call] ?? CommandResult(status: 1, output: Data("Unavailable".utf8))
    }
}

final class WorkspaceRuntimeIntegrationTests: XCTestCase {
    func testProfileApplyDoesNotClaimSuccessWhenReloadLeavesStaleItems() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let helper = home.appendingPathComponent("mac-setup-display")
        try Data("#!/bin/sh\\nexit 0\\n".utf8).write(to: helper)
        let paths = Paths(home: home)
        let runner = WorkspaceProbeRunner()
        runner.replies["/fake/sketchybar --query bar"] = CommandResult(
            status: 0, output: Data(#"{"items":["space.old"]}"#.utf8))
        runner.replies["/fake/sketchybar --reload"] = CommandResult(status: 0)
        let engine = try Engine(paths: paths, runner: runner, displayHelper: helper, tools: {
            $0 == "sketchybar" ? "/fake/sketchybar" : nil
        })
        engine.workspaceVerificationAttempts = 1
        XCTAssertThrowsError(try engine.apply(Catalog.task("sketchybar-profile"))) { error in
            XCTAssertTrue(String(describing: error).contains("reload was not verified"))
        }
        XCTAssertTrue(runner.calls.contains("/fake/sketchybar --reload"))
        XCTAssertTrue(runner.calls.contains("/fake/sketchybar --query bar"))

        let order = WorkspaceConfiguration.defaultLayout.workspaces.map { "space." + $0.id }
        runner.replies["/fake/sketchybar --query bar"] = CommandResult(
            status: 0, output: try JSONSerialization.data(withJSONObject: ["items": order]))
        XCTAssertNoThrow(try engine.apply(Catalog.task("sketchybar-profile")))
    }

    func testEngineQueriesRealServiceResponsesRatherThanAssumingGeneratedFilesAreActive() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = Paths(home: home)
        let runner = WorkspaceProbeRunner()
        let layout = WorkspaceConfiguration.defaultLayout
        try layout.save(to: paths)
        let managed = paths.config.appendingPathComponent("aerospace/aerospace.toml").path
        let ordered = layout.workspaces.map { "space." + $0.id }
        let barJSON = try JSONSerialization.data(withJSONObject: ["items": ["clock"] + ordered])
        runner.replies["/fake/sketchybar --query bar"] = CommandResult(status: 0, output: barJSON)
        runner.replies["/fake/aerospace config --config-path"] = CommandResult(
            status: 0, output: Data((managed + "\n").utf8))
        runner.replies["/fake/aerospace list-workspaces --all"] = CommandResult(
            status: 0, output: Data(layout.workspaces.map(\.id).sorted().joined(separator: "\n").utf8))
        let engine = try Engine(paths: paths, runner: runner, tools: { "/fake/" + $0 })
        XCTAssertTrue(engine.workspaceRuntimeIssues(
            checkAeroSpace: true, checkSketchyBar: true).isEmpty)

        runner.replies["/fake/sketchybar --query bar"] = CommandResult(
            status: 0, output: try JSONSerialization.data(withJSONObject:
                ["items": ["clock"] + Array(ordered.reversed())]))
        let issues = engine.workspaceRuntimeIssues(checkAeroSpace: true, checkSketchyBar: true)
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("different workspace order"))

        runner.replies["/fake/aerospace config --config-path"] = CommandResult(
            status: 0, output: Data("/tmp/other/aerospace.toml".utf8))
        XCTAssertTrue(engine.workspaceRuntimeIssues(
            checkAeroSpace: true, checkSketchyBar: false).contains {
                $0.contains("not using the managed configuration")
            })
    }
}
