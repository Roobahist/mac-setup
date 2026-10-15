import Foundation

/// Resolve the exact settings represented by a full setup's selected tasks.
/// Used by review, initial apply and resume so they cannot save different scopes.
public struct SelectedConfiguration {
    public let layout: WorkspaceConfiguration?
    public let shortcuts: ShortcutSettings?

    public init(taskIDs: Set<String>, draftLayout: WorkspaceConfiguration,
                draftShortcuts: ShortcutSettings, savedLayout: WorkspaceConfiguration,
                savedShortcuts: ShortcutSettings) {
        let workspaceSelected = taskIDs.contains("aerospace-profile")
        let barSelected = taskIDs.contains("sketchybar-profile")
        var layout = savedLayout
        if workspaceSelected {
            layout.workspaces = draftLayout.workspaces
            layout.keymap = draftLayout.keymap
        }
        if barSelected { layout.barStyle = draftLayout.barStyle }
        self.layout = workspaceSelected || barSelected ? layout : nil

        let providers = Set(taskIDs.compactMap { id -> ShortcutProvider? in
            switch id {
            case "aerospace-profile": return .aerospace
            case "karabiner-profile": return .karabiner
            case "raycast-profile": return .raycast
            default: return nil
            }
        })
        guard !providers.isEmpty else { shortcuts = nil; return }
        var shortcuts = savedShortcuts
        shortcuts.entries = ShortcutProvider.allCases.flatMap { provider in
            (providers.contains(provider) ? draftShortcuts : savedShortcuts).entries.filter { $0.provider == provider }
        }
        if providers.contains(.karabiner) { shortcuts.advancedKarabiner = draftShortcuts.advancedKarabiner }
        self.shortcuts = shortcuts
    }
}
