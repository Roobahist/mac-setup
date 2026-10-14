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
            ? "Karabiner's helper, permissions, driver, keyboard and Portable profile are ready. Test one enabled application shortcut from the Shortcuts editor."
            : "Still needed: " + missing.joined(separator: ", ") + ". Finish these in Karabiner's assistant, then check again.", requirements: checks)
    }

    /// Settings are opened separately so the app's assistant stays visible.
    func openGuideSettings(_ task: SetupTask) throws {
        guard case let .guide(url, _, _) = task.action, let url else { return }
        try runner.checked("/usr/bin/open", [url])
    }
}

public struct GuideStepDestination: Equatable {
    public let title: String
    public let url: String?
    public let app: String?

    public init(title: String, url: String? = nil, app: String? = nil) {
        self.title = title
        self.url = url
        self.app = app
    }
}

/// Routes permission instructions to the matching macOS pane.
/// One row's button should not open an unrelated permission screen.
public enum GuideStepRouting {
    public static func destination(task: SetupTask, index: Int) -> GuideStepDestination? {
        guard index >= 0 else { return nil }
        if task.id == "karabiner-access" {
            switch index {
            case 0: return .init(title: "Open login items",
                                 url: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
            case 1: return .init(title: "Open driver extensions",
                                 url: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
            case 2: return .init(title: "Open Accessibility",
                                 url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            case 3: return .init(title: "Open Input Monitoring",
                                 url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
            case 4, 5: return .init(title: "Open Karabiner", app: "Karabiner-Elements")
            default: return nil
            }
        }
        switch task.action {
        case let .guide(url, app, instructions):
            guard instructions.indices.contains(index) else { return nil }
            if let url { return .init(title: "Open settings", url: url) }
            if let app { return .init(title: "Open \(app)", app: app) }
            return nil
        case let .appStore(_, url):
            return index == 0 ? .init(title: "Open App Store", url: url) : nil
        default: return nil
        }
    }
}

public extension Engine {
    func openGuideStep(_ task: SetupTask, index: Int) throws {
        guard let destination = GuideStepRouting.destination(task: task, index: index) else { return }
        if let url = destination.url {
            try runner.checked("/usr/bin/open", [url])
        } else if let app = destination.app {
            try runner.checked("/usr/bin/open", ["-a", app])
        }
    }
}
