import SwiftUI
import MacSetupCore

struct WorkspaceShortcutEditor: View {
    let name: String
    let defaults: WorkspaceShortcuts
    let validate: (WorkspaceShortcuts?) -> String?
    let save: (WorkspaceShortcuts?) -> Void
    @Environment(\.dismiss) private var dismiss
    @LocalViewState private var mode: Int
    @LocalViewState private var switchEnabled: Bool
    @LocalViewState private var moveEnabled: Bool
    @LocalViewState private var switchShortcut: WorkspaceShortcut
    @LocalViewState private var moveShortcut: WorkspaceShortcut
    @LocalViewState private var error = ""

    init(workspace: WorkspaceDefinition, defaults: WorkspaceShortcuts,
         validate: @escaping (WorkspaceShortcuts?) -> String?, save: @escaping (WorkspaceShortcuts?) -> Void) {
        name = workspace.name
        self.defaults = defaults
        self.validate = validate
        self.save = save
        let pair = workspace.shortcuts ?? defaults
        _mode = LocalViewState(initialValue: workspace.shortcuts == nil ? 0 :
            pair.switchTo == nil && pair.moveWindow == nil ? 2 : 1)
        _switchEnabled = LocalViewState(initialValue: pair.switchTo != nil || workspace.shortcuts == nil)
        _moveEnabled = LocalViewState(initialValue: pair.moveWindow != nil || workspace.shortcuts == nil)
        _switchShortcut = LocalViewState(initialValue: pair.switchTo ?? .init(key: "a", modifiers: ["ctrl", "alt"]))
        _moveShortcut = LocalViewState(initialValue: pair.moveWindow ?? .init(key: "a", modifiers: ["ctrl", "alt", "shift"]))
    }

    private var value: WorkspaceShortcuts? {
        if mode == 0 { return nil }
        if mode == 2 { return .init() }
        return .init(switchTo: switchEnabled ? switchShortcut : nil,
                     moveWindow: moveEnabled ? moveShortcut : nil)
    }

    private var validationMessage: String? { validate(value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shortcuts for \(name)").font(SetupDesign.sheetTitle)
            Picker("Shortcut mode", selection: $mode) {
                Text("Default number row").tag(0)
                Text("Custom").tag(1)
                Text("No shortcuts").tag(2)
            }.pickerStyle(.segmented)
            if mode == 0 {
                if let shortcut = defaults.switchTo {
                    Text("Switch to: \(shortcut.display)")
                    Text("Move window: \(defaults.moveWindow?.display ?? "None")")
                    Text("Default shortcuts follow workspace order. Custom shortcuts stay with their workspace when reordered.").foregroundStyle(.secondary)
                } else {
                    Text("All 13 number-row positions are occupied. Choose Custom to assign another combination, or use the workspace's bar icon.")
                }
            } else if mode == 1 {
                WorkspaceShortcutFields(title: "Switch to this workspace", enabled: $switchEnabled, shortcut: $switchShortcut)
                Divider()
                WorkspaceShortcutFields(title: "Move window to this workspace", enabled: $moveEnabled, shortcut: $moveShortcut)
                Text("Choose at least one modifier and a key. Switch and move combinations can be different.").foregroundStyle(.secondary)
            } else {
                Text("This workspace stays in the bar and can receive assigned apps. Click its bar icon to switch to it.")
            }
            if let message = validationMessage {
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save shortcuts") {
                    if let message = validate(value) { error = message; return }
                    save(value); dismiss()
                }.disabled(validationMessage != nil).keyboardShortcut(.defaultAction)
            }
        }.padding(24).font(SetupDesign.body).frame(width: 600, height: 540)
    }
}

private struct WorkspaceShortcutFields: View {
    let title: String
    @Binding var enabled: Bool
    @Binding var shortcut: WorkspaceShortcut

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(title, isOn: $enabled).toggleStyle(.checkbox).fontWeight(.medium)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ForEach(["ctrl", "alt", "shift", "cmd"], id: \.self) { modifier in
                        Toggle(["ctrl": "Control", "alt": "Option", "shift": "Shift", "cmd": "Command"][modifier]!, isOn: Binding(
                            get: { shortcut.modifiers.contains(modifier) },
                            set: { on in
                                shortcut.modifiers.removeAll { $0 == modifier }
                                if on { shortcut.modifiers.append(modifier) }
                            }))
                        .toggleStyle(.checkbox).accessibilityLabel("\(title): \(modifier)")
                    }
                }
                HStack {
                    Picker("Key", selection: $shortcut.key) {
                        ForEach(WorkspaceShortcut.keyGroups.indices, id: \.self) { i in
                            Section(WorkspaceShortcut.keyGroups[i].name) {
                                ForEach(WorkspaceShortcut.keyGroups[i].keys, id: \.self) { key in
                                    Text(WorkspaceShortcut.keyLabel(key)).tag(key)
                                }
                            }
                        }
                    }.frame(width: 260).accessibilityLabel("\(title): key")
                    Spacer()
                    Text(shortcut.display).font(.system(.body, design: .monospaced))
                }
            }.disabled(!enabled).opacity(enabled ? 1 : 0.5)
        }
    }
}
