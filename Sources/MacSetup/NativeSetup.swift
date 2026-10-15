import AppKit
import SwiftUI
import MacSetupCore

enum SetupPage: Hashable { case features, shortcuts, workspaces, workspaceBar, review, running, guide, failed, finished }
enum SetupScope { case full, workspaces, workspaceBar, shortcuts, feature }

final class SetupModel: ObservableObject {
    @Published var page: SetupPage = .features
    @Published var picker = TaskPickerState(preset: .repair)
    @Published var states: [String: String] = [:]
    @Published var layout = WorkspaceConfiguration.defaultLayout
    @Published var shortcuts = ShortcutSettings(entries: [])
    @Published private(set) var appliedLayout = WorkspaceConfiguration.defaultLayout
    @Published private(set) var appliedShortcuts = ShortcutSettings(entries: [])
    var workspaceHasDraftChanges: Bool {
        layout.workspaces != appliedLayout.workspaces || layout.keymap != appliedLayout.keymap
    }
    var barHasDraftChanges: Bool { layout.barStyle != appliedLayout.barStyle }
    var shortcutsHaveDraftChanges: Bool { shortcuts != appliedShortcuts }
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
    @Published var selectedWorkspaceID: String?
    @Published var appSheet = false
    @Published var appSearch = ""
    @Published var manualAppID = ""
    @Published var runLog = ""
    @Published private(set) var runtimeIssues: [String] = []
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
        let loadedWorkspaces = try WorkspaceConfiguration.loadForEditing(from: engine.paths)
        layout = loadedWorkspaces.draft
        appliedLayout = loadedWorkspaces.original
        if !loadedWorkspaces.repairs.isEmpty {
            message = "Workspace identity updates are proposed in this draft. Review them, then apply to update the running desktop."
            + "\n" + loadedWorkspaces.repairs.joined(separator: "\n")
        }
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
        // Keep a pending ID-repair explanation until the repaired draft is
        // applied; unrelated transient errors should not survive navigation.
        if !message.hasPrefix("Workspace identity updates are proposed") { message = "" }
        page = selected == .workspaces ? .workspaces : selected == .workspaceBar ? .workspaceBar : .shortcuts
    }

    func repairWorkspaceIDs() {
        let repairs = layout.repairWorkspaceIDs()
        if !repairs.isEmpty {
            message = "Proposed workspace ID repairs (not saved yet):\n" + repairs.joined(separator: "\n")
        }
    }

    var hasInvalidWorkspaceIDs: Bool {
        var draft = layout
        return !draft.repairWorkspaceIDs().isEmpty
    }

    func review() {
        do {
            if let error = configurationError(for: scope) { throw SetupError(error) }
            let chosen: [String]
            switch scope {
            case .full: chosen = picker.orderedSelection
            case .workspaces: chosen = ["aerospace-profile", "sketchybar-profile"]
            case .workspaceBar: chosen = ["sketchybar-profile"]
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
                let selected = try selectedConfiguration(taskIDs: Set(picker.orderedSelection))
                if selected.layout != nil || selected.shortcuts != nil {
                    try (selected.shortcuts ?? appliedShortcuts).validate(
                        workspaces: selected.layout ?? appliedLayout, aerospaceTemplate: aerospaceTemplate)
                }
            case .workspaces:
                var pending = layout
                pending.barStyle = appliedLayout.barStyle
                try appliedShortcuts.validateWorkspaceBindings(pending, aerospaceTemplate: aerospaceTemplate)
            case .workspaceBar:
                try layout.barStyle.validate()
            case .shortcuts:
                try shortcuts.validate(workspaces: appliedLayout, aerospaceTemplate: aerospaceTemplate)
            case .feature: break
            }
            return nil
        } catch { return String(describing: error) }
    }

    private func selectedConfiguration(taskIDs: Set<String>) throws -> SelectedConfiguration {
        SelectedConfiguration(taskIDs: taskIDs, draftLayout: layout, draftShortcuts: shortcuts,
                              savedLayout: try WorkspaceConfiguration.loadForEditing(from: engine.paths).original,
                              savedShortcuts: try ShortcutSettings.load(from: engine.paths, aerospaceTemplate: aerospaceTemplate))
    }

    func start() {
        if scope == .workspaces || scope == .workspaceBar || scope == .shortcuts {
            startEditorConfiguration()
            return
        }
        do {
            setupLock = try SetupLock(paths: engine.paths)
            switch scope {
            case .full:
                if let error = configurationError(for: .full) { throw SetupError(error) }
                let selected = try selectedConfiguration(taskIDs: Set(tasks.map(\.id)))
                engine.draftLayout = selected.layout
                engine.draftShortcuts = selected.shortcuts
            case .feature:
                engine.draftLayout = nil
                engine.draftShortcuts = nil
            case .workspaces, .workspaceBar, .shortcuts: return
            }
            engine.selectedWorkspaceTaskIDs = scope == .full ? picker.selected : nil
            pausedSetup = false
            runtimeIssues = []
            index = 0; results = [:]; runLog = ""
            log("Starting \(scope) with \(tasks.count) selected tasks")
            log("Reviewed configuration stays in memory until its profile task succeeds.")
            log("Workspace order: \(layout.workspaces.map(\.id).joined(separator: ", "))")
            log("Switch modifiers: \(layout.keymap.switchModifiers.joined(separator: "+")); move modifiers: \(layout.keymap.moveModifiers.joined(separator: "+"))")
            advance()
        } catch {
            setupLock = nil
            message = String(describing: error)
        }
    }

    func retry() {
        if scope == .workspaces || scope == .workspaceBar || scope == .shortcuts { start() }
        else { advance() }
    }

    private func startEditorConfiguration() {
        do {
            setupLock = try SetupLock(paths: engine.paths)
            engine.draftLayout = nil
            engine.draftShortcuts = nil
            let saved = try WorkspaceConfiguration.loadForEditing(from: engine.paths).original
            var chosen = saved
            let chosenShortcuts: ShortcutSettings?
            switch scope {
            case .workspaces:
                chosen.workspaces = layout.workspaces
                chosen.keymap = layout.keymap
                chosenShortcuts = nil
            case .workspaceBar:
                chosen.barStyle = layout.barStyle
                chosenShortcuts = nil
            case .shortcuts:
                chosenShortcuts = shortcuts
            default: return
            }
            let chosenLayout = scope == .shortcuts ? nil : chosen
            let selectedTasks = tasks
            busy = true; page = .running; results = [:]; message = ""; details = ""; runtimeIssues = []
            runLog = ""; log("Applying \(scope) with coordinated recovery")
            worker.async { [self] in
                do {
                    let issues = try engine.applyConfiguration(layout: chosenLayout, shortcuts: chosenShortcuts,
                                                               tasks: selectedTasks)
                    DispatchQueue.main.async {
                        self.results = Dictionary(uniqueKeysWithValues: selectedTasks.map { ($0.id, "Complete") })
                        self.runtimeIssues = issues
                        // These are the saved baseline. Live checks remain separately visible.
                        self.appliedLayout = chosen
                        if let chosenShortcuts { self.appliedShortcuts = chosenShortcuts }
                        self.log(issues.isEmpty ? "Selected configuration applied." : issues.joined(separator: "\n"))
                        self.busy = false; self.page = .finished; self.setupLock = nil
                        self.refreshInventory()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.log("Configuration failed: \(error)")
                        self.busy = false; self.page = .failed; self.setupLock = nil
                        self.message = "Your draft is still available. Review the recovery result below, then retry."
                        self.details = String(describing: error)
                    }
                }
            }
        } catch { setupLock = nil; message = String(describing: error) }
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
                    let ids = Set(tasks.map(\.id))
                    let issues = engine.workspaceRuntimeIssues(
                        checkAeroSpace: ids.contains("aerospace-profile"),
                        checkSketchyBar: ids.contains("sketchybar-profile"))
                    let updatedLayout = try? WorkspaceConfiguration.load(from: engine.paths)
                    let updatedShortcuts = try? ShortcutSettings.load(
                        from: engine.paths, aerospaceTemplate: aerospaceTemplate)
                    DispatchQueue.main.async {
                        self.runtimeIssues = issues
                        self.log(issues.isEmpty
                            ? "Selected files updated. Live workspace queries passed where applicable; verify actual shortcuts and desktop behavior."
                            : "Selected files updated, but live workspace verification reported \(issues.count) issue(s).")
                        if issues.isEmpty && !self.results.values.contains("Pending") {
                            if let updatedLayout, ids.contains("aerospace-profile") || ids.contains("sketchybar-profile") {
                                self.appliedLayout = updatedLayout
                            }
                            if let updatedShortcuts, !ids.isDisjoint(with: ["aerospace-profile", "karabiner-profile", "raycast-profile"]) {
                                self.appliedShortcuts = updatedShortcuts
                            }
                        }
                        self.busy = false
                        self.page = .finished
                        self.setupLock = nil
                        self.engine.draftLayout = nil
                        self.engine.draftShortcuts = nil
                        self.refreshInventory()
                    }
                } catch {
                    DispatchQueue.main.async { self.log("Restart failed: \(error)"); self.busy = false; self.message = String(describing: error); self.page = .failed }
                }
            }
            return
        }
        if let prerequisite = task.dependencies.first(where: { results[$0] == "Pending" }) {
            log("\(task.id): left pending because \(prerequisite) is unfinished")
            results[task.id] = "Pending"
            index += 1
            advance()
            return
        }
        log("Task \(index + 1)/\(tasks.count): \(task.id) (\(task.title))")
        busy = true; page = .running
        worker.async { [self] in
            do {
                for dependency in task.dependencies {
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
                let refreshEditedProfile = scope == .workspaces
                    && ["aerospace-profile", "sketchybar-profile"].contains(task.id)
                    || scope == .shortcuts
                    && ["aerospace-profile", "karabiner-profile"].contains(task.id)
                    || scope == .full && (engine.draftLayout != nil || engine.draftShortcuts != nil)
                    && ["aerospace-profile", "sketchybar-profile", "karabiner-profile", "raycast-profile"].contains(task.id)
                let already = state == .done
                    && task.id != "sketchybar-start" && !refreshEditedProfile
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

    func refreshRuntimeVerification() {
        let ids = Set(tasks.map(\.id))
        busy = true
        worker.async { [self] in
            let issues = engine.workspaceRuntimeIssues(
                checkAeroSpace: ids.contains("aerospace-profile"),
                checkSketchyBar: ids.contains("sketchybar-profile"))
            let updated = try? WorkspaceConfiguration.load(from: engine.paths)
            DispatchQueue.main.async {
                self.runtimeIssues = issues
                self.busy = false
                if issues.isEmpty && !self.results.values.contains("Pending"), let updated {
                    self.appliedLayout = updated
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
            if let error = configurationError(for: .full) { throw SetupError(error) }
            let changed = try Catalog.ordered(picker.orderedSelection, includingDependencies: false)
            let selectedIDs = Set(changed.map(\.id))
            let previousID = current?.id
            tasks = changed
            results = results.filter { selectedIDs.contains($0.key) }
            if let previousID, !selectedIDs.contains(previousID) {
                log("Removed interrupted task \(previousID) from this run")
            }
            let selected = try selectedConfiguration(taskIDs: selectedIDs)
            let previousLayout = try WorkspaceConfiguration.load(from: engine.paths)
            let previousShortcuts = try ShortcutSettings.load(from: engine.paths, aerospaceTemplate: aerospaceTemplate)
            // Re-run profile tasks whose inputs changed while setup was paused.
            if let next = selected.layout, next != previousLayout {
                for id in ["aerospace-profile", "sketchybar-profile", "sketchybar-start"] { results.removeValue(forKey: id) }
            }
            if let next = selected.shortcuts, next != previousShortcuts {
                for id in ["aerospace-profile", "karabiner-profile", "raycast-profile"] { results.removeValue(forKey: id) }
            }
            engine.draftLayout = selected.layout
            engine.draftShortcuts = selected.shortcuts
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
        engine.draftLayout = nil
        engine.draftShortcuts = nil
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

    @Environment(\.accessibilityReduceMotion) private var reducedMotion

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
                    case .workspaceBar: workspaceBar
                    case .review: review
                    case .running: running
                    case .guide: guide
                    case .failed: failed
                    case .finished: finished
                    }
                }
                .padding(SetupDesign.pagePadding)
                .frame(maxWidth: SetupDesign.pageWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .id(model.page)
            Divider()
            Group {
                if embedded { embeddedFooter }
                else { footer }
            }
            .padding(.horizontal, SetupDesign.pagePadding)
            .padding(.vertical, 16)
            .frame(maxWidth: SetupDesign.pageWidth)
            .frame(maxWidth: .infinity)
        }
        .font(SetupDesign.body)
        .frame(minWidth: embedded ? 680 : 820, minHeight: embedded ? 610 : 660)
        .sheet(isPresented: $model.appSheet) { appAssignments }
        .sheet(isPresented: Binding(get: { glyphWorkspaceID != nil }, set: { if !$0 { glyphWorkspaceID = nil } })) {
            if let i = model.layout.workspaces.firstIndex(where: { $0.id == glyphWorkspaceID }) {
                GlyphPicker(workspace: model.layout.workspaces[i]) { model.layout.workspaces[i].icon = $0 }
            }
        }

    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose what to configure").font(SetupDesign.pageTitle)
            Text("Choose the features to install, or update an existing workspace layout or keymap without repeating setup.")
            if model.pausedSetup {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Setup paused at task \(min(model.index + 1, model.tasks.count)) of \(model.tasks.count)",
                          systemImage: "pause.circle.fill").font(SetupDesign.sectionTitle)
                    Text("Change the selected tasks below, then resume where you stopped. Completed tasks will not run again.")
                        .font(SetupDesign.body).foregroundStyle(.secondary)
                    Button("Resume setup") { model.resumeAfterEdits() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SetupDesign.cardRadius))
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
                        withAnimation(reducedMotion ? nil : .easeInOut(duration: 0.16)) {
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
                                            Text(task.summary).font(SetupDesign.body).foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }.toggleStyle(.checkbox).disabled(model.busy)
                                    Spacer(minLength: 8)
                                    Text(task.guided ? "User approval" : "Automatic")
                                        .font(SetupDesign.caption).foregroundStyle(.secondary)
                                        .frame(width: 102, alignment: .trailing)
                                }
                            }
                        }.padding(18)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SetupDesign.cardRadius))
            }
            Text(model.picker.preset?.summary ?? "Custom selection. Open a section to change its tasks.").foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShortcutStudio(settings: $model.shortcuts, layout: $model.layout,
                           apps: model.apps, aerospaceTemplate: model.aerospaceTemplate,
                           karabinerTemplate: model.karabinerTemplate)
            // ShortcutStudio owns its inline validation. Do not show a
            // second, identical error beneath the editor.
        }
    }

    private var workspaceKeys: [String] {
        WorkspaceConfiguration.keys + Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
    }

    /// This is an editable SketchyBar mock, not a material app card.
    /// The menu bar itself is drawn as the thin black strip users actually see.
    private var menuBarPreview: some View {
        let style = model.page == .workspaceBar ? model.layout.barStyle : model.appliedLayout.barStyle
        let workspaces = model.page == .workspaceBar ? model.appliedLayout.workspaces : model.layout.workspaces
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("SKETCHYBAR PREVIEW")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Approximate preview. Apply to update the running bar.")
                    .font(SetupDesign.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 2) {
                ForEach(workspaces, id: \.id) { workspace in
                    Text(workspace.resolvedIcon.symbol)
                        .font(.custom(workspace.resolvedIcon.font.postScriptName, size: 15))
                        .frame(width: CGFloat(style.itemWidth), height: 30)
                        .help(workspace.name)
                }
                Spacer(minLength: 14)
                Text(previewTime).font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(WorkspaceColor.swiftUI(style.occupiedColor))
            .padding(.horizontal, 16)
            .frame(height: 33)
            .background(WorkspaceColor.swiftUI(style.backgroundColor), in: Capsule())
            .padding(.vertical, 5)
        }
    }

    private var workspaceColumns: some View {
        HStack(spacing: WorkspaceColumns.gap) {
            Color.clear.frame(width: WorkspaceColumns.grip)
            Text("Icon").frame(width: WorkspaceColumns.glyph)
            Text("Name").frame(minWidth: 120, maxWidth: .infinity, alignment: .center)
            Text("Apps").frame(width: WorkspaceColumns.apps, alignment: .center)
            Text("Key").frame(width: WorkspaceColumns.key, alignment: .center)
            Text("Display").frame(width: WorkspaceColumns.display, alignment: .center)
            Color.clear.frame(width: WorkspaceColumns.remove)
        }
        .font(SetupDesign.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, WorkspaceColumns.inset)
    }

    private var workspaces: some View {
        VStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
            SetupPageHeader("Workspaces", subtitle: "Name your workspaces, assign apps and choose their keys and displays. Drag the grip or use Move up / Move down to reorder; review before applying.")
            menuBarPreview

            Label(model.workspaceHasDraftChanges ? "Workspace changes need applying or verification" : "No local workspace edits",
                  systemImage: model.workspaceHasDraftChanges ? "square.and.pencil" : "checkmark.circle")
                .font(SetupDesign.body)
                .foregroundStyle(model.workspaceHasDraftChanges ? Color.orange : Color.secondary)
            Divider()
            workspaceColumns
            VStack(spacing: 5) {
                ForEach(visibleWorkspaceIDs, id: \.self) { id in
                    if let index = model.layout.workspaces.firstIndex(where: { $0.id == id }) {
                        workspaceCard(at: index)
                    }
                }
            }
            .animation(reducedMotion ? nil : .easeInOut(duration: 0.16), value: visibleWorkspaceIDs)
            Button {
                model.layout.addWorkspace()
            } label: {
                Label("Add workspace", systemImage: "plus")
            }
            .padding(.top, 4)

            WorkspaceModifierControls(keymap: $model.layout.keymap)

            if model.hasInvalidWorkspaceIDs {
                Button("Repair workspace references") {
                    model.repairWorkspaceIDs()
                }
                .help("Propose unique, safe IDs without discarding workspaces or their assignments")
            }
            // Only one live validation message, never a repeated copy from
            // the last unsuccessful Apply attempt.
            let validationError = model.configurationError(for: .workspaces)
            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle")
                    .font(SetupDesign.body).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.message.isEmpty && model.message != validationError {
                Text(model.message).font(SetupDesign.body).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workspaceBar: some View {
        VStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
            SetupPageHeader("Workspace bar", subtitle: "Adjust the bar’s colors, spacing and blur. Change workspace names, app routing, keys and displays in Workspaces.")
            menuBarPreview
            workspaceAppearance
            DesktopAccentControls(engine: model.engine)
            if let error = model.configurationError(for: .workspaceBar) {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.orange) }
        }
    }

    private var workspaceAppearance: some View {
        let style = model.layout.barStyle
        return VStack(alignment: .leading, spacing: 14) {
            Text("SketchyBar layout and colors").font(SetupDesign.sectionTitle)
            Text("Adjust the bar background, blur, and occupied or empty workspaces that are not focused. Wallpaper highlighting of the focused workspace stays separate.")
                .font(SetupDesign.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                ColorPicker("Occupied", selection: appearanceColor(\.occupiedColor), supportsOpacity: true)
                ColorPicker("Empty", selection: appearanceColor(\.emptyColor), supportsOpacity: true)
                ColorPicker("Bar background", selection: appearanceColor(\.backgroundColor), supportsOpacity: true)
            }
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Workspace spacing")
                        Spacer()
                        Text("\(style.itemWidth) pt").monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(model.layout.barStyle.itemWidth) },
                        set: { model.layout.barStyle.itemWidth = Int($0) }),
                        in: 16...52, step: 1)
                    Text("Controls the width of each workspace item.")
                        .font(SetupDesign.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Background blur")
                        Spacer()
                        Text("\(style.blurRadius)").monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(model.layout.barStyle.blurRadius) },
                        set: { model.layout.barStyle.blurRadius = Int($0) }),
                        in: 0...100, step: 5)
                    Text("SketchyBar blur radius; macOS renders the final effect.")
                        .font(SetupDesign.caption).foregroundStyle(.secondary)
                }
            }
        }
        .setupCard()
    }

    private func appearanceColor(_ key: WritableKeyPath<WorkspaceBarStyle, String>) -> Binding<Color> {
        Binding(
            get: { WorkspaceColor.swiftUI(model.layout.barStyle[keyPath: key]) },
            set: { model.layout.barStyle[keyPath: key] = WorkspaceColor.argb($0) }
        )
    }

    private func workspaceCard(at index: Int) -> some View {
        let item = model.layout.workspaces[index]
        let glyph = item.resolvedIcon
        let count = item.apps.count
        let appCountLabel = "\(count) \(count == 1 ? "app" : "apps")"
        let dragID = "mac-setup-workspace:\(workspaceDragSession):\(item.id)"
        return HStack(spacing: WorkspaceColumns.gap) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: WorkspaceColumns.grip, height: SetupDesign.controlHeight)
                .help("Drag to reorder \(item.name)")
                .accessibilityLabel("Drag \(item.name) to reorder")
                .draggable(dragID) {
                    Label(item.name, systemImage: "circle.grid.3x3.fill")
                        .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            Button { glyphWorkspaceID = item.id } label: {
                Group {
                    if glyph.symbol == "?" { Image(systemName: "plus.square.dashed") }
                    else { Text(glyph.symbol).font(.custom(glyph.font.postScriptName, size: 19)) }
                }
                .workspaceControl()
            }
            .buttonStyle(.plain).frame(width: WorkspaceColumns.glyph)
            .help("Change icon for \(item.name)").accessibilityLabel("Icon for \(item.name)")

            WorkspaceNameField(name: item.name) { name in
                do { try model.layout.renameWorkspace(item.id, to: name) }
                catch { model.message = String(describing: error) }
            }.frame(minWidth: 120, maxWidth: .infinity)

            Button {
                model.selectedWorkspaceID = item.id
                model.appSheet = true
            } label: {
                workspaceMenuLabel(appCountLabel)
            }
            .buttonStyle(.plain).frame(width: WorkspaceColumns.apps)
            .help("Edit assigned applications").accessibilityLabel("Apps for \(item.name)")
            .accessibilityValue(appCountLabel)

            workspaceShortcutKey(at: index).frame(width: WorkspaceColumns.key)

            Menu {
                Button("Automatic") { model.layout.workspaces[index].monitor = .automatic }
                Button("Main display") { model.layout.workspaces[index].monitor = .main }
                Button("Secondary display") { model.layout.workspaces[index].monitor = .secondary }
            } label: {
                Text(item.resolvedMonitor == .automatic ? "Automatic" : item.resolvedMonitor == .main ? "Main" : "Secondary")
            }
            .workspaceDropdown()
            .frame(width: WorkspaceColumns.display)
            .accessibilityValue(item.resolvedMonitor.rawValue)
            .help("Preferred display for \(item.name)").accessibilityLabel("Display for \(item.name)")

            Button { model.layout.removeWorkspace(item.id) } label: {
                Image(systemName: "trash").font(.system(size: 13))
                    .frame(width: WorkspaceColumns.remove, height: SetupDesign.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(model.layout.workspaces.count == 1)
            .help("Remove \(item.name)").accessibilityLabel("Remove \(item.name)")
        }
        .padding(.horizontal, WorkspaceColumns.inset).padding(.vertical, WorkspaceColumns.verticalInset)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SetupDesign.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: SetupDesign.cardRadius)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1))
        .overlay(alignment: .top) {
            if dropTargetWorkspaceID == item.id {
                Capsule().fill(Color.accentColor).frame(height: 3).offset(y: -3)
            }
        }
        .contextMenu {
            Button("Move up") { moveWorkspace(item.id, by: -1) }
                .disabled(index == 0)
            Button("Move down") { moveWorkspace(item.id, by: 1) }
                .disabled(index == model.layout.workspaces.count - 1)
        }
        .accessibilityAction(named: Text("Move workspace up")) {
            moveWorkspace(item.id, by: -1)
        }
        .accessibilityAction(named: Text("Move workspace down")) {
            moveWorkspace(item.id, by: 1)
        }
        .dropDestination(for: String.self) { dragged, location in
            let prefix = "mac-setup-workspace:\(workspaceDragSession):"
            guard dragged.count == 1, let raw = dragged.first, raw.hasPrefix(prefix) else { return false }
            let source = String(raw.dropFirst(prefix.count))
            guard visibleWorkspaceIDs.contains(source) else { return false }
            withAnimation(reducedMotion ? nil : .easeInOut(duration: 0.16)) {
                model.layout.insertWorkspace(source, at: location.y > (SetupDesign.controlHeight + WorkspaceColumns.verticalInset * 2) / 2 ? index + 1 : index)
            }
            dropTargetWorkspaceID = nil
            return true
        } isTargeted: { hovering in
            if hovering { dropTargetWorkspaceID = item.id }
            else if dropTargetWorkspaceID == item.id { dropTargetWorkspaceID = nil }
        }
    }

    private func moveWorkspace(_ id: String, by offset: Int) {
        guard let index = model.layout.workspaces.firstIndex(where: { $0.id == id }),
              model.layout.workspaces.indices.contains(index + offset) else { return }
        withAnimation(reducedMotion ? nil : .easeInOut(duration: 0.16)) {
            model.layout.insertWorkspace(id, at: offset < 0 ? index - 1 : index + 2)
        }
    }

    private func workspaceShortcutKey(at index: Int) -> some View {
        let item = model.layout.workspaces[index]
        let key = item.shortcutKey ?? item.shortcuts?.switchTo?.key
            ?? (WorkspaceConfiguration.keys.indices.contains(index)
                ? WorkspaceConfiguration.keys[index] : "")
        return Menu {
            Button("None") {
                model.layout.workspaces[index].shortcutKey = ""
                model.layout.workspaces[index].shortcuts = nil
            }
            ForEach(workspaceKeys, id: \.self) { selected in
                Button(WorkspaceShortcut.keyLabel(selected)) {
                    model.layout.workspaces[index].shortcutKey = selected
                    model.layout.workspaces[index].shortcuts = nil
                }
            }
        } label: {
            Text(key.isEmpty ? "None" : WorkspaceShortcut.keyLabel(key))
        }
        .workspaceDropdown()
        .accessibilityValue(key.isEmpty ? "None" : WorkspaceShortcut.keyLabel(key))
        .help("Click to change shortcut for \(item.name)")
        .accessibilityLabel("Change shortcut for \(item.name)")
    }

    private func workspaceMenuLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            WorkspaceDisclosure(direction: "right")
        }
        .padding(.horizontal, 8).workspaceControl()
        .foregroundStyle(Color.primary)
    }

    @ViewBuilder private var appAssignments: some View {
        if let id = model.selectedWorkspaceID,
           let index = model.layout.workspaces.firstIndex(where: { $0.id == id }) {
            let savedIDs = Set(model.layout.workspaces.flatMap(\.apps))
            let installedIDs = Set(model.apps.map(\.bundleID))
            let missing = savedIDs.subtracting(installedIDs).map {
                InstalledApplication(name: $0, bundleID: $0, path: "")
            }
            let apps = (model.apps + missing).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            VStack(alignment: .leading, spacing: 16) {
                Text("Apps for \(model.layout.workspaces[index].name)").font(SetupDesign.sheetTitle)
                Text("New windows open in their assigned workspace. Assignments stay available when an app is not installed.")
                    .font(SetupDesign.body).foregroundStyle(.secondary)
                TextField("Find an app or bundle ID", text: $model.appSearch).textFieldStyle(.roundedBorder)
                List(apps.filter { model.appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(model.appSearch)
                    || $0.bundleID.localizedCaseInsensitiveContains(model.appSearch) }, id: \.bundleID) { app in
                    Toggle(isOn: Binding(get: { model.layout.workspaces[index].apps.contains(app.bundleID) }, set: { enabled in
                        for i in model.layout.workspaces.indices { model.layout.workspaces[i].apps.removeAll { $0 == app.bundleID } }
                        if enabled { model.layout.workspaces[index].apps.append(app.bundleID) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.path.isEmpty ? "Not installed · " + app.bundleID : app.bundleID)
                                .font(SetupDesign.caption).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.checkbox)
                }
                HStack {
                    TextField("Application bundle ID", text: $model.manualAppID).textFieldStyle(.roundedBorder)
                    Button("Assign") {
                        let bundle = model.manualAppID.trimmingCharacters(in: .whitespacesAndNewlines)
                        var pending = model.layout
                        for i in pending.workspaces.indices { pending.workspaces[i].apps.removeAll { $0 == bundle } }
                        pending.workspaces[index].apps.append(bundle)
                        do { try pending.validate(); model.layout = pending; model.manualAppID = "" }
                        catch { model.message = String(describing: error) }
                    }.disabled(model.manualAppID.isEmpty)
                }
                if !model.message.isEmpty { Text(model.message).font(SetupDesign.caption).foregroundStyle(.orange) }
                HStack { Spacer(); Button("Done") { model.appSheet = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 540, height: 560)
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to apply \(model.tasks.count) tasks").font(SetupDesign.pageTitle)
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
            Text(model.current?.title ?? "Refreshing your desktop").font(SetupDesign.pageTitle)
            ProgressView(value: Double(model.index), total: Double(max(1, model.tasks.count)))
            Text("Task \(min(model.index + 1, model.tasks.count)) of \(model.tasks.count) · \(model.completed) complete").foregroundStyle(.secondary)
            Text(model.current?.summary ?? "Applying the saved Finder, Dock and menu bar preferences.")
            HStack {
                Text("Apply log").font(SetupDesign.sectionTitle)
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
            Text(model.current?.title ?? "Test your setup").font(SetupDesign.pageTitle)
            Text("Task \(model.index + 1) of \(model.tasks.count). Follow each step below. Open the related setting and check that step before continuing.")
                .font(SetupDesign.body)
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
                                .font(SetupDesign.caption)
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
                    .font(SetupDesign.body)
                    .foregroundStyle(model.checkReady ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(model.current?.title ?? "Refresh needs attention", systemImage: "exclamationmark.triangle").font(SetupDesign.pageTitle)
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
            Text(model.results.values.contains("Pending")
                 ? "Setup saved; some tasks still need attention"
                 : (model.runtimeIssues.isEmpty ? "Setup tasks finished" : "Files updated; live checks need attention"))
                .font(SetupDesign.pageTitle)
            Button { copyLog() } label: { Label("Copy apply log", systemImage: "doc.on.doc") }
            Text("Move the pointer to the bottom edge: the Dock should reveal promptly. The macOS menu bar should hide when the pointer leaves the top. Its reveal timing is controlled by macOS. If it still stays visible, set Automatically hide and show the menu bar to Always in System Settings, then log out and back in.")
            Text("Check the workspace highlight with your chosen modifiers and destination key, then use the move-window shortcut to send a window to another workspace.")
            if !model.runtimeIssues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Live workspace verification needs attention", systemImage: "exclamationmark.triangle")
                        .font(SetupDesign.sectionTitle)
                    ForEach(model.runtimeIssues, id: \.self) { issue in
                        Text(issue).font(SetupDesign.body).textSelection(.enabled)
                    }
                    Button("Check running apps again") { model.refreshRuntimeVerification() }
                        .disabled(model.busy)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
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
            case .workspaces, .workspaceBar, .shortcuts:
                Text(model.page == .workspaces
                     ? (model.workspaceHasDraftChanges ? "Workspace edits are not confirmed active." : "No local workspace edits.")
                     : model.page == .workspaceBar
                     ? (model.barHasDraftChanges ? "Bar appearance has unapplied edits." : "No local bar appearance edits.")
                     : (model.shortcutsHaveDraftChanges ? "Shortcut edits are not confirmed active." : "No local shortcut edits."))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.page == .workspaces ? "Review & apply workspaces" : model.page == .workspaceBar ? "Review & apply bar" : "Review & apply shortcuts") {
                    model.review()
                }
                .disabled(model.busy || model.configurationError(for: model.scope) != nil)
                .keyboardShortcut(.defaultAction)
            case .review:
                Button(model.scope == .workspaces ? "Back to workspaces" :
                       (model.scope == .workspaceBar ? "Back to bar appearance" : model.scope == .shortcuts ? "Back to shortcuts" : "Back to features")) {
                    if model.scope == .workspaces { model.openEditor(.workspaces) }
                    else if model.scope == .workspaceBar { model.openEditor(.workspaceBar) }
                    else if model.scope == .shortcuts { model.openEditor(.shortcuts) }
                    else { onReturn?() }
                }
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
                Button("Retry") { model.retry() }.disabled(model.busy)
            case .finished:
                Text("Configuration saved. Desktop reload requested. Check SketchyBar and AeroSpace to confirm the live result.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue customizing") {
                    if model.scope == .workspaces { model.openEditor(.workspaces) }
                    else if model.scope == .workspaceBar { model.openEditor(.workspaceBar) }
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
            case .workspaces, .workspaceBar:
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
                Spacer(); Button("Retry this task") { model.retry() }.keyboardShortcut(.defaultAction)
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
        installMenus(for: app)
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
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }

    private static func installMenus(for app: NSApplication) {
        let bar = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = bar.addItem(withTitle: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            item.submenu = submenu
            return submenu
        }
        let application = menu("Mac Setup")
        application.addItem(withTitle: "About Mac Setup", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "Hide Mac Setup", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = application.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        application.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "Quit Mac Setup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu("File").addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = menu("Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let window = menu("Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        app.windowsMenu = window
        app.mainMenu = bar
    }
}

private final class SetupWindowDelegate: NSObject, NSWindowDelegate, NSApplicationDelegate {
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
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let window = sender.windows.first, !windowShouldClose(window) { return .terminateCancel }
        return .terminateNow
    }
}
