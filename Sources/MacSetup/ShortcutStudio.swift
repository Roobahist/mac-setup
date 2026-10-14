import SwiftUI
import MacSetupCore

/// A single editor for the shortcuts that Mac Setup writes to the three
/// providers. Complex Karabiner sequences remain in its original profile.
struct ShortcutStudio: View {
    @Binding var settings: ShortcutSettings
    @Binding var layout: WorkspaceConfiguration
    let apps: [InstalledApplication]
    let aerospaceTemplate: String
    @State private var editing: ManagedShortcut?

    private var aerospaceActions: [(title: String, action: String)] {
        var seen = Set<String>()
        return ShortcutSettings.bundledAeroSpaceBindings(aerospaceTemplate).compactMap { _, action in
            guard seen.insert(action).inserted else { return nil }
            return (ShortcutSettings.actionTitle(action, provider: .aerospace), action)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Keyboard shortcuts").font(.title2.bold())
                Spacer()
                Text("\(settings.entries.filter(\.enabled).count) active")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Every standard shortcut managed by this setup is listed below. Select a shortcut to change its keys or action, switch it off, or add another.")
                .foregroundStyle(.secondary)

            workspaceSection

            ForEach(ShortcutProvider.allCases, id: \.self) { provider in
                providerSection(provider)
            }
            Text("AeroSpace manages window commands, Karabiner handles application shortcuts, and Raycast exposes one launcher hotkey. Advanced Karabiner state-based and sequence rules are preserved in its Portable profile.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .sheet(item: $editing) { item in
            ShortcutItemEditor(item: item, aerospaceActions: aerospaceActions, apps: apps,
                               validate: { candidate in
                var updated = settings
                if let index = updated.entries.firstIndex(where: { $0.id == candidate.id }) {
                    updated.entries[index] = candidate
                } else {
                    updated.entries.append(candidate)
                }
                do {
                    try updated.validate(workspaces: layout, aerospaceTemplate: aerospaceTemplate)
                    return nil
                } catch { return String(describing: error) }
            }, save: { candidate in
                if let index = settings.entries.firstIndex(where: { $0.id == candidate.id }) {
                    settings.entries[index] = candidate
                } else {
                    settings.entries.append(candidate)
                }
                editing = nil
            }, cancel: { editing = nil })
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Workspace destinations", systemImage: "square.grid.2x2")
                    .font(.headline)
                Spacer()
                Text("AeroSpace").font(.caption).foregroundStyle(.tertiary)
            }
            Text("The modifier sets apply to every workspace. Destination keys are chosen on the next screen.")
                .font(.callout).foregroundStyle(.secondary)
            modifierRow("Switch to workspace", modifiers: $layout.keymap.switchModifiers)
            modifierRow("Move window to workspace", modifiers: $layout.keymap.moveModifiers)
            Divider()
            ForEach(Array(layout.workspaces.enumerated()), id: \.element.id) { index, item in
                let pair = layout.shortcuts(at: index)
                HStack(spacing: 12) {
                    Text(item.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(pair.switchTo?.display ?? "No key")
                        .frame(width: 94, alignment: .trailing)
                    Text(pair.moveWindow?.display ?? "No key")
                        .frame(width: 108, alignment: .trailing)
                }
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func modifierRow(_ title: String, modifiers: Binding<[String]>) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 192, alignment: .leading).fontWeight(.medium)
            ForEach(WorkspaceShortcut.modifierNames, id: \.self) { modifier in
                Toggle(["cmd": "⌘", "ctrl": "⌃", "alt": "⌥", "shift": "⇧"][modifier]!,
                    isOn: Binding(
                        get: { modifiers.wrappedValue.contains(modifier) },
                        set: { selected in
                            var value = modifiers.wrappedValue
                            value.removeAll { $0 == modifier }
                            if selected { value.append(modifier) }
                            modifiers.wrappedValue = value
                        }))
                .toggleStyle(.checkbox).accessibilityLabel("\(title): \(modifier)")
            }
        }
    }

    private func providerSection(_ provider: ShortcutProvider) -> some View {
        let entries = settings.entries.filter { $0.provider == provider }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(provider.rawValue).font(.headline)
                Text("\(entries.count) shortcuts").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if provider != .raycast {
                    Button {
                        let action = provider == .aerospace ? (aerospaceActions.first?.action ?? "[]") : "Alacritty"
                        editing = ManagedShortcut(provider: provider, action: action,
                                                  shortcut: .init(key: "f12", modifiers: ["ctrl", "alt", "shift"]))
                    } label: { Label("Add shortcut", systemImage: "plus") }
                }
            }
            ForEach(entries) { entry in
                shortcutRow(entry)
                if entry.id != entries.last?.id { Divider().opacity(0.5) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func shortcutRow(_ entry: ManagedShortcut) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ShortcutSettings.actionTitle(entry.action, provider: entry.provider))
                    .fontWeight(.medium).lineLimit(1)
                Text(entry.provider.rawValue).font(.caption2).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.shortcut.display)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 116, alignment: .trailing)
                .foregroundStyle(entry.enabled ? .primary : .secondary)
            Toggle("Enabled", isOn: Binding(
                get: { settings.entries.first(where: { $0.id == entry.id })?.enabled ?? false },
                set: { enabled in
                    guard let i = settings.entries.firstIndex(where: { $0.id == entry.id }) else { return }
                    settings.entries[i].enabled = enabled
                }))
                .labelsHidden().disabled(entry.provider == .raycast)
            Button { editing = entry } label: { Image(systemName: "slider.horizontal.3") }
                .help("Edit shortcut").accessibilityLabel("Edit \(entry.action)")
                .frame(width: 32, height: 32)
            if entry.provider != .raycast {
                Button {
                    settings.entries.removeAll { $0.id == entry.id }
                } label: { Image(systemName: "xmark") }
                    .help("Remove shortcut")
                    .accessibilityLabel("Remove \(entry.action)")
                    .frame(width: 32, height: 32)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
        .buttonStyle(.borderless)
        .opacity(entry.enabled ? 1 : 0.57)
    }
}

private struct ShortcutItemEditor: View {
    let aerospaceActions: [(title: String, action: String)]
    let apps: [InstalledApplication]
    let validate: (ManagedShortcut) -> String?
    let save: (ManagedShortcut) -> Void
    let cancel: () -> Void

    @State private var draft: ManagedShortcut
    @State private var selectedAction: String
    @State private var bundleID: String
    @State private var error = ""

    init(item: ManagedShortcut, aerospaceActions: [(title: String, action: String)],
         apps: [InstalledApplication], validate: @escaping (ManagedShortcut) -> String?,
         save: @escaping (ManagedShortcut) -> Void, cancel: @escaping () -> Void) {
        self.aerospaceActions = aerospaceActions
        self.apps = apps
        self.validate = validate
        self.save = save
        self.cancel = cancel
        _draft = State(initialValue: item)
        _selectedAction = State(initialValue: item.action.hasPrefix("open:") ? "open-app" : item.action)
        _bundleID = State(initialValue: item.action.hasPrefix("open:") ? String(item.action.dropFirst(5)) : "")
    }

    private var candidate: ManagedShortcut {
        var value = draft
        if value.provider == .karabiner {
            value.action = selectedAction == "open-app" ? "open:" + bundleID.trimmingCharacters(in: .whitespaces) : selectedAction
        } else if value.provider == .aerospace {
            value.action = selectedAction
        }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit \(draft.provider.rawValue) shortcut").font(.title2.bold())
            if draft.provider == .aerospace {
                Picker("Action", selection: $selectedAction) {
                    ForEach(aerospaceActions, id: \.action) { action in
                        Text(action.title).tag(action.action)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if draft.provider == .karabiner {
                Picker("Action", selection: $selectedAction) {
                    ForEach(ShortcutSettings.scripts, id: \.name) { script in
                        Text("Open " + script.name).tag(script.name)
                    }
                    Text("Open application by bundle ID").tag("open-app")
                }
                if selectedAction == "open-app" {
                    TextField("Application bundle ID", text: $bundleID)
                        .textFieldStyle(.roundedBorder)
                    Text("Example: com.apple.Safari").font(.callout).foregroundStyle(.secondary)
                    if !apps.isEmpty {
                        Picker("Installed app", selection: $bundleID) {
                            Text("Choose an installed app").tag("")
                            ForEach(apps, id: \.bundleID) { app in
                                Text(app.name).tag(app.bundleID)
                            }
                        }
                    }
                }
            }
            if draft.provider == .raycast {
                Text("Open Raycast").fontWeight(.medium)
            }
            Divider()
            Picker("Key", selection: $draft.shortcut.key) {
                ForEach(WorkspaceShortcut.keyGroups.indices, id: \.self) { group in
                    Section(WorkspaceShortcut.keyGroups[group].name) {
                        ForEach(WorkspaceShortcut.keyGroups[group].keys.filter { key in
                            draft.provider != .raycast || ShortcutSettings.macKeyCodes[key] != nil
                        }, id: \.self) { key in
                            Text(WorkspaceShortcut.keyLabel(key)).tag(key)
                        }
                    }
                }
            }.frame(width: 320)
            Text("Modifiers").fontWeight(.medium)
            HStack(spacing: 18) {
                ForEach(WorkspaceShortcut.modifierNames, id: \.self) { modifier in
                    Toggle(["cmd": "Command", "ctrl": "Control", "alt": "Option", "shift": "Shift"][modifier]!,
                           isOn: Binding(
                            get: { draft.shortcut.modifiers.contains(modifier) },
                            set: { selected in
                                draft.shortcut.modifiers.removeAll { $0 == modifier }
                                if selected { draft.shortcut.modifiers.append(modifier) }
                            }))
                        .toggleStyle(.checkbox)
                }
            }
            HStack {
                Text(candidate.shortcut.display).font(.system(.headline, design: .monospaced))
                Spacer()
                if candidate.provider != .raycast {
                    Toggle("Enabled", isOn: $draft.enabled).toggleStyle(.checkbox)
                }
            }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            if !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save shortcut") {
                    let item = candidate
                    if let message = validate(item) { error = message }
                    else { save(item) }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650, height: 480)
    }
}
