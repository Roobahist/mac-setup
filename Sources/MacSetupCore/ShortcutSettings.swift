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

public struct AdvancedKarabinerRule: Codable, Equatable, Identifiable {
    public var id: String
    public var json: String
    public var enabled: Bool

    public init(id: String, json: String, enabled: Bool = true) {
        self.id = id
        self.json = json
        self.enabled = enabled
    }
}

/// The user-editable hotkeys that are managed by Mac Setup. Workspace destination
/// keys remain in WorkspaceConfiguration; they inherit its two shared modifier sets.
public struct ShortcutSettings: Codable, Equatable {
    public var entries: [ManagedShortcut]
    /// Optional to support shortcuts.json files created before advanced rules were editable.
    public var advancedKarabiner: [AdvancedKarabinerRule]?
    /// Nil indicates a configuration written before the Option+R migration.
    public var configurationVersion: Int?

    public init(entries: [ManagedShortcut], advancedKarabiner: [AdvancedKarabinerRule]? = nil) {
        self.entries = entries
        self.advancedKarabiner = advancedKarabiner
        self.configurationVersion = 3
    }

    /// Mark the current settings format without replacing a user's assignments.
    public mutating func migrateBundledDefaults(installedAlacritty: Bool) {
        // Existing assignments are user choices, including Terminal and Command+Space.
        // New installations use the source profile; upgrades never guess at intent.
        configurationVersion = 3
    }

    public mutating func updateAdvancedRule(_ rule: AdvancedKarabinerRule) {
        var values = advancedKarabiner ?? []
        values.removeAll { $0.id == rule.id }
        values.append(rule)
        advancedKarabiner = values
    }

    public static func bundledAdvancedKarabinerRules(from source: Data) -> [AdvancedKarabinerRule] {
        guard let root = try? JSONSerialization.jsonObject(with: source) as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]],
              let profile = profiles.first(where: { ($0["name"] as? String) == "Portable" }),
              let modifications = profile["complex_modifications"] as? [String: Any],
              let rules = modifications["rules"] as? [[String: Any]] else { return [] }
        let simple = Set(scripts.map { $0.name })
        return rules.compactMap { rule in
            guard let description = rule["description"] as? String,
                  !simple.contains(description),
                  let data = try? JSONSerialization.data(withJSONObject: rule, options: [.prettyPrinted, .sortedKeys]) else { return nil }
            return .init(id: description, json: String(decoding: data, as: UTF8.self),
                         enabled: rule["enabled"] as? Bool ?? true)
        }
    }

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
        let karabiner = ReferenceProfile.bundled.karabinerShortcuts
        return .init(entries: aerospace + karabiner + [
            .init(id: "raycast:launcher", provider: .raycast, action: "launcher",
                  shortcut: .init(key: "r", modifiers: ["alt"]))
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

    /// Workspace editing must not be blocked by unrelated malformed Karabiner
    /// actions or advanced rules. Check the layout and actual enabled key chords
    /// only. The full shortcut validation still runs when shortcuts are applied.
    public func validateWorkspaceBindings(_ workspaces: WorkspaceConfiguration,
                                          aerospaceTemplate: String) throws {
        try workspaces.validate(aerospaceTemplate: aerospaceTemplateApplying(to: aerospaceTemplate))
        var active: [String: String] = [:]
        for entry in entries where entry.enabled {
            // A malformed app action is not a workspace-editing error, but its
            // valid hotkey still conflicts with the workspace's hotkeys.
            guard (try? entry.shortcut.validate()) != nil else { continue }
            active[entry.shortcut.binding] = Self.actionTitle(entry.action, provider: entry.provider)
        }
        for (index, workspace) in workspaces.workspaces.enumerated() {
            let pair = workspaces.shortcuts(at: index)
            for chord in [pair.switchTo, pair.moveWindow].compactMap({ $0 }) {
                if let owner = active[chord.binding] {
                    throw SetupError("\(chord.display) conflicts with \(owner) and workspace \(workspace.name).")
                }
            }
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
                    guard !bundleID.isEmpty && bundleID.unicodeScalars.allSatisfy({ permitted.contains($0) }) else {
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

        let overrides = advancedKarabiner ?? []
        guard Set(overrides.map(\.id)).count == overrides.count else {
            throw SetupError("Advanced Karabiner rule names must be unique.")
        }
        for rule in overrides {
            guard let data = rule.json.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  parsed["description"] as? String == rule.id,
                  let manipulators = parsed["manipulators"] as? [[String: Any]],
                  !manipulators.isEmpty,
                  manipulators.allSatisfy({ $0["from"] is [String: Any] && $0["to"] != nil }) else {
                throw SetupError("Invalid advanced Karabiner rule '\(rule.id)'.")
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
            if inMain && !inWorkspaces, let split = trimmed.firstIndex(of: "=") {
                let rawKey = String(trimmed[..<split]).trimmingCharacters(in: .whitespaces)
                // AeroSpace treats alt-ctrl and ctrl-alt as equivalent.
                if let binding = WorkspaceShortcut.parse(rawKey)?.binding,
                   known.contains(binding) {
                    continue
                }
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

    public func karabinerData(from source: Data, preserving existing: Data? = nil,
                              configDirectory: URL? = nil) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: source) as? [String: Any],
              var profiles = root["profiles"] as? [[String: Any]],
              let index = profiles.firstIndex(where: { ($0["name"] as? String) == "Portable" }),
              var modifications = profiles[index]["complex_modifications"] as? [String: Any],
              var rules = modifications["rules"] as? [[String: Any]] else {
            throw SetupError("Could not locate Karabiner's Portable profile.")
        }

        var profile = profiles[index]
        guard Set(entries.map(\.id)).count == entries.count,
              Set((advancedKarabiner ?? []).map(\.id)).count == (advancedKarabiner ?? []).count else {
            throw SetupError("Shortcut and advanced rule IDs must be unique.")
        }
        let defaults = ReferenceProfile.bundled.karabinerShortcuts
        let sourceNames = Set(defaults.map(\.action))
        let overrides = Dictionary(uniqueKeysWithValues: (advancedKarabiner ?? []).map { ($0.id, $0) })
        var emitted = Set<String>()
        var generated: [[String: Any]] = []
        for original in rules {
            let name = original["description"] as? String ?? ""
            if let baseline = defaults.first(where: { $0.action == name }) {
                guard let entry = entries.first(where: { $0.id == baseline.id && $0.provider == .karabiner }) else { continue }
                emitted.insert(entry.id)
                if entry == baseline {
                    generated.append(original)
                } else {
                    generated.append(try karabinerRule(entry, description: name, original: original))
                }
            } else if let override = overrides[name] {
                generated.append(try Self.advancedRule(override))
            } else {
                generated.append(original)
            }
        }
        for entry in entries where entry.provider == .karabiner && !emitted.contains(entry.id) {
            generated.append(try karabinerRule(entry, description: Self.actionTitle(entry.action, provider: .karabiner)))
        }
        let existingNames = Set(rules.compactMap { $0["description"] as? String })
        for override in advancedKarabiner ?? [] where !existingNames.contains(override.id) {
            guard !sourceNames.contains(override.id) else {
                throw SetupError("Edit the application shortcut instead of overriding its rule: \(override.id)")
            }
            generated.append(try Self.advancedRule(override))
        }
        rules = generated
        modifications["rules"] = rules
        profile["complex_modifications"] = modifications
        profiles[index] = profile
        root["profiles"] = profiles
        if let existing {
            guard var installed = try JSONSerialization.jsonObject(with: existing) as? [String: Any],
                  let installedProfiles = installed["profiles"] as? [[String: Any]] else {
                throw SetupError("The existing Karabiner configuration is malformed. Inspect it before applying.")
            }
            var inserted = false
            var merged: [[String: Any]] = []
            for var item in installedProfiles {
                if item["name"] as? String == "Portable" {
                    if !inserted { merged.append(profile); inserted = true }
                } else {
                    item["selected"] = false
                    merged.append(item)
                }
            }
            if !inserted { merged.append(profile) }
            installed["profiles"] = merged
            root = installed
        }
        if let configDirectory {
            // Shell-command paths are host adaptations, confined to generated local files.
            let base = configDirectory.appendingPathComponent("karabiner").path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "`", with: "\\`")
            func commands(_ value: Any) -> Any {
                if var object = value as? [String: Any] {
                    for (key, child) in object {
                        if key == "shell_command", let command = child as? String {
                            object[key] = command.replacingOccurrences(of: "$HOME/.config/karabiner", with: base)
                        } else { object[key] = commands(child) }
                    }
                    return object
                }
                if let array = value as? [Any] { return array.map { commands($0) } }
                return value
            }
            // Relocate only our Portable profile; other installed profiles are preserved verbatim.
            if var values = root["profiles"] as? [[String: Any]] {
                for i in values.indices where values[i]["name"] as? String == "Portable" {
                    if let relocated = commands(values[i]) as? [String: Any] { values[i] = relocated }
                }
                root["profiles"] = values
            }
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private static func advancedRule(_ rule: AdvancedKarabinerRule) throws -> [String: Any] {
        guard let data = rule.json.data(using: .utf8),
              var parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              parsed["description"] as? String == rule.id,
              let manipulators = parsed["manipulators"] as? [[String: Any]], !manipulators.isEmpty else {
            throw SetupError("Invalid advanced Karabiner rule: \(rule.id)")
        }
        if rule.enabled { parsed.removeValue(forKey: "enabled") }
        else { parsed["enabled"] = false }
        return parsed
    }

    private func karabinerRule(_ entry: ManagedShortcut, description: String,
                               original: [String: Any]? = nil) throws -> [String: Any] {
        try entry.shortcut.validate()
        let command: String
        if let script = Self.scripts.first(where: { $0.name == entry.action }) {
            command = script.shell
        } else if entry.action.hasPrefix("open:") {
            let bundle = String(entry.action.dropFirst(5))
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
            guard !bundle.isEmpty, bundle.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw SetupError("Enter a valid application bundle ID for Karabiner.")
            }
            command = "/usr/bin/open -b " + bundle
        } else { throw SetupError("Unknown Karabiner action: \(entry.action)") }
        let modifierNames = ["cmd": "command", "ctrl": "control", "alt": "option", "shift": "shift"]
        var rule = original ?? [:]
        rule["description"] = description
        if entry.enabled { rule.removeValue(forKey: "enabled") } else { rule["enabled"] = false }
        var manipulator = (original?["manipulators"] as? [[String: Any]])?.first ?? ["type": "basic"]
        manipulator["from"] = ["key_code": entry.shortcut.karabinerKeyCode,
                               "modifiers": ["mandatory": entry.shortcut.modifiers.compactMap { modifierNames[$0] },
                                             "optional": ["caps_lock"]]]
        if original?["description"] as? String != entry.action {
            manipulator["to"] = [["shell_command": command]]
        }
        rule["manipulators"] = [manipulator]
        return rule
    }

    public var raycastHotkey: String {
        let item = entries.first { $0.provider == .raycast }
        guard let item, item.enabled else { return "" }
        let modifierMap = ["cmd": "Command", "ctrl": "Control", "alt": "Option", "shift": "Shift"]
        let parts = WorkspaceShortcut.modifierNames.filter { item.shortcut.modifiers.contains($0) }
            .compactMap { modifierMap[$0] }
        return (parts + [String(Self.macKeyCodes[item.shortcut.key] ?? 49)]).joined(separator: "-")
    }

    public var usesSpotlightKey: Bool {
        entries.contains { $0.provider == .raycast && $0.enabled &&
            $0.shortcut.key == "space" && Set($0.shortcut.modifiers) == ["cmd"] }
    }
}
