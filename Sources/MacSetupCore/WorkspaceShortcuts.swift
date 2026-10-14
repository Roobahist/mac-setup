import Foundation

public struct WorkspaceShortcut: Codable, Equatable, Hashable {
    public var key: String
    public var modifiers: [String]

    public init(key: String, modifiers: [String] = ["alt"]) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let modifierNames = ["cmd", "ctrl", "alt", "shift"]
    public static let keyGroups: [(name: String, keys: [String])] = [
        ("Number row", WorkspaceConfiguration.keys),
        ("Letters", Array("abcdefghijklmnopqrstuvwxyz").map(String.init)),
        ("Function keys", (1...20).map { "f\($0)" }),
        ("Navigation", ["left", "down", "up", "right", "pageUp", "pageDown", "home", "end"]),
        ("Other keys", ["period", "comma", "slash", "backslash", "quote", "semicolon",
                        "leftSquareBracket", "rightSquareBracket", "space", "enter", "esc",
                        "backspace", "tab", "forwardDelete", "sectionSign"]),
        ("Keypad", (0...9).map { "keypad\($0)" } + ["keypadClear", "keypadDecimalMark",
            "keypadDivide", "keypadEnter", "keypadEqual", "keypadMinus", "keypadMultiply", "keypadPlus"])
    ]

    public var binding: String {
        (Self.modifierNames.filter(modifiers.contains) + [key]).joined(separator: "-")
    }

    public var display: String {
        let symbols = [("ctrl", "⌃"), ("alt", "⌥"), ("shift", "⇧"), ("cmd", "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + " " + Self.keyLabel(key)
    }

    public static func keyLabel(_ key: String) -> String {
        let labels = ["backtick": "`", "minus": "−", "equal": "=", "period": ".", "comma": ",",
            "slash": "/", "backslash": "\\", "quote": "'", "semicolon": ";",
            "leftSquareBracket": "[", "rightSquareBracket": "]", "space": "Space", "enter": "Return",
            "esc": "Escape", "backspace": "Delete", "tab": "Tab", "forwardDelete": "Forward Delete",
            "sectionSign": "§", "left": "←", "right": "→", "up": "↑", "down": "↓",
            "pageUp": "Page Up", "pageDown": "Page Down", "home": "Home", "end": "End"]
        if let label = labels[key] { return label }
        if key.hasPrefix("keypad") { return "Keypad " + key.dropFirst(6) }
        return key.uppercased()
    }

    public func validate() throws {
        guard Self.keyGroups.flatMap(\.keys).contains(key) else {
            throw SetupError("Choose a supported keyboard key.")
        }
        guard !modifiers.isEmpty, Set(modifiers).count == modifiers.count,
              modifiers.allSatisfy(Self.modifierNames.contains) else {
            throw SetupError("Choose at least one modifier: Command, Control, Option or Shift.")
        }
    }

    static func parse(_ binding: String) -> WorkspaceShortcut? {
        let parts = binding.split(separator: "-").map(String.init)
        guard let key = parts.last else { return nil }
        let shortcut = WorkspaceShortcut(key: key, modifiers: Array(parts.dropLast()))
        return (try? shortcut.validate()) == nil ? nil : shortcut
    }
}

/// A nil pair on a workspace uses its position's number-row defaults.
/// A pair with nil actions explicitly leaves those actions unbound.
public struct WorkspaceShortcuts: Codable, Equatable {
    public var switchTo: WorkspaceShortcut?
    public var moveWindow: WorkspaceShortcut?

    public init(switchTo: WorkspaceShortcut? = nil, moveWindow: WorkspaceShortcut? = nil) {
        self.switchTo = switchTo
        self.moveWindow = moveWindow
    }

    public static func defaultRow(at index: Int) -> WorkspaceShortcuts {
        guard WorkspaceConfiguration.keys.indices.contains(index) else { return .init() }
        let key = WorkspaceConfiguration.keys[index]
        return .init(switchTo: .init(key: key), moveWindow: .init(key: key, modifiers: ["alt", "shift"]))
    }
}


// The modifiers are shared across every workspace. Individual workspace
// definitions choose only the destination key.
public struct WorkspaceKeymap: Codable, Equatable {
    public var switchModifiers: [String]
    public var moveModifiers: [String]

    public init(switchModifiers: [String] = ["alt"],
                moveModifiers: [String] = ["alt", "shift"]) {
        self.switchModifiers = switchModifiers
        self.moveModifiers = moveModifiers
    }

    public func validate() throws {
        for modifiers in [switchModifiers, moveModifiers] {
            try WorkspaceShortcut(key: "1", modifiers: modifiers).validate()
        }
        guard Set(switchModifiers) != Set(moveModifiers) else {
            throw SetupError("Switch and move-window shortcuts must use different modifiers.")
        }
    }
}
