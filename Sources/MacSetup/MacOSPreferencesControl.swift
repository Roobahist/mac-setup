import AppKit
import SwiftUI
import MacSetupCore

struct MacOSPreferencesControl: View {
    let engine: Engine
    @LocalViewState private var enabled = true
    @LocalViewState private var busy = false
    @LocalViewState private var status = ""
    @LocalViewState private var preview: [String] = []
    @LocalViewState private var reviewed: Data?
    @LocalViewState private var showingReview = false
    @LocalViewState private var lastTransaction: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shared macOS preferences").font(SetupDesign.sectionTitle)
                Spacer()
                Toggle("Use preference profile", isOn: $enabled).disabled(busy)
            }
            Text("Keep macOS preferences in one dotfiles file. Review and apply the group here; individual controls update the same file. Turning it off restores previous values while preserving later manual edits.")
                .font(SetupDesign.body).foregroundStyle(.secondary)
            Text(engine.macOSPreferences.profileURL.path)
                .font(SetupDesign.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if !status.isEmpty { Text(status).font(SetupDesign.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Open preference file") { openFile() }.disabled(busy)
                Button("Reload") { load() }.disabled(busy)
                if let transaction = lastTransaction {
                    Button("Undo group change") { undo(transaction) }.disabled(busy)
                }
                Spacer()
                Button("Review group changes") { review() }.buttonStyle(.borderedProminent).disabled(busy)
            }
        }
        .setupCard()
        .onAppear(perform: load)
        .sheet(isPresented: $showingReview) {
            VStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
                Text("Review macOS preferences").font(SetupDesign.sheetTitle)
                Text("Finish Finder file operations before applying. Some changes require logout or reopening apps.")
                    .font(SetupDesign.body).foregroundStyle(.secondary)
                ScrollView {
                    Text(preview.joined(separator: "\n\n")).font(SetupDesign.body)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                HStack {
                    Button("Cancel") { showingReview = false }.keyboardShortcut(.cancelAction).disabled(busy)
                    Spacer()
                    Button("Apply reviewed changes") { apply() }.buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction).disabled(busy || reviewed == nil)
                }
            }.padding(SetupDesign.pagePadding).frame(width: 660, height: 560)
        }
    }

    private func load() {
        do { enabled = try engine.macOSPreferences.profile().enabled; status = "" }
        catch { status = String(describing: error) }
    }

    private func openFile() {
        let url = engine.macOSPreferences.profileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = "Review and apply the group once to create your local preference file."
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func review() {
        busy = true
        let requested = enabled
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> (Data, [String]) in
                let service = engine.macOSPreferences
                return (try service.profile().encoded(), try service.preview(enabled: requested))
            }
            DispatchQueue.main.async {
                busy = false
                switch result {
                case let .success((data, lines)): reviewed = data; preview = lines; showingReview = true
                case .failure(let error): status = String(describing: error)
                }
            }
        }
    }

    private func apply() {
        busy = true
        let requested = enabled, expected = reviewed
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try engine.macOSPreferences.apply(enabled: requested, expected: expected) }
            DispatchQueue.main.async {
                busy = false; showingReview = false; reviewed = nil
                switch result {
                case .success(let outcome):
                    lastTransaction = outcome.transaction; load()
                    status = outcome.refreshWarning ?? "Preference group saved and verified. Undo is available."
                case .failure(let error): status = String(describing: error)
                }
            }
        }
    }

    private func undo(_ transaction: String) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> Void in
                let lock = try SetupLock(paths: engine.paths)
                defer { withExtendedLifetime(lock) {} }
                try engine.journal.restore(transaction)
            }
            DispatchQueue.main.async {
                busy = false
                switch result {
                case .success: lastTransaction = nil; load(); status = "Previous values and file restored. Reopen affected apps or log out to refresh."
                case .failure(let error): status = String(describing: error)
                }
            }
        }
    }
}
