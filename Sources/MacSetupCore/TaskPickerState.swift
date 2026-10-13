import Foundation

/// Selection policy shared by the terminal UI and scripted presets.
public enum SetupPreset: String, CaseIterable {
    case minimal, productivity, developer, complete

    public var title: String { rawValue.capitalized }

    public var summary: String {
        switch self {
        case .complete: return "All setup tasks, including permissions and checks"
        case .minimal: return "Homebrew, fonts, dark mode, and Git ignores"
        case .productivity: return "Windows, applications, and macOS appearance"
        case .developer: return "Terminal, shell history, fonts, and Git"
        }
    }

    public func ids(in tasks: [SetupTask]) -> Set<String> {
        let ids: Set<String>
        switch self {
        case .complete:
            ids = Set(tasks.map(\.id))
        case .minimal:
            ids = ["homebrew", "fonts", "dark-mode", "git-ignore"]
        case .productivity:
            ids = Set(tasks.filter {
                ["Window management", "Apps", "Appearance", "Finder"].contains($0.category)
            }.map(\.id)).union(["dotfiles-linked"])
        case .developer:
            ids = ["homebrew", "fonts", "dotfiles-linked", "alacritty", "alacritty-profile",
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

    public var visibleTasks: [SetupTask] {
        tasks.filter { task in
            (categoryIndex == 0 || task.category == category) &&
            (query.isEmpty || [task.id, task.title, task.summary, task.category]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
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
