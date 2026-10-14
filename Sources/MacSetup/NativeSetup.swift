import AppKit
import SwiftUI
import MacSetupCore

enum SetupPage: Hashable { case features, shortcuts, workspaces, review, running, guide, failed, finished }
enum SetupScope { case full, workspaces, shortcuts, feature }

final class SetupModel: ObservableObject {
    @Published var page: SetupPage = .features
    @Published var picker = TaskPickerState(preset: .repair)
    @Published var states: [String: String] = [:]
    @Published var layout = WorkspaceConfiguration.defaultLayout
    @Published var shortcuts = ShortcutSettings(entries: [])
    @Published private(set) var appliedLayout = WorkspaceConfiguration.defaultLayout
    @Published private(set) var appliedShortcuts = ShortcutSettings(entries: [])
    var workspaceHasDraftChanges: Bool { layout.workspaces != appliedLayout.workspaces }
    var shortcutsHaveDraftChanges: Bool { shortcuts != appliedShortcuts || layout.keymap != appliedLayout.keymap }
    @Published var pausedSetup = false
    let aerospaceTemplate: String
    let karabinerTemplate: Data
    @Published var apps: [InstalledApplication] = []
    @Published var index = 0
    @Published var tasks: [SetupTask] = []
    @Published var results: [String: String] = [:]
    @Published var message = ""
    @Published var details = ""
    @Published var installerOutput = ""
    @Published var acceptsInput = false
    @Published var response = ""
    @Published var checkedSteps = Set<Int>()
    @Published var checkReady = false
    @Published var busy = false
    @Published var search = ""
    @Published var selectedWorkspace = 0
    @Published var appSheet = false
    @Published var appSearch = ""
    @Published var runLog = ""
    var scope: SetupScope = .full
    private let worker = DispatchQueue(label: "mac-setup.native", qos: .userInitiated)
    private var setupLock: SetupLock?
    private var guideProgress = GuideProgress()
    let runner = EmbeddedInstaller()
    let engine: Engine

    init(ids: [String]?, preset: SetupPreset?) throws {
        engine = try Engine(runner: runner)
        engine.deferRestarts = true
        aerospaceTemplate = try String(contentsOf: engine.paths.profile.appendingPathComponent("aerospace/aerospace.toml"), encoding: .utf8)
        karabinerTemplate = try Data(contentsOf: engine.paths.profile.appendingPathComponent("karabiner/karabiner.json"))
        shortcuts = try ShortcutSettings.load(from: engine.paths, aerospaceTemplate: aerospaceTemplate)
        shortcuts.migrateBundledDefaults(
            installedAlacritty: ApplicationDiscovery.scan(home: engine.paths.home)
                .contains { $0.name == "Alacritty" })
        layout = try WorkspaceConfiguration.load(from: engine.paths)
        appliedLayout = layout
        appliedShortcuts = shortcuts
        guideProgress = try GuideProgress.load(from: engine.paths)
        apps = ApplicationDiscovery.scan(home: engine.paths.home)
        if let preset { picker.choose(preset) }
        if let ids {
            for id in picker.orderedSelection where picker.selected.contains(id) { picker.toggle(id) }
            for id in ids where !picker.selected.contains(id) { picker.toggle(id) }
        }
        runner.output = { [weak self] value in
            DispatchQueue.main.async {
                guard let self else { return }
                let clean = value.replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
                self.installerOutput = String((self.installerOutput + clean).suffix(18000))
                self.runLog += clean
            }
        }
        runner.inputChanged = { [weak self] value in DispatchQueue.main.async { self?.acceptsInput = value } }
        refreshInventory()
    }

    var current: SetupTask? { tasks.indices.contains(index) ? tasks[index] : nil }
    var steps: [String] {
        guard let task = current else { return [] }
        switch task.action {
        case let .guide(_, _, instructions): return instructions
        case let .appStore(app, _): return ["Install \(app) in the App Store. Return here after installation finishes."]
        default: return []
        }
    }
    var completed: Int { results.values.filter { $0 == "Complete" || $0 == "Already configured" }.count }

    func refreshInventory() {
        busy = true
        worker.async { [self] in
            var values: [String: String] = [:]
            for task in Catalog.tasks { values[task.id] = (try? engine.state(task).rawValue) ?? "Could not inspect" }
            DispatchQueue.main.async {
                self.states = values
                self.picker.available = Set(values.filter { $0.value == TaskState.done.rawValue || $0.value == TaskState.confirmed.rawValue }.keys)
                self.busy = false
            }
        }
    }

    func openEditor(_ selected: SetupScope) {
        pausedSetup = false
        scope = selected
        message = ""
        page = selected == .workspaces ? .workspaces : .shortcuts
    }

    func review() {
        do {
            if let error = configurationError(for: scope) { throw SetupError(error) }
            let chosen: [String]
            switch scope {
            case .full: chosen = picker.orderedSelection
            case .workspaces: chosen = ["aerospace-profile", "sketchybar-profile", "sketchybar-start"]
            case .shortcuts: chosen = ["aerospace-profile", "karabiner-profile", "raycast-profile"]
            case .feature: chosen = tasks.map(\.id)
            }
            tasks = try Catalog.ordered(chosen, includingDependencies: false)
            message = ""
            page = .review
        } catch { message = String(describing: error) }
    }

    func log(_ entry: String) {
        runLog += "[\(ISO8601DateFormatter().string(from: Date()))] \(entry)\n"
    }

    func workspaceError(in layout: WorkspaceConfiguration, shortcutWorkspaceID: String? = nil) -> String? {
        do {
            try shortcuts.validate(workspaces: layout, aerospaceTemplate: aerospaceTemplate)
            return nil
        } catch { return String(describing: error) }
    }

    /// Validate only the section being applied, using other sections' saved
    /// configuration instead of potentially unrelated unsaved drafts.
    func configurationError(for selected: SetupScope) -> String? {
        do {
            switch selected {
            case .full:
                try shortcuts.validate(workspaces: layout, aerospaceTemplate: aerospaceTemplate)
            case .workspaces:
                var pending = layout
                pending.keymap = appliedLayout.keymap
                try appliedShortcuts.validate(workspaces: pending, aerospaceTemplate: aerospaceTemplate)
            case .shortcuts:
                var pending = appliedLayout
                pending.keymap = layout.keymap
                try shortcuts.validate(workspaces: pending, aerospaceTemplate: aerospaceTemplate)
            case .feature: break
            }
            return nil
        } catch { return String(describing: error) }
    }

    func start() {
        do {
            setupLock = try SetupLock(paths: engine.paths)
            // Applying one section must never save an unrelated unsaved draft.
            switch scope {
            case .full:
                if let error = workspaceError(in: layout) { throw SetupError(error) }
                try shortcuts.save(to: engine.paths)
                try layout.save(to: engine.paths)
            case .workspaces:
                var chosen = layout
                chosen.keymap = appliedLayout.keymap
                try appliedShortcuts.validate(workspaces: chosen, aerospaceTemplate: aerospaceTemplate)
                try chosen.save(to: engine.paths)
            case .shortcuts:
                var chosen = appliedLayout
                chosen.keymap = layout.keymap
                try shortcuts.validate(workspaces: chosen, aerospaceTemplate: aerospaceTemplate)
                try chosen.save(to: engine.paths)
                try shortcuts.save(to: engine.paths)
            case .feature: break
            }
            engine.selectedWorkspaceTaskIDs = scope == .full ? picker.selected : nil
            pausedSetup = false
            index = 0; results = [:]; runLog = ""
            log("Starting \(scope) with \(tasks.count) selected tasks")
            log("Workspace order: \(layout.workspaces.map(\.id).joined(separator: ", "))")
            log("Switch modifiers: \(layout.keymap.switchModifiers.joined(separator: "+")); move modifiers: \(layout.keymap.moveModifiers.joined(separator: "+"))")
            advance()
        } catch { message = String(describing: error) }
    }

    func advance() {
        message = ""; details = ""; installerOutput = ""; response = ""
        // Completed tasks are never repeated when resuming a paused setup.
        while let task = current, ["Complete", "Already configured", "Pending"].contains(results[task.id] ?? "") {
            index += 1
        }
        checkedSteps = []; checkReady = false
        guard let task = current else {
            log("Tasks complete. Refreshing desktop services")
            busy = true; page = .running
            worker.async { [self] in
                do {
                    try engine.finishRestarts()
                    let updatedLayout = try? WorkspaceConfiguration.load(from: engine.paths)
                    let updatedShortcuts = try? ShortcutSettings.load(
                        from: engine.paths, aerospaceTemplate: aerospaceTemplate)
                    DispatchQueue.main.async {
                        self.log("Finished successfully. Saved and refreshed selected configuration.")
                        if let updatedLayout { self.appliedLayout = updatedLayout }
                        if let updatedShortcuts { self.appliedShortcuts = updatedShortcuts }
                        self.busy = false
                        self.page = .finished
                        self.setupLock = nil
                        self.refreshInventory()
                    }
                } catch {
                    DispatchQueue.main.async { self.log("Restart failed: \(error)"); self.busy = false; self.message = String(describing: error); self.page = .failed }
                }
            }
            return
        }
        log("Task \(index + 1)/\(tasks.count): \(task.id) (\(task.title))")
        busy = true; page = .running
        worker.async { [self] in
            do {
                for dependency in task.dependencies {
                    if results[dependency] == "Pending" {
                        throw SetupError("Complete the pending task \(dependency) first, then retry this task.")
                    }
                    if !tasks.contains(where: { $0.id == dependency }) {
                        let dependencyState = try engine.state(Catalog.task(dependency))
                        if dependencyState != .done && dependencyState != .confirmed {
                            throw SetupError("Required task \(dependency) was left unchecked and is not ready. Select it in Choose features.")
                        }
                    }
                }
                if case .appStore = task.action, try engine.state(task) == .done {
                    DispatchQueue.main.async {
                        self.log("\(task.id): already installed")
                        self.results[task.id] = "Already configured"
                        self.busy = false; self.index += 1; self.advance()
                    }
                    return
                }
                // Permission guides are always revisited: previous answers are not a hardware test.
                if task.guided {
                    try engine.openGuide(task)
                    let check = try engine.checkGuide(task)
                    DispatchQueue.main.async {
                        self.log("\(task.id): waiting for user verification")
                        self.busy = false; self.page = .guide
                        self.restoreGuideProgress()
                        self.updateGuideCheck(check)
                    }
                    return
                }
                // A selected service task refreshes an existing bar after configuration changes.
                let state = try engine.state(task)
                let already = state == .done && task.id != "sketchybar-start"
                if !already { _ = try engine.apply(task) }
                DispatchQueue.main.async {
                    self.log("\(task.id): \(already ? "already configured" : "applied")")
                    self.results[task.id] = already ? "Already configured" : "Complete"
                    self.busy = false; self.index += 1; self.advance()
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("\(task.id): FAILED: \(error)")
                    self.busy = false; self.message = Self.recoveryHint(task)
                    self.details = String(describing: error); self.page = .failed
                }
            }
        }
    }

    static func recoveryHint(_ task: SetupTask) -> String {
        switch task.id {
        case "karabiner": return "Karabiner did not finish installing. If the installer asked for an administrator password, enter it in the secure installer field. Retry resumes this task."
        case "vorssaint-profile", "raycast-profile": return "Close the app from its Quit menu, then retry. Its saved preferences must be updated while it is closed."
        case "alacritty": return "Homebrew disabled the Alacritty cask on this system. Uncheck Alacritty in Terminal, choose another terminal, then resume at this task. Your previous completed steps will be preserved."
        default: return "This task needs attention. Review the error below, fix its stated cause, then retry. Completed tasks stay completed. You can also leave this task pending."
        }
    }

    func checkAgain() {
        guard let task = current else { return }
        busy = true
        worker.async { [self] in
            do {
                let check = try engine.checkGuide(task)
                DispatchQueue.main.async { self.updateGuideCheck(check); self.busy = false }
            } catch {
                DispatchQueue.main.async { self.message = String(describing: error); self.checkReady = false; self.busy = false }
            }
        }
    }

    private func restoreGuideProgress() {
        guard let task = current else { return }
        let saved = guideProgress.completedSteps[task.id] ?? []
        checkedSteps = Set(steps.enumerated().filter { saved.contains($0.element) }.map(\.offset))
    }

    func setGuideStep(_ index: Int, _ enabled: Bool) {
        if enabled { checkedSteps.insert(index) } else { checkedSteps.remove(index) }
        saveGuideProgress()
    }

    private func saveGuideProgress() {
        guard let task = current else { return }
        guideProgress.completedSteps[task.id] = Set(checkedSteps.compactMap { steps.indices.contains($0) ? steps[$0] : nil })
        do { try guideProgress.save(to: engine.paths) }
        catch { message = "Could not save this checklist: \(error)" }
    }

    private func updateGuideCheck(_ check: GuideCheck) {
        message = check.message; checkReady = check.ready
        guard let task = current else { return }
        guideProgress.observedRequirements[task.id] = check.requirements
        guideProgress.lastChecked[task.id] = Date()
        if task.id == "karabiner-access" {
            let required = [["services"], ["driver"], ["accessibility"], ["input"], ["keyboard", "profile"]]
            for (index, identifiers) in required.enumerated() {
                let ready = identifiers.allSatisfy { id in check.requirements.contains { $0.id == id && $0.ready } }
                if ready { checkedSteps.insert(index) } else { checkedSteps.remove(index) }
            }
        }
        saveGuideProgress()
    }

    func completeGuide() {
        guard let task = current else { return }
        busy = true
        worker.async { [self] in
            do {
                if task.id != "tomito" { try engine.confirm(task) }
                else if try engine.state(task) != .done { throw SetupError("Tomito has not finished installing.") }
                DispatchQueue.main.async {
                    self.log("\(task.id): verified")
                    self.results[task.id] = "Complete"; self.busy = false; self.index += 1; self.advance()
                }
            } catch { DispatchQueue.main.async { self.message = String(describing: error); self.checkReady = false; self.busy = false } }
        }
    }

    func skip() {
        if let task = current { log("\(task.id): left pending"); results[task.id] = "Pending"; index += 1 }
        advance()
    }

    func openPermissionPane(_ pane: String) {
        do { try engine.runner.checked("/usr/bin/open", [pane]) }
        catch { message = String(describing: error) }
    }

    func openSettings() {
        guard let task = current else { return }
        do { try engine.openGuideSettings(task) } catch { message = String(describing: error) }
    }

    func openGuideStep(_ index: Int) {
        guard let task = current else { return }
        do { try engine.openGuideStep(task, index: index) }
        catch { message = String(describing: error) }
    }

    func guideStepVerified(_ index: Int) -> Bool {
        if current?.id == "karabiner-access", index < 5 {
            let required = [["services"], ["driver"], ["accessibility"], ["input"], ["keyboard", "profile"]]
            guard required.indices.contains(index), let task = current else { return false }
            let observed = guideProgress.observedRequirements[task.id] ?? []
            return required[index].allSatisfy { id in
                observed.contains { $0.id == id && $0.ready }
            }
        }
        return checkedSteps.contains(index)
    }

    func pauseForEdits() {
        guard !busy, page == .failed || page == .guide else { return }
        pausedSetup = true
        scope = .full
        page = .features
        log("Paused at task \(index + 1)/\(tasks.count); completed tasks remain recorded")
        // Do not re-scan task states or release the active setup lock.
    }

    func resumeAfterEdits() {
        guard pausedSetup, !busy else { return }
        do {
            if let error = workspaceError(in: layout) { throw SetupError(error) }
            let changed = try Catalog.ordered(picker.orderedSelection, includingDependencies: false)
            let selectedIDs = Set(changed.map(\.id))
            let previousID = current?.id
            tasks = changed
            results = results.filter { selectedIDs.contains($0.key) }
            if let previousID, !selectedIDs.contains(previousID) {
                log("Removed interrupted task \(previousID) from this run")
            }
            try shortcuts.save(to: engine.paths)
            try layout.save(to: engine.paths)
            engine.selectedWorkspaceTaskIDs = picker.selected
            index = 0
            pausedSetup = false
            log("Resuming \(tasks.count) selected tasks without repeating completed work")
            advance()
        } catch {
            message = String(describing: error)
        }
    }

    func returnToFeatures() {
        setupLock = nil
        pausedSetup = false
        scope = .full
        message = ""
        page = .features
        refreshInventory()
    }

    func sendInput() { runner.send(response); response = "" }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    let embedded: Bool
    let onReturn: (() -> Void)?

    init(model: SetupModel, embedded: Bool = false, onReturn: (() -> Void)? = nil) {
        self.model = model
        self.embedded = embedded
        self.onReturn = onReturn
    }
    @LocalViewState private var glyphWorkspaceID: String?
    @LocalViewState private var workspaceDragSession = UUID().uuidString
    @LocalViewState private var dropTargetWorkspaceID: String?
    @LocalViewState private var expandedTaskCategories = Set<String>()

    private var previewTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm"
        return formatter.string(from: Date())
    }

    private var visibleWorkspaceIndices: [Int] { Array(model.layout.workspaces.indices) }
    private var visibleWorkspaceIDs: [String] { model.layout.workspaces.map(\.id) }
    private var installedIDs: Set<String> { Set(model.apps.map(\.bundleID)) }

    private var step: Int {
        switch model.page {
        case .features: return 1
        case .shortcuts: return 2
        case .workspaces: return 3
        case .review: return 4
        default: return 5
        }
    }

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.runLog, forType: .string)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
            HStack {
                Image(systemName: "desktopcomputer").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up your Mac").font(.system(size: 26, weight: .semibold))
                    Text("Apps, workspaces, and the checks that make them work.").foregroundStyle(.secondary)
                }
                Spacer()
                Text("Mac Setup").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }.padding(24)
            HStack(spacing: 24) {
                ForEach(Array(["Choose features", "Shortcuts", "Workspaces", "Review", "Set up & test"].enumerated()), id: \.offset) { index, name in
                    Label(name, systemImage: model.scope == .full && index + 1 < step
                          ? "checkmark.circle.fill" : "\(index + 1).circle")
                        .foregroundStyle(index + 1 == step ? Color.accentColor : Color.secondary)
                }
            }.padding(.horizontal, 24).padding(.bottom, 20)
            Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch model.page {
                    case .features: features
                    case .shortcuts: shortcuts
                    case .workspaces: workspaces
                    case .review: review
                    case .running: running
                    case .guide: guide
                    case .failed: failed
                    case .finished: finished
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(model.page)
            Divider()
            Group {
                if embedded { embeddedFooter }
                else { footer }
            }.padding(20)
        }
        .font(.system(size: 15))
        .frame(minWidth: embedded ? 610 : 820, minHeight: embedded ? 610 : 660)
        .sheet(isPresented: $model.appSheet) { appAssignments }
        .sheet(isPresented: Binding(get: { glyphWorkspaceID != nil }, set: { if !$0 { glyphWorkspaceID = nil } })) {
            if let i = model.layout.workspaces.firstIndex(where: { $0.id == glyphWorkspaceID }) {
                GlyphPicker(workspace: model.layout.workspaces[i]) { model.layout.workspaces[i].icon = $0 }
            }
        }

    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose what to configure").font(.title2.bold())
            Text("Choose the features to install, or update an existing workspace layout or keymap without repeating setup.")
            if model.pausedSetup {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Setup paused at task \(min(model.index + 1, model.tasks.count)) of \(model.tasks.count)",
                          systemImage: "pause.circle.fill").font(.headline)
                    Text("Change the selected tasks below, then resume where you stopped. Completed tasks will not run again.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Resume setup") { model.resumeAfterEdits() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            HStack(spacing: 12) {
                Button { model.openEditor(.workspaces) } label: { Label("Edit workspaces only", systemImage: "square.grid.2x2") }
                Button { model.openEditor(.shortcuts) } label: { Label("Edit shortcuts only", systemImage: "keyboard") }
            }
            HStack {
                ForEach(SetupPreset.allCases, id: \.self) { preset in
                    Button(preset.title) { model.picker.choose(preset) }.disabled(model.busy)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small); Text("Checking this Mac…") }
            }
            TextField("Find a feature", text: $model.search).textFieldStyle(.roundedBorder)
            ForEach(model.picker.categories.dropFirst(), id: \.self) { category in
                let selectedCount = Catalog.tasks.filter {
                    $0.category == category && model.picker.selected.contains($0.id)
                }.count
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            if expandedTaskCategories.contains(category) {
                                expandedTaskCategories.remove(category)
                            } else {
                                expandedTaskCategories.insert(category)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .rotationEffect(.degrees(expandedTaskCategories.contains(category) ? 90 : 0))
                                .frame(width: 16)
                            Text(category).font(.system(size: 15, weight: .medium))
                            Spacer(minLength: 12)
                            Text("\(selectedCount) selected")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .padding(.horizontal, 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category), \(selectedCount) selected")
                    .accessibilityHint(expandedTaskCategories.contains(category) ? "Collapse group" : "Expand group")

                    if expandedTaskCategories.contains(category) {
                        Divider().padding(.horizontal, 18)
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Catalog.tasks.filter { $0.category == category &&
                                (model.search.isEmpty ||
                                 ($0.title + " " + $0.summary)
                                    .localizedCaseInsensitiveContains(model.search)) }, id: \.id) { task in
                                HStack(alignment: .top, spacing: 18) {
                                    Toggle(isOn: Binding(
                                        get: { model.picker.selected.contains(task.id) },
                                        set: { _ in model.picker.toggle(task.id) })) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(task.title).fontWeight(.medium)
                                            Text(task.summary).font(.callout).foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }.toggleStyle(.checkbox).disabled(model.busy)
                                    Spacer(minLength: 8)
                                    Text(task.guided ? "User approval" : "Automatic")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 102, alignment: .trailing)
                                }
                            }
                        }.padding(18)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            Text(model.picker.preset?.summary ?? "Custom selection. Open a section to change its tasks.").foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShortcutStudio(settings: $model.shortcuts, layout: $model.layout,
                           apps: model.apps, aerospaceTemplate: model.aerospaceTemplate,
                           karabinerTemplate: model.karabinerTemplate)
            if let error = model.workspaceError(in: model.layout) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
            }
        }
    }

    private var workspaceKeys: [String] {
        WorkspaceConfiguration.keys + Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
    }

    /// This is an editable SketchyBar mock, not a material app card.
    /// The menu bar itself is drawn as the thin black strip users actually see.
    private var menuBarPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("SKETCHYBAR PREVIEW")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Changes appear here first, then on your Mac after Apply")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 2) {
                ForEach(model.layout.workspaces, id: \.id) { workspace in
                    Text(workspace.resolvedIcon.symbol)
                        .font(.custom(workspace.resolvedIcon.font.postScriptName, size: 15))
                        .frame(width: 28, height: 30)
                        .help(workspace.name)
                }
                Spacer(minLength: 14)
                Text(previewTime)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 33)
            .background(Color.black, in: Capsule())
            .padding(.vertical, 7)
        }
    }

    private func workspaceColumn(_ label: String, width: CGFloat,
                                 alignment: Alignment = .center) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private var workspaceColumns: some View {
        HStack(spacing: 12) {
            workspaceColumn("ORDER", width: 64)
            workspaceColumn("GLYPH", width: 60)
            workspaceColumn("WORKSPACE", width: 190, alignment: .leading)
            workspaceColumn("APPS", width: 116)
            workspaceColumn("KEY", width: 110)
            workspaceColumn("REMOVE", width: 44)
        }
        .padding(.horizontal, 12)
    }

    private var workspaces: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workspaces").font(.title2.bold())
            Text("Drag a row or use the arrows to reorder. The menu preview updates immediately; your actual menu bar does not change until you apply the layout.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            menuBarPreview

            HStack(spacing: 12) {
                Label(model.workspaceHasDraftChanges ? "Unapplied workspace changes" : "Workspace layout is saved",
                      systemImage: model.workspaceHasDraftChanges ? "square.and.pencil" : "checkmark.circle")
                    .foregroundStyle(model.workspaceHasDraftChanges ? Color.orange : Color.secondary)
                Spacer()
                Button("Review & apply workspaces") { model.review() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || !model.workspaceHasDraftChanges)
            }
            .font(.callout)
            .padding(.top, 5)
            Divider()
            workspaceColumns
            VStack(spacing: 7) {
                ForEach(visibleWorkspaceIDs, id: \.self) { id in
                    if let index = model.layout.workspaces.firstIndex(where: { $0.id == id }) {
                        workspaceCard(at: index)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.16), value: visibleWorkspaceIDs)
            Button {
                var number = 1
                while model.layout.workspaces.contains(where: { $0.id == "custom\(number)" }) {
                    number += 1
                }
                model.layout.workspaces.append(.init(id: "custom\(number)",
                    name: "Workspace \(number)", glyph: "star", shortcutKey: ""))
            } label: {
                Label("Add workspace", systemImage: "plus")
            }
            .padding(.top, 4)
            if let error = model.workspaceError(in: model.layout) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.message.isEmpty {
                Text(model.message).font(.callout).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: 800, alignment: .leading)
    }

    private func moveWorkspace(_ index: Int, upward: Bool) {
        guard model.layout.workspaces.indices.contains(index) else { return }
        let id = model.layout.workspaces[index].id
        let target = upward ? index - 1 : index + 2
        guard upward ? index > 0 : index < model.layout.workspaces.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            model.layout.insertWorkspace(id, at: target)
        }
    }

    private func workspaceCard(at i: Int) -> some View {
        let item = model.layout.workspaces[i]
        let glyph = item.resolvedIcon
        let assignedCount = model.layout.workspaces[i].apps.count
        return HStack(spacing: 12) {
            HStack(spacing: 2) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .frame(width: 22)
                    .help("Drag anywhere on this row to reorder")
                VStack(spacing: 1) {
                    Button { moveWorkspace(i, upward: true) } label: {
                        Image(systemName: "chevron.up").frame(width: 28, height: 17)
                    }
                    .disabled(i == 0)
                    .help("Move \(item.name) up")
                    Button { moveWorkspace(i, upward: false) } label: {
                        Image(systemName: "chevron.down").frame(width: 28, height: 17)
                    }
                    .disabled(i == model.layout.workspaces.count - 1)
                    .help("Move \(item.name) down")
                }
            }
            .frame(width: 64)
            Button { glyphWorkspaceID = item.id } label: {
                Group {
                    if glyph.symbol == "?" {
                        Image(systemName: "plus.square.dashed")
                    } else {
                        Text(glyph.symbol)
                            .font(.custom(glyph.font.postScriptName, size: 19))
                    }
                }
                .frame(width: 48, height: 36)
                .background(Color.accentColor.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(width: 60)
            .help("Choose glyph for \(item.name)")

            TextField("Workspace name", text: $model.layout.workspaces[i].name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
                .accessibilityLabel("Workspace name")

            Button {
                model.selectedWorkspace = i
                model.appSheet = true
            } label: {
                Label("\(assignedCount) apps", systemImage: "square.stack.3d.up")
                    .frame(width: 116, height: 32)
            }
            .help("Assign applications to \(item.name)")

            workspaceShortcutKey(at: i)
            Button { model.layout.workspaces.remove(at: i) } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 32)
            }
            .disabled(model.layout.workspaces.count == 1)
            .help("Remove \(item.name)")
        }
        .buttonStyle(.plain)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1))
        .overlay(alignment: .top) {
            if dropTargetWorkspaceID == item.id {
                Capsule().fill(Color.accentColor).frame(height: 3).offset(y: -4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .draggable("mac-setup-workspace:\(workspaceDragSession):\(item.id)") {
            Label(item.name, systemImage: "line.3.horizontal")
                .font(.headline)
                .padding(14)
                .frame(width: 280, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .dropDestination(for: String.self) { dragged, location in
            let prefix = "mac-setup-workspace:\(workspaceDragSession):"
            guard dragged.count == 1, let raw = dragged.first, raw.hasPrefix(prefix) else { return false }
            let source = String(raw.dropFirst(prefix.count))
            guard visibleWorkspaceIDs.contains(source) else { return false }
            withAnimation(.easeInOut(duration: 0.16)) {
                model.layout.insertWorkspace(source, at: location.y > 26 ? i + 1 : i)
            }
            dropTargetWorkspaceID = nil
            return true
        } isTargeted: { hovering in
            if hovering { dropTargetWorkspaceID = item.id }
            else if dropTargetWorkspaceID == item.id { dropTargetWorkspaceID = nil }
        }
    }

    private func workspaceShortcutKey(at i: Int) -> some View {
        let item = model.layout.workspaces[i]
        let binding = Binding<String>(
            get: {
                item.shortcutKey ?? item.shortcuts?.switchTo?.key
                    ?? (WorkspaceConfiguration.keys.indices.contains(i)
                        ? WorkspaceConfiguration.keys[i] : "")
            },
            set: { key in
                model.layout.workspaces[i].shortcutKey = key
                model.layout.workspaces[i].shortcuts = nil
            })
        return Picker("Shortcut destination key", selection: binding) {
            Text("None").tag("")
            ForEach(workspaceKeys, id: \.self) { key in
                Text(WorkspaceShortcut.keyLabel(key)).tag(key)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 110)
        .help("Key for \(item.name)")
    }

    private var appAssignments: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Apps for \(model.layout.workspaces[model.selectedWorkspace].name)").font(.title2.bold())
            Text("New windows from these apps will open in this workspace. Selecting an app moves its assignment here.")
            TextField("Find an installed app", text: $model.appSearch).textFieldStyle(.roundedBorder)
            List(model.apps.filter { model.appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(model.appSearch) }, id: \.bundleID) { app in
                Toggle(app.name, isOn: Binding(get: { model.layout.workspaces[model.selectedWorkspace].apps.contains(app.bundleID) }, set: { enabled in
                    for i in model.layout.workspaces.indices { model.layout.workspaces[i].apps.removeAll { $0 == app.bundleID } }
                    if enabled { model.layout.workspaces[model.selectedWorkspace].apps.append(app.bundleID) }
                })).toggleStyle(.checkbox)
            }
            HStack { Spacer(); Button("Done") { model.appSheet = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 540, height: 520)
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to apply \(model.tasks.count) tasks").font(.title2.bold())
            Text("Only the listed tasks will run. Changed files are backed up, permission checks require confirmation, and the apply log can be copied.")
            ForEach(model.tasks, id: \.id) { task in
                HStack(alignment: .top) {
                    Image(systemName: task.guided ? "hand.tap" : "gearshape")
                    VStack(alignment: .leading, spacing: 4) { Text(task.title).fontWeight(.medium); Text(task.summary).foregroundStyle(.secondary) }
                }
            }
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.red) }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.current?.title ?? "Refreshing your desktop").font(.title2.bold())
            ProgressView(value: Double(model.index), total: Double(max(1, model.tasks.count)))
            Text("Task \(min(model.index + 1, model.tasks.count)) of \(model.tasks.count) · \(model.completed) complete").foregroundStyle(.secondary)
            Text(model.current?.summary ?? "Applying the saved Finder, Dock and menu bar preferences.")
            HStack {
                Text("Apply log").font(.headline)
                Spacer()
                Button { copyLog() } label: { Label("Copy log", systemImage: "doc.on.doc") }
                    .disabled(model.runLog.isEmpty)
            }
            ScrollView {
                Text(model.runLog).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 160, maxHeight: 260)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            if model.acceptsInput {
                HStack {
                    SecureField("Installer password or response", text: $model.response)
                        .onSubmit { model.sendInput() }
                    Button("Send") { model.sendInput() }
                }
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.current?.title ?? "Test your setup").font(.title2.bold())
            Text("Task \(model.index + 1) of \(model.tasks.count). Follow each step below. Open the related setting and check that step before continuing.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(model.steps.enumerated()), id: \.offset) { i, instruction in
                let automatic = model.current?.id == "karabiner-access" && i < 5
                let verified = model.guideStepVerified(i)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(i + 1))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 7))
                        Text(instruction)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 12) {
                        if let task = model.current,
                           let route = GuideStepRouting.destination(task: task, index: i) {
                            Button(route.title) { model.openGuideStep(i) }
                                .controlSize(.regular)
                        }
                        if automatic {
                            Button("Check this step") { model.checkAgain() }
                                .disabled(model.busy)
                            Label(verified ? "Verified" : "Needs attention",
                                  systemImage: verified ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.caption)
                                .foregroundStyle(verified ? Color.secondary : Color.orange)
                        } else {
                            Toggle("Completed", isOn: Binding(
                                get: { model.checkedSteps.contains(i) },
                                set: { model.setGuideStep(i, $0) }
                            )).toggleStyle(.checkbox)
                        }
                        Spacer(minLength: 0)
                        if automatic && model.busy {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.leading, 36)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.48)))
            }
            if !model.message.isEmpty {
                Label(model.message,
                      systemImage: model.checkReady ? "checkmark.circle" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(model.checkReady ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(model.current?.title ?? "Refresh needs attention", systemImage: "exclamationmark.triangle").font(.title2.bold())
            Text(model.message)
            Text(model.details).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
            Button { copyLog() } label: { Label("Copy full apply log", systemImage: "doc.on.doc") }
            ScrollView {
                Text(model.runLog).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 260)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.results.values.contains("Pending") ? "Setup saved; some tasks still need attention" : "Setup complete").font(.title2.bold())
            Button { copyLog() } label: { Label("Copy apply log", systemImage: "doc.on.doc") }
            Text("Move the pointer to the bottom edge: the Dock should reveal promptly. The macOS menu bar should hide when the pointer leaves the top. Its reveal timing is controlled by macOS. If it still stays visible, set Automatically hide and show the menu bar to Always in System Settings, then log out and back in.")
            Text("Check the workspace highlight with your chosen modifiers and destination key, then use the move-window shortcut to send a window to another workspace.")
            ForEach(model.tasks, id: \.id) { task in
                HStack { Text(task.title); Spacer(); Text(model.results[task.id] ?? "Pending").foregroundStyle(model.results[task.id] == "Pending" ? Color.orange : Color.secondary) }
            }
            Button("Retry pending tasks") {
                model.tasks = model.tasks.filter { model.results[$0.id] == "Pending" }
                model.start()
            }.disabled(!model.results.values.contains("Pending"))
        }
    }

    @ViewBuilder private var embeddedFooter: some View {
        HStack {
            switch model.page {
            case .workspaces, .shortcuts:
                Text(model.page == .workspaces
                     ? (model.workspaceHasDraftChanges ? "Draft changes are not yet active." : "Workspace order is saved.")
                     : (model.shortcutsHaveDraftChanges ? "Shortcut changes are not yet active." : "Shortcuts are saved."))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.page == .workspaces ? "Review & apply workspaces" : "Review & apply shortcuts") {
                    model.review()
                }
                .disabled(model.busy || model.configurationError(for: model.scope) != nil)
                .keyboardShortcut(.defaultAction)
            case .review:
                Button("Back to features") { onReturn?() }
                Spacer()
                Button(model.scope == .full ? "Apply selected setup" :
                       (model.scope == .feature ? "Apply selected feature" : "Apply changes now")) { model.start() }
                    .disabled(model.busy).keyboardShortcut(.defaultAction)
            case .running:
                Text("Applying your changes.").foregroundStyle(.secondary)
                Spacer()
            case .guide:
                Button("Leave pending") { model.skip() }.disabled(model.busy)
                Spacer()
                Button("Test passed") { model.completeGuide() }
                    .disabled(model.busy || !model.checkReady || model.checkedSteps.count != model.steps.count)
            case .failed:
                Button("Back") { onReturn?() }
                if model.current != nil {
                    Button("Leave pending") { model.skip() }
                }
                Spacer()
                Button("Retry") { model.advance() }.disabled(model.busy)
            case .finished:
                Text("Your changes have been saved.").foregroundStyle(.secondary)
                Spacer()
                Button("Continue customizing") {
                    if model.scope == .workspaces { model.openEditor(.workspaces) }
                    else if model.scope == .shortcuts { model.openEditor(.shortcuts) }
                    else { onReturn?() }
                }.keyboardShortcut(.defaultAction)
            case .features:
                Spacer()
                Button("Back to features") { onReturn?() }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        HStack {
            switch model.page {
            case .features:
                Text("\(model.picker.selectedCount) selected tasks").foregroundStyle(.secondary)
                Spacer()
                if model.pausedSetup {
                    Button("Resume setup") { model.resumeAfterEdits() }
                        .disabled(model.busy).keyboardShortcut(.defaultAction)
                } else {
                Button("Continue") {
                    model.scope = .full
                    if model.picker.selected.contains("aerospace-profile")
                        || model.picker.selected.contains("karabiner-profile")
                        || model.picker.selected.contains("raycast-profile") {
                        model.page = .shortcuts
                    } else { model.review() }
                }.disabled(model.busy || model.picker.selectedCount == 0).keyboardShortcut(.defaultAction)
                }
            case .shortcuts:
                Button("Back") { model.returnToFeatures() }; Spacer()
                Button("Continue") {
                    if model.scope == .shortcuts { model.review() }
                    else if model.picker.selected.contains("aerospace-profile") { model.page = .workspaces }
                    else { model.review() }
                }.disabled(model.workspaceError(in: model.layout) != nil)
                    .keyboardShortcut(.defaultAction)
            case .workspaces:
                Button("Back") {
                    if model.scope == .full { model.page = .shortcuts }
                    else { model.returnToFeatures() }
                }; Spacer()
                Button("Review changes") { model.review() }.keyboardShortcut(.defaultAction)
            case .review:
                Button("Back") { model.page = model.scope == .workspaces ? .workspaces : .shortcuts }; Spacer()
                Button("Start setup") { model.start() }.keyboardShortcut(.defaultAction)
            case .guide:
                Button("Back to task selection") { model.pauseForEdits() }
                    .disabled(model.busy)
                Button("Leave pending & continue") { model.skip() }.disabled(model.busy); Spacer()
                Button("Test passed — continue") { model.completeGuide() }.disabled(model.busy || !model.checkReady || model.checkedSteps.count != model.steps.count).keyboardShortcut(.defaultAction)
            case .failed:
                Button("Change selection") { model.pauseForEdits() }
                if model.current != nil { Button("Leave pending & continue") { model.skip() } }
                Spacer(); Button("Retry this task") { model.advance() }.keyboardShortcut(.defaultAction)
            case .running:
                Text("Keep this window open while the installer finishes.").foregroundStyle(.secondary); Spacer()
            case .finished:
                Text("Backups are stored locally in Application Support/mac-setup.").foregroundStyle(.secondary)
                Spacer()
                Button("Edit again") { model.scope = .full; model.page = .features; model.refreshInventory() }
                Button("Close") { NSApplication.shared.terminate(nil) }.keyboardShortcut(.defaultAction)
            }
        }
    }

}

enum NativeSetup {
    static func run(ids: [String]? = nil, preset: SetupPreset? = nil,
                    workspaceEditor: Bool = false, shortcutEditor: Bool = false,
                    guided: Bool = false) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if let icon = AppResources.iconURL, let image = NSImage(contentsOf: icon) { app.applicationIconImage = image }
        let model = try SetupModel(ids: ids, preset: preset)
        if workspaceEditor { model.openEditor(.workspaces) }
        if shortcutEditor { model.openEditor(.shortcuts) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 830), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Mac Setup"
        let initial: ControlDestination = workspaceEditor ? .workspaces
            : (shortcutEditor ? .shortcuts : .home)
        // Guided setup uses the same real sections and controls as the dashboard.
        window.contentView = NSHostingView(
            rootView: ControlCenterView(model: model, initialDestination: initial,
                                        startGuided: guided,
                                        hasPreparedSelection: ids != nil || preset != nil))
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        let delegate = SetupWindowDelegate(model: model)
        window.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

private final class SetupWindowDelegate: NSObject, NSWindowDelegate {
    let model: SetupModel
    init(model: SetupModel) { self.model = model }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.busy && model.page != .features {
            let alert = NSAlert()
            alert.messageText = "An installer is still running"
            alert.informativeText = "Keep setup open until this task finishes."
            alert.runModal()
            return false
        }
        return true
    }
    func windowWillClose(_ notification: Notification) { NSApplication.shared.terminate(nil) }
}
