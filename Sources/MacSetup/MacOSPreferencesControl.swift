import AppKit
import SwiftUI
import MacSetupCore

struct MacOSPreferencesControl: View {
    let engine: Engine
    @LocalViewState private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shared macOS preferences").font(SetupDesign.sectionTitle)
            Text("Edit your setup as cards. Apply saves one configuration file and changes only the settings you edited. Current values are read from this Mac, including changes made outside the app.")
                .font(SetupDesign.body).foregroundStyle(.secondary)
            Button("Edit macOS preferences") { showingEditor = true }.buttonStyle(.borderedProminent)
        }
        .setupCard()
        .sheet(isPresented: $showingEditor) { MacOSPreferencesEditor(engine: engine) }
    }
}

private struct MacOSPreferencesEditor: View {
    let engine: Engine
    @Environment(\.dismiss) private var dismiss
    @LocalViewState private var snapshot: MacOSPreferenceSnapshot?
    @LocalViewState private var observed: MacOSPreferenceSnapshot?
    @LocalViewState private var needsSync = false
    @LocalViewState private var rows: [MacOSPreferenceEdit] = []
    @LocalViewState private var initial: [MacOSPreferenceEdit] = []
    @LocalViewState private var enabled = true
    @LocalViewState private var busy = false
    @LocalViewState private var status = ""
    @LocalViewState private var category = "All"
    @LocalViewState private var query = ""
    @LocalViewState private var reviewLines: [String] = []
    @LocalViewState private var reviewedEdits: [MacOSPreferenceEdit] = []
    @LocalViewState private var showingReview = false
    @LocalViewState private var lastTransaction: String?

    private var edits: [MacOSPreferenceEdit] {
        rows.filter { row in
            guard let old = initial.first(where: { $0.id == row.id }) else { return true }
            return old.enabled != row.enabled || !equalPreference(old.value, row.value)
        }
    }
    private var changed: Bool { !edits.isEmpty || enabled != snapshot?.profile.enabled || needsSync }
    private var settings: [MacOSSetting] { snapshot?.profile.settings.filter { $0.category != "Menu Bar" } ?? [] }
    private var categories: [String] { ["All"] + Array(Set(settings.map(\.category))).sorted() }
    private var visible: [MacOSSetting] {
        settings.filter { (category == "All" || $0.category == category) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("macOS preferences").font(SetupDesign.sheetTitle).accessibilityAddTraits(.isHeader)
                Text("Current values come from this Mac. Select the cards you want to manage; unedited settings keep their current values.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Toggle("Use preference profile", isOn: $enabled).disabled(busy)
                Spacer()
                Button("Reload current values", action: load).disabled(busy)
            }
            HStack {
                TextField("Find a preference", text: $query).textFieldStyle(.roundedBorder)
                SetupDropdown(title: "Preference category", selection: $category,
                              choices: categories.map { .init(value: $0, title: $0) }).frame(width: 180)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
                    ForEach(visible, id: \.id) { setting in
                        if let index = rows.firstIndex(where: { $0.id == setting.id }) {
                            MacOSPreferenceCard(setting: setting, edit: $rows[index],
                                                currentDescription: describe(setting))
                                .disabled(busy || !enabled || setting.minimumOS > ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
                        }
                    }
                    if visible.isEmpty && !busy { Text("No matching preferences.").foregroundStyle(.secondary) }
                }.padding(2)
            }
            Text(enabled ? "Turning a card off restores its previous managed value and preserves later manual edits." : "Apply to restore the group’s previous values. Later manual edits are preserved.")
                .font(SetupDesign.caption).foregroundStyle(.secondary)
            if !status.isEmpty { Text(status).font(SetupDesign.body).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                if let transaction = lastTransaction {
                    Button("Undo last apply") { undo(transaction) }.disabled(busy)
                }
                Button("Use reference defaults", action: referenceDefaults).disabled(busy)
                Spacer()
                Text("\(edits.count) edited \(edits.count == 1 ? "card" : "cards")").font(SetupDesign.caption).foregroundStyle(.secondary)
                Button(edits.isEmpty && enabled == snapshot?.profile.enabled ? "Review current settings" : "Review & apply") { review() }.buttonStyle(.borderedProminent)
                    .disabled(busy || snapshot == nil || !changed)
            }
        }
        .padding(SetupDesign.pagePadding).font(SetupDesign.body).frame(width: 800, height: 780)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !busy { refresh(preservingDraft: true) }
        }
        .sheet(isPresented: $showingReview) {
            VStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
                Text("Review macOS preferences").font(SetupDesign.sheetTitle)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(reviewLines.enumerated()), id: \.offset) { _, line in
                            Text(line).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text("The app checks edited settings again before applying. Finish Finder file operations first; some changes need reopening apps or logging out.")
                    .font(SetupDesign.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Back") { showingReview = false }.keyboardShortcut(.cancelAction).disabled(busy)
                    Spacer()
                    Button("Apply changes", action: apply).buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction).disabled(busy)
                }
            }.padding(SetupDesign.pagePadding).font(SetupDesign.body).frame(width: 660, height: 540)
        }
    }

    private func describe(_ setting: MacOSSetting) -> String {
        guard let observed else { return "Loading…" }
        do {
            guard let value = try observed.value(for: setting.id) else { return "System default (no stored override)" }
            if let array = value as? [Any] { return "\(array.count) pinned items" }
            if value is [String: Any] { return "Saved Finder list options" }
            if let number = value as? NSNumber, String(cString: number.objCType) == "c" { return number.boolValue ? "On" : "Off" }
            return String(describing: value)
        } catch { return "Unable to read current value" }
    }

    private func load() { refresh(preservingDraft: false) }

    private func refresh(preservingDraft: Bool, statusAfterLoad: String = "") {
        guard !busy else { return }
        busy = true
        let pending = preservingDraft ? edits : [], oldInitial = initial
        let original = snapshot, requested = enabled
        let masterChanged = preservingDraft && original != nil && requested != original!.profile.enabled
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> (MacOSPreferenceSnapshot, [MacOSPreferenceEdit], Bool) in
                let service = engine.macOSPreferences, current = try service.snapshot()
                if let original, (!pending.isEmpty || masterChanged),
                   try original.profile.encoded() != current.profile.encoded() {
                    throw SetupError("The preference file changed outside the app. Reload current values before applying; your draft has been kept.")
                }
                let profile = try service.editingProfile(current)
                return (current, profile.settings.map { .init(id: $0.id, enabled: $0.enabled, value: $0.value) },
                        try profile.encoded() != current.profile.encoded())
            }
            DispatchQueue.main.async {
                busy = false
                switch result {
                case let .success((current, values, sync)):
                    observed = current; needsSync = sync
                    var keep = Set(pending.map(\.id))
                    if masterChanged && requested { keep.formUnion(current.profile.settings.filter(\.enabled).map(\.id)) }
                    snapshot = original.map { current.preservingBaseline(for: keep, from: $0) } ?? current
                    rows = values.map { value in pending.first { $0.id == value.id } ?? value }
                    initial = values.map { value in
                        pending.contains { $0.id == value.id } ? oldInitial.first { $0.id == value.id } ?? value : value
                    }
                    enabled = masterChanged ? requested : current.profile.enabled
                    status = statusAfterLoad
                case .failure(let error): status = String(describing: error)
                }
            }
        }
    }

    private func referenceDefaults() {
        do {
            let reference = try MacOSProfile(data: Data(contentsOf: engine.paths.profile.appendingPathComponent("macos/preferences.json")))
            for setting in reference.settings where setting.category != "Menu Bar" {
                if let index = rows.firstIndex(where: { $0.id == setting.id }) {
                    rows[index] = .init(id: setting.id, enabled: setting.enabled, value: setting.value)
                }
            }
            enabled = true
        } catch { status = String(describing: error) }
    }

    private func review() {
        guard let snapshot else { return }
        busy = true
        let selected = edits, requested = enabled
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try engine.macOSPreferences.previewEdits(selected, snapshot: snapshot, enabled: requested) }
            DispatchQueue.main.async {
                busy = false
                switch result {
                case .success(let lines): reviewedEdits = selected; reviewLines = lines; showingReview = true
                case .failure(let error): status = String(describing: error)
                }
            }
        }
    }

    private func apply() {
        guard let snapshot else { return }
        busy = true
        let selected = reviewedEdits, requested = enabled
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try engine.macOSPreferences.applyEdits(selected, snapshot: snapshot, enabled: requested) }
            DispatchQueue.main.async {
                busy = false; showingReview = false
                switch result {
                case .success(let outcome):
                    lastTransaction = outcome.transaction
                    refresh(preservingDraft: false, statusAfterLoad: outcome.refreshWarning ?? "Saved to one preference file. Only selected changes were applied. Undo is available.")
                case .failure(let error): status = String(describing: error)
                }
            }
        }
    }

    private func undo(_ transaction: String) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try engine.macOSPreferences.restore(transaction) }
            DispatchQueue.main.async {
                busy = false
                switch result {
                case .success(let warning):
                    lastTransaction = nil
                    refresh(preservingDraft: false, statusAfterLoad: warning ?? "Previous values restored.")
                case .failure(let error): status = String(describing: error)
                }
            }
        }
    }
}
