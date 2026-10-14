import Foundation

public struct GuideCheck {
    public let ready: Bool
    public let message: String
    public let requirements: [GuideRequirement]
    public init(_ ready: Bool, _ message: String, requirements: [GuideRequirement] = []) {
        self.ready = ready; self.message = message; self.requirements = requirements
    }
}

public extension Engine {
    func checkGuide(_ task: SetupTask) throws -> GuideCheck {
        switch task.id {
        case "aerospace-access":
            guard let tool = executable("aerospace") else { return GuideCheck(false, "Install AeroSpace first.") }
            let workspaces = try runner.run(tool, ["list-workspaces", "--all"])
            let windows = try runner.run(tool, ["list-windows", "--all", "--format", "%{window-id}"])
            return GuideCheck(workspaces.status == 0 && !workspaces.text.isEmpty && windows.status == 0 && !windows.text.isEmpty,
                              "AeroSpace must be running with Accessibility access and see at least one window. Then test Option+1 and Command+Tab to an app on another workspace.")
        case "karabiner-access":
            let cli = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
            let result = try runner.run(cli, ["--show-settings-window-guidance"])
            let profile = try runner.run(cli, ["--show-current-profile-name"])
            return Self.karabinerCheck(result, profile: profile.text)
        case "raycast-access":
            let template = try String(contentsOf: paths.profile.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
            let settings = try ShortcutSettings.load(from: paths, aerospaceTemplate: template)
            let actual = try journal.preference("com.raycast.macos", "raycastGlobalHotkey") as? String
            let spotlightConflict: Bool
            if settings.usesSpotlightKey { spotlightConflict = try spotlightSearchEnabled() }
            else { spotlightConflict = false }
            let configured = actual == settings.raycastHotkey && !spotlightConflict
            let combination = settings.entries.first(where: { $0.provider == .raycast })?.shortcut.display ?? "configured hotkey"
            return GuideCheck(configured, "Expected: \(combination) opens Raycast. Enable Launch at login and test the configured shortcut in Raycast Settings.")
        case "tomito":
            return GuideCheck(try state(task) == .done, "Install Tomito using the App Store, then return and check again.")
        default:
            return GuideCheck(true, "Check the visible result described above before marking this step complete.")
        }
    }

    static func karabinerCheck(_ result: CommandResult, profile: String) -> GuideCheck {
        guard result.status == 0,
              let value = try? JSONSerialization.jsonObject(with: result.output) as? [String: Any],
              let core = value["core_service_daemon_state"] as? [String: Any],
              let permissions = core["current_process_permission_check_result"] as? [String: Any],
              let context = value["guidance_context"] as? [String: Any] else {
            return GuideCheck(false, "Karabiner did not return its setup status. Open Karabiner and finish its assistant, then check again.")
        }
        var checks: [GuideRequirement] = [
            .init("services", "Background services", context["services_running"] as? Bool == true && context["services_enabled"] as? Bool == true),
            .init("driver", "Driver Extension", core["driver_activated"] as? Bool == true && core["driver_connected"] as? Bool == true && core["driver_version_mismatched"] as? Bool != true),
            .init("accessibility", "Accessibility", permissions["accessibility_process_trusted"] as? Bool == true),
            .init("input", "Input Monitoring", permissions["iohid_listen_event_allowed"] as? Bool == true),
            .init("keyboard", "Virtual keyboard and layout", core["virtual_hid_keyboard_ready"] as? Bool == true && core["virtual_hid_keyboard_type_not_set"] as? Bool != true),
            .init("profile", "Portable profile", profile == "Portable")
        ]
        if let error = core["karabiner_json_parse_error_message"] as? String, !error.isEmpty {
            checks.append(.init("config", "Configuration: " + error, false))
        }
        if core["karabiner_json_permission_error"] as? Bool == true || value["console_user_server_karabiner_json_permission_error"] as? Bool == true {
            checks.append(.init("file", "Configuration file access", false))
        }
        let missing = checks.filter { !$0.ready }.map(\.title)
        return GuideCheck(missing.isEmpty, missing.isEmpty
            ? "Karabiner's helper, permissions, driver, keyboard and Portable profile are ready. Now press Option+E and verify that one Finder window opens."
            : "Still needed: " + missing.joined(separator: ", ") + ". Finish these in Karabiner's assistant, then check again.", requirements: checks)
    }

    /// Settings are opened separately so the app's assistant stays visible.
    func openGuideSettings(_ task: SetupTask) throws {
        guard case let .guide(url, _, _) = task.action, let url else { return }
        try runner.checked("/usr/bin/open", [url])
    }
}
