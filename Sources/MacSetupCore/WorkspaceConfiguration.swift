import Foundation

public struct WorkspaceGlyph: Hashable {
    public let name: String
    public let symbol: String
    public let keywords: String

    public init(_ name: String, _ symbol: String, _ keywords: String = "") {
        self.name = name
        self.symbol = symbol
        self.keywords = keywords
    }

    // Legacy IDs are retained only to decode existing layouts, never as picker labels.
    public static let all: [WorkspaceGlyph] = [
        .init("0", "0", "number zero"), .init("1", "1", "number one"),
        .init("2", "2", "number two"), .init("3", "3", "number three"),
        .init("4", "4", "number four"), .init("5", "5", "number five"),
        .init("6", "6", "number six"), .init("7", "7", "number seven"),
        .init("8", "8", "number eight"), .init("9", "9", "number nine"),
        .init("robot", "􀴽", "ai assistant chatgpt reference"), .init("terminal", "󰆍", "shell command"),
        .init("code", "󰅨", "developer editor vscode"), .init("file", "󰉋", "finder folder"),
        .init("git", "󰊢", "source version"), .init("tasks", "󱃔", "list todo"),
        .init("weather", "󰖕", "sun cloud"), .init("mail", "󰇮", "email inbox"),
        .init("calculator", "󰪚", "math"), .init("map", "󰆋", "navigation location"),
        .init("microphone", "󰍬", "audio recording"), .init("chat", "􀌲", "messages telegram whatsapp"),
        .init("video call", "󰍫", "zoom meetings"), .init("notes", "􀈫", "writing obsidian"),
        .init("camera", "󰄀", "photo"), .init("web", "󰇧", "browser safari chrome"),
        .init("home", "󱉑", "house automation"), .init("music", "􀑬", "spotify tunes"),
        .init("podcast", "󰦔", "radio"), .init("play", "󱉺", "video television"),
        .init("book", "󰂿", "reading"), .init("dictionary", "󱁯", "reference"),
        .init("preview", "󰋲", "image screenshot"), .init("password", "󰷡", "security key"),
        .init("download", "󱑢", "transfer"), .init("cast", "󱒃", "airplay"),
        .init("table", "󰓫", "excel spreadsheet"), .init("presentation", "󰈩", "slides"),
        .init("cloud", "󰅧", "drive backup"), .init("pen", "󰏬", "design drawing"),
        .init("desktop", "󰢹", "monitor remote"), .init("clock", "􀐯", "timer pomodoro"),
        .init("calendar", "󰃭", "schedule"), .init("wifi", "󰖩", "internet"),
        .init("vpn", "󰦝", "network privacy"), .init("battery", "󰁹", "power"),
        .init("memory", "󰓅", "ram"), .init("disk", "󰋊", "storage"),
        .init("cpu", "󰘚", "processor"), .init("settings", "󰒓", "configuration"),
        .init("chart", "󱕍", "analytics"), .init("lock", "󰌾", "secure"),
        .init("package", "󰏓", "homebrew"), .init("document", "󰈩", "work"),
        .init("star", "󰓎", "favorite"), .init("game", "󰊗", "gaming"),
        .init("heart", "󰋑", "wellness"), .init("search", "󰍉", "find"),
        .init("coffee", "󰅶", "break"), .init("briefcase", "󰃖", "work business")
    ]

    public static func matching(_ query: String) -> [WorkspaceGlyph] {
        guard !query.isEmpty else { return all }
        return all.filter { "\($0.name) \($0.keywords)".localizedCaseInsensitiveContains(query) }
    }
}

public struct InstalledApplication: Hashable {
    public let name: String
    public let bundleID: String
    public let path: String

    public init(name: String, bundleID: String, path: String) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
    }
}

public enum ApplicationDiscovery {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            roots: [URL]? = nil) -> [InstalledApplication] {
        let folders = roots ?? [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            home.appendingPathComponent("Applications")
        ]
        let manager = FileManager.default
        var discovered: [String: InstalledApplication] = [:]
        for root in folders {
            guard let iterator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            while let url = iterator.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "app" else { continue }
                iterator.skipDescendants()
                guard let bundle = Bundle(url: url),
                      let identifier = bundle.bundleIdentifier,
                      !identifier.isEmpty else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let app = InstalledApplication(name: name, bundleID: identifier, path: url.path)
                // Prefer apps in /Applications when duplicate bundle IDs exist.
                if discovered[identifier] == nil { discovered[identifier] = app }
            }
        }
        return discovered.values.sorted {
            let names = $0.name.localizedCaseInsensitiveCompare($1.name)
            return names == .orderedSame ? $0.bundleID < $1.bundleID : names == .orderedAscending
        }
    }
}

public struct WorkspaceDefinition: Codable, Equatable {
    public var id: String
    public var name: String
    public var glyph: String
    public var apps: [String]
    public var requiresTask: String?
    public var shortcuts: WorkspaceShortcuts? // Decodes shortcuts saved by older app versions.
    public var shortcutKey: String?
    public var icon: FontGlyphSelection?

    public init(id: String, name: String, glyph: String, apps: [String] = [], requiresTask: String? = nil,
                shortcuts: WorkspaceShortcuts? = nil, icon: FontGlyphSelection? = nil,
                shortcutKey: String? = nil) {
        self.id = id
        self.name = name
        self.glyph = glyph
        self.apps = apps
        self.requiresTask = requiresTask
        self.shortcuts = shortcuts
        self.shortcutKey = shortcutKey
        self.icon = icon
    }

    public var resolvedIcon: FontGlyphSelection {
        if let icon { return icon }
        let reference = WorkspaceConfiguration.referenceGlyphs.contains(glyph)
        let font = reference ? GlyphFont(postScriptName: "SFPro-Regular", family: "SF Pro", style: "Regular")
            : GlyphFont(postScriptName: "HackNF-Bold", family: "Hack Nerd Font", style: "Bold")
        return .init(font: font, symbol: WorkspaceConfiguration.symbol(for: glyph) ?? "?")
    }
}

/// Appearance values used by the installed SketchyBar profile. The defaults
/// reproduce the bundled configuration, including its translucent dark bar.
/// Fail closed when a bundled profile no longer contains exactly one setting.
/// Replacing an entire line would lose the shell continuation after blur_radius.
private enum WorkspaceTemplateSetting {
    static func replace(_ source: String, key: String, value: String,
                        exported: Bool = false,
                        sectionStart: String? = nil, sectionEnd: String? = nil) throws -> String {
        let area: Range<String.Index>
        if let sectionStart, let sectionEnd {
            guard let first = source.range(of: sectionStart),
                  let last = source.range(of: sectionEnd,
                                          range: first.upperBound..<source.endIndex) else {
                throw SetupError("Unsupported SketchyBar profile: missing section for \(key).")
            }
            area = first.upperBound..<last.lowerBound
        } else {
            area = source.startIndex..<source.endIndex
        }
        let text = String(source[area])
        let prefix = exported ? "export[ \\t]+" : ""
        let expression = try NSRegularExpression(
            pattern: "(?m)^([ \\t]*" + prefix
                + NSRegularExpression.escapedPattern(for: key)
                + "=[ \\t]*)([^ \\t\\r\\n\\\\#]+)")
        let matches = expression.matches(in: text,
                                         range: NSRange(text.startIndex..<text.endIndex, in: text))
        guard matches.count == 1,
              let valueRange = Range(matches[0].range(at: 2), in: text) else {
            throw SetupError("Unsupported SketchyBar profile: expected one assignment for \(key).")
        }
        return source.replacingCharacters(in: area,
            with: text.replacingCharacters(in: valueRange, with: value))
    }
}

public struct WorkspaceBarStyle: Codable, Equatable {
    public var itemWidth: Int
    public var blurRadius: Int
    public var backgroundColor: String
    public var occupiedColor: String
    public var emptyColor: String

    public init(itemWidth: Int = 21, blurRadius: Int = 50,
                backgroundColor: String = "0x35000000",
                occupiedColor: String = "0xffffffff",
                emptyColor: String = "0x30000000") {
        self.itemWidth = itemWidth
        self.blurRadius = blurRadius
        self.backgroundColor = backgroundColor
        self.occupiedColor = occupiedColor
        self.emptyColor = emptyColor
    }

    /// Render only the three palette values exposed by the workspace editor.
    /// Keep wallpaper-driven HIGHLIGHT_COLOR and other user script settings.
    public func colorsShell(from template: String) throws -> String {
        try validate()
        var rendered = template
        for (key, color) in [
            ("BAR_COLOR", backgroundColor),
            ("BASE_WHITE", occupiedColor),
            ("BASE_GRAY", emptyColor)
        ] {
            rendered = try WorkspaceTemplateSetting.replace(
                rendered, key: key, value: color, exported: true)
        }
        return rendered
    }

    public func validate() throws {
        guard (16...52).contains(itemWidth), (0...100).contains(blurRadius) else {
            throw SetupError("Workspace spacing must be 16–52 and bar blur must be 0–100.")
        }
        for color in [backgroundColor, occupiedColor, emptyColor] {
            guard color.range(of: "^0x[0-9a-fA-F]{8}$",
                              options: .regularExpression) != nil else {
                throw SetupError("SketchyBar colors must be ARGB values such as 0x35000000.")
            }
        }
    }
}

public struct WorkspaceConfiguration: Codable, Equatable {
    public var workspaces: [WorkspaceDefinition]
    public var keymap: WorkspaceKeymap
    public var barStyle: WorkspaceBarStyle

    public init(workspaces: [WorkspaceDefinition], keymap: WorkspaceKeymap = .init(),
                barStyle: WorkspaceBarStyle = .init()) {
        self.workspaces = workspaces
        self.keymap = keymap
        self.barStyle = barStyle
    }

    private enum CodingKeys: String, CodingKey { case workspaces, keymap, barStyle }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try values.decode([WorkspaceDefinition].self, forKey: .workspaces)
        keymap = try values.decodeIfPresent(WorkspaceKeymap.self, forKey: .keymap) ?? .init()
        barStyle = try values.decodeIfPresent(WorkspaceBarStyle.self, forKey: .barStyle) ?? .init()
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(workspaces, forKey: .workspaces)
        try values.encode(keymap, forKey: .keymap)
        try values.encode(barStyle, forKey: .barStyle)
    }

    // Default shortcuts follow the number row. Additional workspaces can use custom shortcuts.
    public static let keys = ["backtick", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "minus", "equal"]
    public static let font = "Hack Nerd Font:Bold:14.5"
    public static let referenceGlyphs: Set<String> = ["robot", "music", "chat", "notes", "clock"]
    public static func font(for glyph: String) -> String {
        referenceGlyphs.contains(glyph) ? "SF Pro:Regular:14.5" : font
    }
    public static func fontFamily(for glyph: String) -> String {
        referenceGlyphs.contains(glyph) ? "SF Pro" : "Hack Nerd Font"
    }

    // Tomito is not a setup dependency, and the timer workspace is optional.
    public static var defaultLayout: WorkspaceConfiguration {
        WorkspaceConfiguration(workspaces: [
            .init(id: "chatgpt", name: "AI", glyph: "robot", apps: ["com.openai.chat", "com.openai.codex"]),
            .init(id: "1", name: "1", glyph: "1"),
            .init(id: "2", name: "2", glyph: "2"),
            .init(id: "3", name: "3", glyph: "3"),
            .init(id: "4", name: "4", glyph: "4"),
            .init(id: "5", name: "5", glyph: "5"),
            .init(id: "6", name: "6", glyph: "6"),
            .init(id: "7", name: "7", glyph: "7"),
            .init(id: "8", name: "8", glyph: "8"),
            .init(id: "music", name: "Music", glyph: "music", apps: ["com.spotify.client"]),
            .init(id: "messages", name: "Messages", glyph: "chat", apps: [
                "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp", "com.apple.MobileSMS"
            ]),
            .init(id: "notes", name: "Notes", glyph: "notes", apps: ["md.obsidian"]),
            .init(id: "timer", name: "Pomodoro", glyph: "clock",
                  apps: ["com.tomito.tomito"], requiresTask: "tomito")
        ])
    }

    /// Optional app choices change routing, not the existence of a workspace.
    /// Installed apps are retained even when their installer task is unchecked.
    public func forSelectedTasks(_ taskIDs: Set<String>?,
                                 installedBundleIDs: Set<String>? = nil) -> WorkspaceConfiguration {
        guard taskIDs != nil || installedBundleIDs != nil else { return self }
        var copy = self
        for index in copy.workspaces.indices {
            copy.workspaces[index].apps.removeAll { bundle in
                switch bundle {
                case "com.tomito.tomito":
                    return !(taskIDs?.contains("tomito") ?? false)
                        && !(installedBundleIDs?.contains(bundle) ?? false)
                case "md.obsidian":
                    return !(taskIDs?.contains("obsidian") ?? false)
                        && !(installedBundleIDs?.contains(bundle) ?? false)
                case "com.spotify.client":
                    return installedBundleIDs.map { !$0.contains(bundle) } ?? false
                default:
                    return false
                }
            }
        }
        return copy
    }

    /// Keep the complete editable layout. Optional workspaces are never hidden.
    public func mergingVisible(_ visible: WorkspaceConfiguration,
                               selectedTasks: Set<String>) throws -> WorkspaceConfiguration {
        try visible.validate()
        return visible
    }

    public static func path(in paths: Paths) -> URL {
        paths.state.appendingPathComponent("workspaces.json")
    }

    public static func load(from paths: Paths) throws -> WorkspaceConfiguration {
        let url = path(in: paths)
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaultLayout }
        let config = try JSONDecoder().decode(WorkspaceConfiguration.self, from: Data(contentsOf: url))
        try config.validate()
        return config
    }

    /// The editor can recover legacy or manually corrupted IDs without
    /// overwriting the user's saved layout. The repaired draft is only saved
    /// when the user explicitly applies it.
    public static func loadForEditing(from paths: Paths) throws
        -> (original: WorkspaceConfiguration, draft: WorkspaceConfiguration, repairs: [String]) {
        let url = path(in: paths)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (.defaultLayout, .defaultLayout, [])
        }
        let original = try JSONDecoder().decode(WorkspaceConfiguration.self, from: Data(contentsOf: url))
        var draft = original
        let repairs = draft.repairWorkspaceIDs()
        try draft.validate()
        return (original, draft, repairs)
    }

    /// Repairs only duplicate or shell-unsafe identifiers. Never changes
    /// valid identifiers, workspace order, app assignments or shortcut keys.
    /// Return messages describing each edit so the UI can explain it.
    @discardableResult
    public mutating func repairWorkspaceIDs() -> [String] {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        func valid(_ id: String) -> Bool {
            !id.isEmpty && id.unicodeScalars.allSatisfy(allowed.contains)
        }
        // Reserve all existing valid IDs so a generated repair cannot steal one.
        let reserved = Set(workspaces.map(\.id).filter(valid))
        var used = Set<String>()
        var repairs: [String] = []
        for index in workspaces.indices {
            let old = workspaces[index].id
            if valid(old) && used.insert(old).inserted { continue }
            let cleaned = old.unicodeScalars.map {
                allowed.contains($0) ? String($0) : "-"
            }.joined()
            let base = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            let root = base.isEmpty ? "workspace" : base
            var candidate = root + "-" + String(index + 1)
            var suffix = 2
            while reserved.contains(candidate) || used.contains(candidate) {
                candidate = root + "-" + String(index + 1) + "-" + String(suffix)
                suffix += 1
            }
            workspaces[index].id = candidate
            used.insert(candidate)
            repairs.append("Workspace '\(workspaces[index].name)' had ID '\(old)'; proposed '\(candidate)'.")
        }
        return repairs
    }

    public func save(to paths: Paths) throws {
        try validate()
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.path(in: paths), options: .atomic)
    }

    public func shortcuts(at index: Int) -> WorkspaceShortcuts {
        let item = workspaces[index]
        let legacyKey: String? = item.shortcuts?.switchTo?.key ?? item.shortcuts?.moveWindow?.key
        let key = item.shortcutKey ?? (item.shortcuts == nil
            ? (Self.keys.indices.contains(index) ? Self.keys[index] : "")
            : (legacyKey ?? ""))
        guard !key.isEmpty else { return .init() }
        return .init(
            switchTo: .init(key: key, modifiers: keymap.switchModifiers),
            moveWindow: .init(key: key, modifiers: keymap.moveModifiers)
        )
    }

    /// Inserts the complete card at a boundary in the current order.
    /// The destination is measured before removing the source item.
    public mutating func insertWorkspace(_ sourceID: String, at destination: Int) {
        guard let source = workspaces.firstIndex(where: { $0.id == sourceID }),
              (0...workspaces.count).contains(destination) else { return }
        // Materialize inherited keys before moving a workspace. Reordering
        // must not unexpectedly assign it a different keyboard shortcut.
        for index in workspaces.indices where workspaces[index].shortcutKey == nil
            && workspaces[index].shortcuts == nil {
            workspaces[index].shortcutKey = Self.keys.indices.contains(index)
                ? Self.keys[index] : ""
        }
        let item = workspaces.remove(at: source)
        let index = min(workspaces.count, destination > source ? destination - 1 : destination)
        workspaces.insert(item, at: index)
    }

    /// Move before the destination while preserving the entire workspace card.
    public mutating func moveWorkspace(_ sourceID: String, to targetID: String, selectedTasks: Set<String>? = nil) {
        guard let destination = workspaces.firstIndex(where: { $0.id == targetID }) else { return }
        insertWorkspace(sourceID, at: destination)
    }

    public func validate(aerospaceTemplate: String? = nil, checkingShortcutsFor workspaceID: String? = nil) throws {
        try barStyle.validate()
        guard !workspaces.isEmpty else {
            throw SetupError("Keep at least one workspace.")
        }
        try keymap.validate()
        var names = Set<String>()
        var applications = Set<String>()
        let allowedID = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let allowedApp = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        for item in workspaces {
            guard !item.id.isEmpty && item.id.unicodeScalars.allSatisfy(allowedID.contains) else {
                throw SetupError("Workspace '\(item.name)' has invalid ID '\(item.id)'. Use only letters, numbers, _ or -. Repair IDs in Workspaces.")
            }
            guard names.insert(item.id).inserted else {
                throw SetupError("Workspace ID '\(item.id)' is used more than once. Repair IDs in Workspaces.")
            }
            guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SetupError("Workspace names cannot be empty or contain control characters.")
            }
            guard item.icon != nil || Self.symbol(for: item.glyph) != nil else {
                throw SetupError("Unknown glyph '\(item.glyph)' for workspace '\(item.id)'.")
            }
            try item.resolvedIcon.validate()
            for app in item.apps {
                guard !app.isEmpty && app.unicodeScalars.allSatisfy(allowedApp.contains),
                      applications.insert(app).inserted else {
                    throw SetupError("Each valid app bundle ID can be assigned to only one workspace.")
                }
            }
        }
        var used: [String: (label: String, workspaceID: String?)] = [:]
        if let aerospaceTemplate {
            // Reserve bindings that survive workspace generation, using the actual template.
            let remaining = try Self.replace(aerospaceTemplate, from: "# Workspaces\n", to: "# Resize\n", with: "")
            var inMainMode = false
            for line in remaining.components(separatedBy: .newlines) {
                let line = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") { inMainMode = line == "[mode.main.binding]" }
                guard inMainMode, let equal = line.firstIndex(of: "=") else { continue }
                let key = line[..<equal].trimmingCharacters(in: .whitespaces)
                if let shortcut = WorkspaceShortcut.parse(key) {
                    used[shortcut.binding] = ("an existing AeroSpace action", nil)
                }
            }
        }
        for (index, item) in workspaces.enumerated() {
            let pair = shortcuts(at: index)
            for (action, shortcut) in [("Switch to", pair.switchTo), ("Move window to", pair.moveWindow)] {
                guard let shortcut else { continue }
                try shortcut.validate()
                if let owner = used[shortcut.binding], workspaceID == nil || item.id == workspaceID || owner.workspaceID == workspaceID {
                    throw SetupError("\(shortcut.display) for \(action) \(item.name) is already used by \(owner.label). Choose another shortcut.")
                }
                used[shortcut.binding] = ("\(action) \(item.name)", item.id)
            }
        }
    }

    public static func symbol(for glyph: String) -> String? {
        if glyph.count == 1, glyph.first?.isNumber == true { return glyph }
        return WorkspaceGlyph.all.first(where: { $0.name == glyph })?.symbol
    }

    private static func replace(_ original: String, from start: String, to end: String,
                                with replacement: String) throws -> String {
        guard let startRange = original.range(of: start),
              let endRange = original.range(of: end, range: startRange.upperBound..<original.endIndex) else {
            throw SetupError("Unsupported profile version: expected template markers were not found.")
        }
        let separator = end.hasPrefix("\n") || replacement.hasSuffix("\n") ? "" : "\n"
        return String(original[..<startRange.lowerBound]) + replacement + separator
            + String(original[endRange.lowerBound...])
    }

    public func aerospaceTOML(from template: String, geometry: DisplayGeometry = .current()) throws -> String {
        try validate(aerospaceTemplate: template)
        var result = geometry.applying(to: template)
        let ids = workspaces.map { "    \"\($0.id)\"," }.joined(separator: "\n")
        result = try Self.replace(result, from: "persistent-workspaces = [", to: "\n]\n",
            with: "persistent-workspaces = [\n\(ids)")
        let initial = workspaces.contains(where: { $0.id == "1" }) ? "1" : workspaces[0].id
        result = result.replacingOccurrences(of: "layout --workspace 1 --root tiles",
                                               with: "layout --workspace \(initial) --root tiles")
        let shortcuts = workspaces.enumerated().compactMap { index, item -> String? in
            guard let shortcut = self.shortcuts(at: index).switchTo else { return nil }
            return "\(shortcut.binding) = 'workspace \(item.id)'"
        }.joined(separator: "\n")
        let moves = workspaces.enumerated().compactMap { index, item -> String? in
            guard let shortcut = self.shortcuts(at: index).moveWindow else { return nil }
            return "\(shortcut.binding) = ['move-node-to-workspace \(item.id)', 'exec-and-forget sketchybar --trigger aerospace_workspace_change']"
        }.joined(separator: "\n")
        let bindings = """
        # Workspaces
        # Switch and move modifiers are shared; workspace keys are configured in Mac Setup.
        # ------------------------------------------------------------

        \(shortcuts)

        # Move window to workspace
        # The same key is used for switch and move, with separate global modifiers.

        \(moves)

        # ------------------------------------------------------------
        """
        result = try Self.replace(result, from: "# Workspaces\n", to: "# Resize\n", with: bindings)
        let rules = workspaces.flatMap { item in item.apps.map { app in
            """
            [[on-window-detected]]
            if = 'test %{app-bundle-id} = \(app)'
            run = ['move-node-to-workspace \(item.id)', 'exec-and-forget sketchybar --trigger aerospace_workspace_change']

            """
        } }.joined(separator: "\n")
        let appSection = """
        # APP ASSIGNMENTS
        # ============================================================

        # Preserve explicit tiling rules from the public dotfiles.
        [[on-window-detected]]
        if = 'test %{app-bundle-id} = com.apple.ScreenContinuity'
        run = 'layout tiling'

        [[on-window-detected]]
        if = 'test %{app-bundle-id} = com.apple.systempreferences'
        run = 'layout tiling'

        \(rules)

        # ============================================================
        """
        result = try Self.replace(result, from: "# APP ASSIGNMENTS\n", to: "# MONITOR ASSIGNMENTS\n",
                                  with: appSection)
        if !workspaces.contains(where: { $0.id == "2" }) {
            result = result.replacingOccurrences(of: "2 = 'secondary'", with: "")
        }
        try Self.verifyGeneratedBindings(result)
        return result
    }

    /// Reject equivalent modifier permutations before writing AeroSpace TOML.
    public static func verifyGeneratedBindings(_ toml: String) throws {
        var inMain = false
        var seen: [String: String] = [:]
        for raw in toml.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "[mode.main.binding]" { inMain = true; continue }
            if inMain && line.hasPrefix("[") { break }
            guard inMain, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let source = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            guard let key = WorkspaceShortcut.parse(source)?.binding else { continue }
            if let previous = seen.updateValue(source, forKey: key) {
                throw SetupError("AeroSpace binding \(source) duplicates \(previous). Change one shortcut before applying.")
            }
        }
    }

    public func sketchybarShell(from template: String) throws -> String {
        try validate()
        let icons = workspaces.map { item in
            return "    \(item.id)) printf '%s\\n' \(Self.shellQuote(item.resolvedIcon.symbol)) ;;"
        }.joined(separator: "\n")
        let fonts = workspaces.map { "    \($0.id)) printf '%s\\n' \(Self.shellQuote($0.resolvedIcon.font.sketchybarFont)) ;;" }.joined(separator: "\n")
        let section = """
        ##### Workspace Icons #####

        # Each workspace uses its selected Unicode character and font face.
        workspace_icon() {
          case "$1" in
        \(icons)
            *) printf '%s\\n' "$1" ;;
          esac
        }

        workspace_font() {
          case "$1" in
        \(fonts)
            *) printf '%s\\n' '\(Self.font)' ;;
          esac
        }

        """
        var rendered = try Self.replace(template, from: "##### Workspace Icons #####\n",
                                to: "# Read workspace names and order directly from AeroSpace\n",
                                with: section + "##### AeroSpace Workspaces #####\n\nsketchybar --add event aerospace_workspace_change\n\n# ------------------------------------------------------------\n")
        // Workspaces are created in the user's saved order. Relying on a live
        // AeroSpace socket here previously left the bar in an old order while
        // the tiling manager restarted or pointed at a different config.
        let orderedIDs = workspaces.map { Self.shellQuote($0.id) }.joined(separator: " ")
        rendered = try Self.replace(rendered,
                                    from: "# Read workspace names and order directly from AeroSpace\n",
                                    to: "# Create workspace items\n",
                                    with: "# Workspace order follows workspaces.json\nworkspace_ids=(\(orderedIDs))\n\n")
        rendered = try WorkspaceTemplateSetting.replace(
            rendered, key: "label.width", value: String(barStyle.itemWidth),
            sectionStart: "# Create workspace items\n", sectionEnd: "##### Clock #####")
        rendered = try WorkspaceTemplateSetting.replace(
            rendered, key: "blur_radius", value: String(barStyle.blurRadius))
        return DisplayGeometry.barShell(rendered)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
