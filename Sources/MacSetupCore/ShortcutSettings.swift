import Foundation

public enum ShortcutProvider: String, Codable, CaseIterable {
    case aerospace = "AeroSpace"
    case karabiner = "Karabiner"
    case raycast = "Raycast"
}

public struct ManagedShortcut: Codable, Equatable, Identifiable {
    public var id: String
    public var provider: ShortcutProvider
    public var action: String
    public var shortcut: WorkspaceShortcut
    public var enabled: Bool

    public init(id: String = UUID().uuidString, provider: ShortcutProvider,
                action: String, shortcut: WorkspaceShortcut, enabled: Bool = true) {
        self.id = id
        self.provider = provider
        self.action = action
        self.shortcut = shortcut
        self.enabled = enabled
    }
}

/// The user-editable hotkeys that are managed by Mac Setup. Workspace destination
/// keys remain in WorkspaceConfiguration; they inherit its two shared modifier sets.
public struct ShortcutSettings: Codable, Equatable {
    public var entries: [ManagedShortcut]

    public init(entries: [ManagedShortcut]) { self.entries = entries }

    public static let scripts: [(name: String, shell: String)] = [
        ("Alacritty", "\"$HOME/.config/karabiner/scripts/alacritty/open_new_window.sh\""),
        ("Visual Studio Code", "\"$HOME/.config/karabiner/scripts/vscode/open_new_window.sh\""),
        ("Finder", "\"$HOME/.config/karabiner/scripts/finder/open_window.sh\"")
    ]

    /// Carbon virtual key codes used by the Raycast global hotkey preference.
    /// A key without a macOS virtual-key code cannot be assigned to Raycast.
    public static let macKeyCodes: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28,
        "0": 29, "rightSquareBracket": 30, "o": 31, "u": 32,
        "leftSquareBracket": 33, "i": 34, "p": 35, "enter": 36, "l": 37,
        "j": 38, "quote": 39, "k": 40, "semicolon": 41, "backslash": 42,
        "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47,
        "tab": 48, "space": 49, "backtick": 50, "backspace": 51,
        "esc": 53, "f1": 122, "f2": 120, "f3": 99, "f4": 118,
        "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111, "left": 123, "right": 124,
        "down": 125, "up": 126
    ]

    /// Read ordinary AeroSpace bindings from the bundled main mode, excluding
    /// workspace actions that are generated separately for every workspace.
    public static func bundledAeroSpaceBindings(_ template: String) -> [(WorkspaceShortcut, String)] {
        var inMain = false
        var inWorkspaces = false
        var result: [(WorkspaceShortcut, String)] = []
        for raw in template.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "[mode.main.binding]" { inMain = true; continue }
            if inMain && line.hasPrefix("[") { break }
            if !inMain { continue }
            if line == "# Workspaces" { inWorkspaces = true }
            if line == "# Resize" { inWorkspaces = false }
            guard !inWorkspaces, let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let action = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if let shortcut = WorkspaceShortcut.parse(key), !action.isEmpty {
                result.append((shortcut, action))
            }
        }
        return result
    }

    public static func defaults(aerospaceTemplate: String) -> ShortcutSettings {
        let aerospace = bundledAeroSpaceBindings(aerospaceTemplate).map { shortcut, action in
            ManagedShortcut(id: "aerospace:\(shortcut.binding)", provider: .aerospace,
                            action: action, shortcut: shortcut)
        }
        let karabiner: [ManagedShortcut] = [
            .init(id: "karabiner:alacritty", provider: .karabiner,
                  action: "Alacritty", shortcut: .init(key: "enter", modifiers: ["alt"])),
            .init(id: "karabiner:vscode", provider: .karabiner,
                  action: "Visual Studio Code", shortcut: .init(key: "v", modifiers: ["alt"])),
            .init(id: "karabiner:finder", provider: .karabiner,
                  action: "Finder", shortcut: .init(key: "e", modifiers: ["alt"]))
        ]
        return .init(entries: aerospace + karabiner + [
            .init(id: "raycast:launcher", provider: .raycast, action: "launcher",
                  shortcut: .init(key: "space", modifiers: ["cmd"]))
        ])
    }

    public static func path(in paths: Paths) -> URL {
        paths.state.appendingPathComponent("shortcuts.json")
    }

    public static func load(from paths: Paths, aerospaceTemplate: String) throws -> ShortcutSettings {
        let file = path(in: paths)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return defaults(aerospaceTemplate: aerospaceTemplate)
        }
        return try JSONDecoder().decode(ShortcutSettings.self, from: Data(contentsOf: file))
    }

    public func save(to paths: Paths) throws {
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.path(in: paths), options: .atomic)
    }

    public static func actionTitle(_ action: String, provider: ShortcutProvider) -> String {
        switch provider {
        case .aerospace:
            if action == "[]" { return "Disable native shortcut" }
            return action.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                .replacingOccurrences(of: "exec-and-forget ", with: "Run: ")
                .replacingOccurrences(of: "focus --wrap-around ", with: "Focus ")
                .replacingOccurrences(of: "macos-native-fullscreen", with: "Native fullscreen")
                .replacingOccurrences(of: "fullscreen", with: "Fullscreen")
                .replacingOccurrences(of: "move-workspace-to-monitor --wrap-around ", with: "Move workspace to monitor ")
                .replacingOccurrences(of: "workspace-back-and-forth", with: "Previous workspace")
                .replacingOccurrences(of: "balance-sizes", with: "Balance windows")
                .replacingOccurrences(of: "resize ", with: "Resize ")
                .replacingOccurrences(of: "move ", with: "Move window ")
        case .karabiner:
            return action.hasPrefix("open:") ? "Open " + String(action.dropFirst(5)) : "Open " + action
        case .raycast: return "Open Raycast"
        }
    }

    public func validate(workspaces: WorkspaceConfiguration, aerospaceTemplate: String) throws {
        let availableActions = Set(Self.bundledAeroSpaceBindings(aerospaceTemplate).map { $0.1 })
        let uniqueIDs = Set(entries.map(\.id))
        guard uniqueIDs.count == entries.count else { throw SetupError("Shortcut row IDs must be unique.") }
        guard entries.filter({ $0.provider == .raycast }).count == 1,
              entries.first(where: { $0.provider == .raycast })?.action == "launcher" else {
            throw SetupError("Raycast has one supported global launcher shortcut.")
        }

        var active: [String: String] = [:]
        for entry in entries {
            if entry.provider == .aerospace && !availableActions.contains(entry.action) {
                throw SetupError("Unrecognized AeroSpace action in \(entry.id).")
            }
            if entry.provider == .karabiner {
                if entry.action.hasPrefix("open:") {
                    let bundleID = String(entry.action.dropFirst(5))
                    let permitted = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
                    guard !bundleID.isEmpty && bundleID.unicodeScalars.allSatisfy(permitted.contains) else {
                        throw SetupError("Enter a valid application bundle ID for Karabiner.")
                    }
                } else if !Self.scripts.contains(where: { $0.name == entry.action }) {
                    throw SetupError("Unrecognized Karabiner action in \(entry.id).")
                }
            }
            guard entry.enabled else { continue }
            try entry.shortcut.validate()
            if entry.provider == .raycast && Self.macKeyCodes[entry.shortcut.key] == nil {
                throw SetupError("This key cannot be used for the Raycast launcher.")
            }
            let chord = entry.shortcut.binding
            if let existing = active[chord] {
                throw SetupError("\(entry.shortcut.display) is assigned to both \(existing) and \(Self.actionTitle(entry.action, provider: entry.provider)).")
            }
            active[chord] = Self.actionTitle(entry.action, provider: entry.provider)
        }
        for (index, workspace) in workspaces.workspaces.enumerated() {
            let pair = workspaces.shortcuts(at: index)
            for chord in [pair.switchTo, pair.moveWindow].compactMap({ $0 }) {
                if let existing = active[chord.binding] {
                    throw SetupError("\(chord.display) conflicts with \(existing) and workspace \(workspace.name).")
                }
                active[chord.binding] = "workspace \(workspace.name)"
            }
        }

        // The dynamically generated AeroSpace bindings must also be checked
        // against workspace destinations before a profile can be applied.
        try workspaces.validate(aerospaceTemplate: aerospaceTemplateApplying(to: aerospaceTemplate))
    }

    public func aerospaceTemplateApplying(to template: String) -> String {
        let known = Set(Self.bundledAeroSpaceBindings(template).map { $0.0.binding })
        let lines = template.components(separatedBy: "\n")
        var output: [String] = []
        var inMain = false
        var inWorkspaces = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[mode.main.binding]" { inMain = true }
            else if inMain && trimmed.hasPrefix("[") { inMain = false }
            if inMain && trimmed == "# Workspaces" { inWorkspaces = true }
            if inMain && trimmed == "# Resize" { inWorkspaces = false }
            if inMain && !inWorkspaces, let split = trimmed.firstIndex(of: "="),
               known.contains(String(trimmed[..<split]).trimmingCharacters(in: .whitespaces)) {
                continue
            }
            output.append(line)
            if trimmed == "[mode.main.binding]" {
                output.append("# Managed shortcuts generated by Mac Setup")
                for item in entries where item.provider == .aerospace && item.enabled {
                    output.append("\(item.shortcut.binding) = \(item.action)")
                }
                output.append("")
            }
        }
        return output.joined(separator: "\n")
    }

    public func karabinerData(from source: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: source) as? [String: Any],
              var profiles = root["profiles"] as? [[String: Any]],
              let index = profiles.firstIndex(where: { ($0["name"] as? String) == "Portable" }),
              var profile = profiles[index] as [String: Any],
              var modifications = profile["complex_modifications"] as? [String: Any],
              var rules = modifications["rules"] as? [[String: Any]] else {
            throw SetupError("Could not locate Karabiner's Portable profile.")
        }

        let scriptNames = Set(Self.scripts.map { $0.name })
        rules.removeAll { scriptNames.contains($0["description"] as? String ?? "") ||
            ($0["description"] as? String) == "Mac Setup: Custom shortcuts" }
        let manipulators: [[String: Any]] = try entries.filter {
            $0.provider == .karabiner && $0.enabled
        }.map { entry in
            let command: String
            if let script = Self.scripts.first(where: { $0.name == entry.action }) {
                command = script.shell
            } else {
                let id = String(entry.action.dropFirst(5))
                command = "/usr/bin/open -b " + id
            }
            let karabinerKey: String
            switch entry.shortcut.key {
            case "enter": karabinerKey = "return_or_enter"
            case "backtick": karabinerKey = "grave_accent_and_tilde"
            case "minus": karabinerKey = "hyphen"
            case "equal": karabinerKey = "equal_sign"
            case "space": karabinerKey = "spacebar"
            default: karabinerKey = entry.shortcut.key
            }
            let mapped = entry.shortcut.modifiers.map { modifier in
                ["cmd": "command", "ctrl": "control", "alt": "option", "shift": "shift"][modifier]!
            }
            return [
                "type": "basic",
                "description": Self.actionTitle(entry.action, provider: entry.provider),
                "from": [
                    "key_code": karabinerKey,
                    "modifiers": ["mandatory": mapped, "optional": ["caps_lock"]]
                ],
                "to": [["shell_command": command]]
            ]
        }
        if !manipulators.isEmpty {
            rules.append(["description": "Mac Setup: Custom shortcuts", "manipulators": manipulators])
        }
        modifications["rules"] = rules
        profile["complex_modifications"] = modifications
        profiles[index] = profile
        root["profiles"] = profiles
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public var raycastHotkey: String {
        let item = entries.first { $0.provider == .raycast }
        let modifierMap = ["cmd": "Command", "ctrl": "Control", "alt": "Option", "shift": "Shift"]
        let parts = WorkspaceShortcut.modifierNames.filter { item?.shortcut.modifiers.contains($0) == true }
            .compactMap { modifierMap[$0] }
        return (parts + [String(Self.macKeyCodes[item?.shortcut.key ?? "space"] ?? 49)]).joined(separator: "-")
    }

    public var usesSpotlightKey: Bool {
        entries.contains { $0.provider == .raycast && $0.enabled &&
            $0.shortcut.key == "space" && Set($0.shortcut.modifiers) == ["cmd"] }
    }
}
