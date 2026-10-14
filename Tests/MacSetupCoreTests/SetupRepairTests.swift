import XCTest
@testable import MacSetupCore

final class SetupRepairTests: XCTestCase {
    func testGeneratedBarUsesChosenGlyphsAtRuntime() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let config = WorkspaceConfiguration(workspaces: [
            .init(id: "research", name: "Research", glyph: "book"),
            .init(id: "1", name: "1", glyph: "1")
        ])
        let paths = Paths(home: home)
        let bar = try config.sketchybarShell(from: String(contentsOf: paths.profile.appendingPathComponent("sketchybar/sketchybarrc"), encoding: .utf8))
        let toml = try config.aerospaceTOML(from: String(contentsOf: paths.profile.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8))
        let configFile = home.appendingPathComponent("aerospace.toml")
        try toml.write(to: configFile, atomically: true, encoding: .utf8)
        let capture = home.appendingPathComponent("calls")
        let stub = bin.appendingPathComponent("sketchybar")
        try "#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"$CAPTURE\"\n".write(to: stub, atomically: true, encoding: .utf8)
        let aerospace = bin.appendingPathComponent("aerospace")
        try "#!/bin/bash\nif [ \"$1\" = config ]; then printf '%s\\n' \"$TEST_CONFIG\"; else echo 1; fi\n".write(to: aerospace, atomically: true, encoding: .utf8)
        for file in [stub, aerospace] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        let script = home.appendingPathComponent("bar.sh")
        try bar.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.environment = ["HOME": home.path, "PATH": bin.path + ":/usr/bin:/bin", "CAPTURE": capture.path,
                               "CONFIG_DIR": paths.profile.appendingPathComponent("sketchybar").path, "TEST_CONFIG": configFile.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let calls = try String(contentsOf: capture, encoding: .utf8)
        XCTAssertTrue(calls.contains("--set space.research label=" + WorkspaceConfiguration.symbol(for: "book")!))
        XCTAssertTrue(calls.contains("label.font=Hack Nerd Font Mono:Bold:17.0"))
        XCTAssertTrue(calls.contains("label.width=30"))
        XCTAssertFalse(calls.contains("Font Awesome"))
        XCTAssertTrue(calls.contains("front_app_switched system_woke"))
    }

    func testKarabinerMustHavePermissionsDriverAndProfile() throws {
        var core: [String: Any] = [
            "current_process_permission_check_result": ["accessibility_process_trusted": true, "iohid_listen_event_allowed": true],
            "driver_activated": true, "driver_connected": true, "virtual_hid_keyboard_ready": true,
            "karabiner_json_parse_error_message": ""
        ]
        func result() throws -> CommandResult {
            CommandResult(status: 0, output: try JSONSerialization.data(withJSONObject: [
                "core_service_daemon_state": core, "guidance_context": ["services_running": true]
            ]))
        }
        XCTAssertTrue(Engine.karabinerCheck(try result(), profile: "Portable").ready)
        XCTAssertFalse(Engine.karabinerCheck(try result(), profile: "Default profile").ready)
        core["driver_connected"] = false
        XCTAssertFalse(Engine.karabinerCheck(try result(), profile: "Portable").ready)
        core["driver_connected"] = true
        core["current_process_permission_check_result"] = ["accessibility_process_trusted": true, "iohid_listen_event_allowed": false]
        XCTAssertFalse(Engine.karabinerCheck(try result(), profile: "Portable").ready)
        XCTAssertFalse(Engine.karabinerCheck(CommandResult(status: 0), profile: "Portable").ready)
    }

    func testRestartsAreBatchedAndGuideOpensOnlyOneDestination() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeRunner()
        let engine = try Engine(paths: Paths(home: home), runner: runner)
        engine.deferRestarts = true
        _ = try engine.apply(Catalog.task("finder-list"))
        _ = try engine.apply(Catalog.task("finder-tabs"))
        XCTAssertFalse(runner.calls.contains { $0.first == "/usr/bin/killall" })
        try engine.finishRestarts()
        XCTAssertEqual(runner.calls.filter { $0 == ["/usr/bin/killall", "Finder"] }.count, 1)
        try engine.openGuide(Catalog.task("aerospace-access"))
        let opens = runner.calls.filter { $0.first == "/usr/bin/open" }
        XCTAssertEqual(opens, [["/usr/bin/open", "-a", "AeroSpace"]])
    }

    func testEmbeddedInstallerSupportsInputAndPreservesExitCode() throws {
        let runner = EmbeddedInstaller()
        runner.output = { value in if value.contains("RESPOND_NOW") { runner.send("ready") } }
        let result = try runner.run("/bin/sh", ["-c", "printf 'RESPOND_NOW\\n'; read response; test \"$response\" = ready || exit 9; exit 7"], interactive: true)
        XCTAssertEqual(result.status, 7)
    }
}
