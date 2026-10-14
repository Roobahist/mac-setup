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

    // Every selectable glyph is supplied by Hack Nerd Font, the workspace font.
    public static let all: [WorkspaceGlyph] = [
        .init("0", "0", "number zero"), .init("1", "1", "number one"),
        .init("2", "2", "number two"), .init("3", "3", "number three"),
        .init("4", "4", "number four"), .init("5", "5", "number five"),
        .init("6", "6", "number six"), .init("7", "7", "number seven"),
        .init("8", "8", "number eight"), .init("9", "9", "number nine"),
        .init("robot", "󰚩", "ai assistant chatgpt"), .init("terminal", "󰆍", "shell command"),
        .init("code", "󰅨", "developer editor vscode"), .init("file", "󰉋", "finder folder"),
        .init("git", "󰊢", "source version"), .init("tasks", "󱃔", "list todo"),
        .init("weather", "󰖕", "sun cloud"), .init("mail", "󰇮", "email inbox"),
        .init("calculator", "󰪚", "math"), .init("map", "󰆋", "navigation location"),
        .init("microphone", "󰍬", "audio recording"), .init("chat", "󰍩", "messages telegram whatsapp"),
        .init("video call", "󰍫", "zoom meetings"), .init("notes", "󱞎", "writing obsidian"),
        .init("camera", "󰄀", "photo"), .init("web", "󰇧", "browser safari chrome"),
        .init("home", "󱉑", "house automation"), .init("music", "󰎄", "spotify tunes"),
        .init("podcast", "󰦔", "radio"), .init("play", "󱉺", "video television"),
        .init("book", "󰂿", "reading"), .init("dictionary", "󱁯", "reference"),
        .init("preview", "󰋲", "image screenshot"), .init("password", "󰷡", "security key"),
        .init("download", "󱑢", "transfer"), .init("cast", "󱒃", "airplay"),
        .init("table", "󰓫", "excel spreadsheet"), .init("presentation", "󰈩", "slides"),
        .init("cloud", "󰅧", "drive backup"), .init("pen", "󰏬", "design drawing"),
        .init("desktop", "󰢹", "monitor remote"), .init("clock", "󰥔", "timer pomodoro"),
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

    public init(id: String, name: String, glyph: String, apps: [String] = [], requiresTask: String? = nil) {
        self.id = id
        self.name = name
        self.glyph = glyph
        self.apps = apps
        self.requiresTask = requiresTask
    }
}

public struct WorkspaceConfiguration: Codable, Equatable {
    public var workspaces: [WorkspaceDefinition]

    public init(workspaces: [WorkspaceDefinition]) { self.workspaces = workspaces }

    // The layout supports AeroSpace's familiar Option+key navigation.
    public static let keys = ["backtick", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "minus", "equal"]
    public static let font = "Hack Nerd Font:Bold:14.5"

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

    /// Hide only optional default workspaces whose application task was unchecked.
    /// This does not delete unrelated workspaces, and does not mutate saved settings.
    public func forSelectedTasks(_ taskIDs: Set<String>?) -> WorkspaceConfiguration {
        guard let taskIDs else { return self }
        return WorkspaceConfiguration(workspaces: workspaces.filter {
            $0.requiresTask.map(taskIDs.contains) ?? true
        })
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

    public func save(to paths: Paths) throws {
        try validate()
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.path(in: paths), options: .atomic)
    }

    public func validate() throws {
        guard !workspaces.isEmpty && workspaces.count <= Self.keys.count else {
            throw SetupError("Choose 1 to \(Self.keys.count) workspaces.")
        }
        var names = Set<String>()
        var applications = Set<String>()
        let allowedID = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let allowedApp = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        for item in workspaces {
            guard !item.id.isEmpty && item.id.unicodeScalars.allSatisfy(allowedID.contains),
                  names.insert(item.id).inserted else {
                throw SetupError("Workspace IDs must be unique and contain only letters, numbers, _ or -.")
            }
            guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SetupError("Workspace names cannot be empty or contain control characters.")
            }
            guard Self.symbol(for: item.glyph) != nil else {
                throw SetupError("Unknown glyph '\(item.glyph)' for workspace '\(item.id)'.")
            }
            for app in item.apps {
                guard !app.isEmpty && app.unicodeScalars.allSatisfy(allowedApp.contains),
                      applications.insert(app).inserted else {
                    throw SetupError("Each valid app bundle ID can be assigned to only one workspace.")
                }
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

    public func aerospaceTOML(from template: String) throws -> String {
        try validate()
        var result = template
        let ids = workspaces.map { "    \"\($0.id)\"," }.joined(separator: "\n")
        result = try Self.replace(result, from: "persistent-workspaces = [", to: "\n]\n",
            with: "persistent-workspaces = [\n\(ids)")
        let initial = workspaces.contains(where: { $0.id == "1" }) ? "1" : workspaces[0].id
        result = result.replacingOccurrences(of: "layout --workspace 1 --root tiles",
                                               with: "layout --workspace \(initial) --root tiles")
        let shortcuts = workspaces.enumerated().map { index, item -> String in
            let key = Self.keys[index]
            return "alt-\(key) = 'workspace \(item.id)'"
        }.joined(separator: "\n")
        let moves = workspaces.enumerated().map { index, item -> String in
            let key = Self.keys[index]
            return "alt-shift-\(key) = ['move-node-to-workspace \(item.id)', 'exec-and-forget sketchybar --trigger aerospace_workspace_change']"
        }.joined(separator: "\n")
        let bindings = """
        # Workspaces
        # Option + workspace key
        # ------------------------------------------------------------

        \(shortcuts)

        # Move window to workspace
        # Option + Shift + workspace key

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

        # Keep macOS system dialogs tiled.
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
        return result
    }

    public func sketchybarShell(from template: String) throws -> String {
        try validate()
        let icons = workspaces.map { item in
            let symbol = Self.symbol(for: item.glyph)!
            return "    \(item.id)) printf '%s\\n' '\(symbol)' ;;"
        }.joined(separator: "\n")
        let section = """
        ##### Workspace Icons #####

        # Custom workspace icons use Hack Nerd Font. Layout is saved locally.
        workspace_icon() {
          case "$1" in
        \(icons)
            *) printf '%s\\n' "$1" ;;
          esac
        }

        workspace_font() {
          printf '%s\\n' '\(Self.font)'
        }

        """
        return try Self.replace(template, from: "##### Workspace Icons #####\n",
                                to: "##### AeroSpace Workspaces #####\n", with: section)
    }
}
