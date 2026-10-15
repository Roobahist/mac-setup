import SwiftUI
import MacSetupCore

struct WorkspaceNameField: View {
    let name: String
    let rename: (String) -> Void
    @LocalViewState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Workspace name", text: $draft)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .workspaceControl()
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { value in if !value { commit() } }
            .accessibilityLabel("Name for \(name)")
        .onAppear { draft = name }
        .onChange(of: name) { value in if !focused { draft = value } }
    }

    private func commit() {
        guard draft != name else { return }
        rename(draft)
    }
}

struct WorkspaceModifierControls: View {
    @Binding var keymap: WorkspaceKeymap

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspace keyboard controls").font(SetupDesign.sectionTitle)
            Text("Each workspace keeps its destination key when you reorder or remove another workspace.")
                .font(SetupDesign.body).foregroundStyle(.secondary)
            modifierRow("Switch to workspace", modifiers: $keymap.switchModifiers)
            modifierRow("Move window to workspace", modifiers: $keymap.moveModifiers)
        }
        .setupCard()
    }

    private func modifierRow(_ title: String, modifiers: Binding<[String]>) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 192, alignment: .leading)
            ForEach(WorkspaceShortcut.modifierNames, id: \.self) { modifier in
                Toggle(["cmd": "⌘", "ctrl": "⌃", "alt": "⌥", "shift": "⇧"][modifier]!,
                       isOn: Binding(get: { modifiers.wrappedValue.contains(modifier) }, set: { selected in
                    modifiers.wrappedValue.removeAll { $0 == modifier }
                    if selected { modifiers.wrappedValue.append(modifier) }
                }))
                .toggleStyle(.checkbox).accessibilityLabel("\(title): \(modifier)")
            }
        }
    }
}
