import Foundation

/// Selection policy shared by the terminal UI and scripted presets.
public enum SetupPreset: String, CaseIterable {
    case repair, minimal, productivity, developer, complete

    public var title: String { rawValue.capitalized }

    public var summary: String {
        switch self {
        case .repair: return "Repair the workspace bar, Dock, launcher and keyboard setup"
        case .complete: return "All setup tasks, including permissions and checks"
        case .minimal: return "Homebrew, fonts, dark mode, and Git ignores"
        case .productivity: return "Windows, applications, and macOS appearance"
        case .developer: return "Terminal, shell history, fonts, and Git"
        }
    }

    public func ids(in tasks: [SetupTask]) -> Set<String> {
        let ids: Set<String>
        switch self {
        case .repair:
            ids = ["fonts", "tomito", "obsidian", "aerospace-profile", "mission-control", "aerospace-access",
                   "sketchybar-profile", "sketchybar-start", "vorssaint-profile", "vorssaint-access",
                   "raycast-profile", "raycast-access", "karabiner-profile", "karabiner-access",
                   "dock-hide", "menu-bar"]
        case .complete:
            // Terminal choice is explicit: disabled casks must not break a full setup.
            let optIn: Set<String> = ["alacritty", "alacritty-profile", "ghostty", "wezterm", "kitty", "finder-reset-views"]
            ids = Set(tasks.map(\.id)).subtracting(optIn)
        case .minimal:
            ids = ["homebrew", "fonts", "dark-mode", "git-ignore"]
        case .productivity:
            ids = Set(tasks.filter {
                ["Window management", "Apps", "Appearance", "Finder"].contains($0.category)
            }.map(\.id)).union(["dotfiles-linked"])
        case .developer:
            ids = ["homebrew", "fonts", "dotfiles-linked",
                   "atuin", "atuin-profile", "atuin-shell", "git-ignore"]
        }
        return ids.intersection(Set(tasks.map(\.id)))
    }
}

public struct TaskPickerState {
    public let tasks: [SetupTask]
    public private(set) var selected: Set<String>
    public private(set) var updates = Set<String>()
    public var available = Set<String>()
    public var unknown = Set<String>()
    public private(set) var categoryIndex = 0
    public private(set) var cursorIndex = 0
    public private(set) var query = ""
    public private(set) var preset: SetupPreset?

    public init(tasks: [SetupTask] = Catalog.tasks, preset: SetupPreset = .complete) {
        self.tasks = tasks
        self.preset = preset
        self.selected = Self.withDependencies(preset.ids(in: tasks), in: tasks)
    }

    public var categories: [String] {
        ["All"] + tasks.reduce(into: [String]()) { result, task in
            if !result.contains(task.category) { result.append(task.category) }
        }
    }

    public var category: String { categories[categoryIndex] }

    /// Show each task once beneath its first prerequisite. Other prerequisites
    /// remain explicit in the row, since dependencies form a graph rather than a tree.
    public var visibleTasks: [SetupTask] {
        let visible = tasks.filter { task in
            (categoryIndex == 0 || task.category == category) &&
            (query.isEmpty || [task.id, task.title, task.summary, task.category]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
        let visibleIDs = Set(visible.map(\.id))
        var result: [SetupTask] = []
        var visited = Set<String>()
        func append(_ task: SetupTask) {
            guard visited.insert(task.id).inserted else { return }
            result.append(task)
            for child in visible where child.dependencies.first == task.id { append(child) }
        }
        for task in visible where task.dependencies.first.map({ !visibleIDs.contains($0) }) ?? true { append(task) }
        // Defensive fallback for an invalid cycle: keep every task accessible.
        for task in visible { append(task) }
        return result
    }

    public func hierarchyPrefix(for task: SetupTask) -> String {
        let visible = visibleTasks
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        var path = [task]
        var visited: Set<String> = [task.id]
        while let parent = path.last?.dependencies.first, let ancestor = byID[parent], visited.insert(parent).inserted {
            path.append(ancestor)
        }
        path.reverse()
        guard path.count > 1 else { return "" }
        func isLast(_ node: SetupTask) -> Bool {
            visible.last(where: { $0.dependencies.first == node.dependencies.first })?.id == node.id
        }
        let guides = path.dropFirst().dropLast().map { isLast($0) ? "    " : "│   " }.joined()
        return guides + (isLast(task) ? "└── " : "├── ")
    }

    public func hierarchySpacer(after task: SetupTask, before next: SetupTask) -> String? {
        let currentPrefix = hierarchyPrefix(for: task)
        let nextPrefix = hierarchyPrefix(for: next)
        let opensGroup = currentPrefix.isEmpty && !nextPrefix.isEmpty
        let endsLeafSibling = !currentPrefix.isEmpty && currentPrefix.count == nextPrefix.count &&
            !visibleTasks.contains { $0.dependencies.first == task.id }
        guard currentPrefix.count > nextPrefix.count || opensGroup || endsLeafSibling else { return nil }
        return nextPrefix.isEmpty ? "" : String(nextPrefix.dropLast(4)) + "│"
    }

    public var focusedTask: SetupTask? {
        let visible = visibleTasks
        return visible.indices.contains(cursorIndex) ? visible[cursorIndex] : nil
    }

    public var orderedSelection: [String] {
        tasks.filter { selected.contains($0.id) }.map(\.id)
    }

    public var selectedCount: Int { selected.count }

    public mutating func move(_ offset: Int) {
        let count = visibleTasks.count
        guard count > 0 else { cursorIndex = 0; return }
        cursorIndex = ((cursorIndex + offset) % count + count) % count
    }

    public mutating func cycleCategory(_ direction: Int = 1) {
        let count = categories.count
        categoryIndex = ((categoryIndex + direction) % count + count) % count
        cursorIndex = 0
    }

    public mutating func appendSearch(_ character: Character) {
        query.append(character)
        cursorIndex = 0
    }

    public mutating func removeSearchCharacter() {
        if !query.isEmpty { query.removeLast() }
        cursorIndex = 0
    }

    public mutating func clearSearch() {
        query = ""
        cursorIndex = 0
    }

    public mutating func choose(_ preset: SetupPreset) {
        self.preset = preset
        selected = Self.withDependencies(preset.ids(in: tasks), in: tasks)
        updates.removeAll()
        cursorIndex = 0
    }

    public mutating func toggleFocused() {
        guard let task = focusedTask else { return }
        toggle(task.id)
    }

    public mutating func toggle(_ id: String) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        if selected.contains(id) {
            selected.remove(id)
            removeUnsatisfiedChildren()
        } else {
            selected.formUnion(Self.withDependencies([id], in: tasks, available: available.union(unknown)))
        }
        updates.formIntersection(selected)
        preset = nil
    }

    public mutating func toggleVisible() {
        let ids = Set(visibleTasks.map(\.id))
        guard !ids.isEmpty else { return }
        if ids.isSubset(of: selected) {
            selected.subtract(ids)
            removeUnsatisfiedChildren()
        } else {
            selected.formUnion(Self.withDependencies(ids, in: tasks, available: available.union(unknown)))
        }
        updates.formIntersection(selected)
        preset = nil
    }

    public mutating func toggleUpdate(_ id: String) {
        guard available.contains(id), tasks.first(where: { $0.id == id })?.updatable == true else { return }
        if updates.contains(id) { updates.remove(id) }
        else {
            selected.formUnion(Self.withDependencies([id], in: tasks, available: available.union(unknown)))
            updates.insert(id)
        }
        preset = nil
    }

    private mutating func removeUnsatisfiedChildren() {
        var changed = true
        while changed {
            changed = false
            for task in tasks where selected.contains(task.id) {
                if task.dependencies.contains(where: { !selected.contains($0) && !available.contains($0) && !unknown.contains($0) }) {
                    selected.remove(task.id)
                    changed = true
                }
            }
        }
    }

    private static func withDependencies(_ ids: Set<String>, in tasks: [SetupTask], available: Set<String> = []) -> Set<String> {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var result = ids
        var pending = Array(ids)
        while let next = pending.popLast() {
            guard let task = byID[next] else { continue }
            for dependency in task.dependencies where !available.contains(dependency) && result.insert(dependency).inserted {
                pending.append(dependency)
            }
        }
        return result
    }
}
