import AppKit
import SwiftUI
import MacSetupCore

private enum SetupPage: Hashable { case features, shortcuts, workspaces, review, running, guide, failed, finished }
enum SetupScope { case full, workspaces, shortcuts }

private final class SetupModel: ObservableObject {
    @Published var page: SetupPage = .features
    @Published var picker = TaskPickerState(preset: .repair)
    @Published var states: [String: String] = [:]
    @Published var layout = WorkspaceConfiguration.defaultLayout
    @Published var shortcuts = ShortcutSettings(entries: [])
    let aerospaceTemplate: String
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
    @Published var shortcutsConfirmed = false
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
        shortcuts = try ShortcutSettings.load(from: engine.paths, aerospaceTemplate: aerospaceTemplate)
        layout = try WorkspaceConfiguration.load(from: engine.paths)
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
        scope = selected
        message = ""
        shortcutsConfirmed = selected == .workspaces
        page = selected == .workspaces ? .workspaces : .shortcuts
    }

    func review() {
        do {
            if let error = workspaceError(in: layout) { throw SetupError(error) }
            let chosen: [String]
            switch scope {
            case .full: chosen = picker.orderedSelection
            case .workspaces: chosen = ["aerospace-profile", "sketchybar-profile", "sketchybar-start"]
            case .shortcuts: chosen = ["aerospace-profile", "karabiner-profile", "raycast-profile"]
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

    func start() {
        do {
            setupLock = try SetupLock(paths: engine.paths)
            if let error = workspaceError(in: layout) { throw SetupError(error) }
            try shortcuts.save(to: engine.paths)
            try layout.save(to: engine.paths)
            engine.selectedWorkspaceTaskIDs = scope == .full ? picker.selected : nil
            index = 0; results = [:]; runLog = ""
            log("Starting \(scope) with \(tasks.count) selected tasks")
            log("Workspace order: \(layout.workspaces.map(\.id).joined(separator: ", "))")
            log("Switch modifiers: \(layout.keymap.switchModifiers.joined(separator: "+")); move modifiers: \(layout.keymap.moveModifiers.joined(separator: "+"))")
            advance()
        } catch { message = String(describing: error) }
    }

    func advance() {
        message = ""; details = ""; installerOutput = ""; response = ""
        checkedSteps = []; checkReady = false
        guard let task = current else {
            log("Tasks complete. Refreshing desktop services")
            busy = true; page = .running
            worker.async { [self] in
                do {
                    try engine.finishRestarts()
                    DispatchQueue.main.async { self.log("Finished successfully"); self.busy = false; self.page = .finished; self.setupLock = nil }
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
        case "alacritty": return "Homebrew could not install Alacritty. Review the installer details below and retry. Option+Return needs this app installed."
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

    func returnToFeatures() { setupLock = nil; page = .features; refreshInventory() }

    func sendInput() { runner.send(response); response = "" }
}

private struct SetupView: View {
    @ObservedObject var model: SetupModel
    @LocalViewState private var glyphWorkspaceID: String?
    @LocalViewState private var workspaceDragSession = UUID().uuidString
    @LocalViewState private var dropTargetWorkspaceID: String?

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
            HStack {
                Image(systemName: "desktopcomputer").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up your Mac").font(.system(size: 26, weight: .semibold))
                    Text("Apps, workspaces, and the checks that make them work.").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.scope == .full ? "Step \(step) of 5" : "Edit settings").font(.headline)
            }.padding(24)
            HStack(spacing: 24) {
                ForEach(Array(["Choose features", "Shortcuts", "Workspaces", "Review", "Set up & test"].enumerated()), id: \.offset) { index, name in
                    Label(name, systemImage: index + 1 < step ? "checkmark.circle.fill" : "\(index + 1).circle")
                        .foregroundStyle(index + 1 == step ? Color.accentColor : Color.secondary)
                }
            }.padding(.horizontal, 24).padding(.bottom, 20)
            Divider()
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
            footer.padding(20)
        }
        .font(.system(size: 15))
        .frame(minWidth: 820, minHeight: 660)
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
                DisclosureGroup("\(category) · \(Catalog.tasks.filter { $0.category == category && model.picker.selected.contains($0.id) }.count) selected") {
                    VStack(alignment: .leading, spacing: 12) {
                    ForEach(Catalog.tasks.filter { $0.category == category && (model.search.isEmpty || ($0.title + " " + $0.summary).localizedCaseInsensitiveContains(model.search)) }, id: \.id) { task in
                        HStack(alignment: .top) {
                            Toggle(isOn: Binding(get: { model.picker.selected.contains(task.id) }, set: { _ in model.picker.toggle(task.id) })) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(task.title).fontWeight(.medium)
                                    Text(task.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }.toggleStyle(.checkbox).disabled(model.busy)
                            Spacer(minLength: 16)
                            Text(task.guided ? "You test" : "Automatic").font(.caption).foregroundStyle(.secondary).frame(width: 80)
                        }
                    }
                    }.padding(.top, 14)
                }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }
            Text(model.picker.preset?.summary ?? "Custom selection. Open a section to change its tasks.").foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShortcutStudio(settings: $model.shortcuts, layout: $model.layout,
                           apps: model.apps, aerospaceTemplate: model.aerospaceTemplate)
            if let error = model.workspaceError(in: model.layout) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
            }
        }
    }

    private var workspaceKeys: [String] {
        WorkspaceConfiguration.keys + Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
    }

    private var workspaces: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Workspaces").font(.title2.bold())
                Spacer()
                Button("Edit shortcuts") { model.page = .shortcuts }
                    .buttonStyle(.borderless)
            }
            Text("Drag a card to reorder it. Edit its name, symbol, assigned apps, and destination key.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("MENU BAR PREVIEW")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2).foregroundStyle(.tertiary)
                HStack(spacing: 0) {
                    ForEach(model.layout.forSelectedTasks(
                        model.scope == .full ? model.picker.selected : nil,
                        installedBundleIDs: installedIDs).workspaces, id: \.id) { workspace in
                        Text(workspace.resolvedIcon.symbol)
                            .font(.custom(workspace.resolvedIcon.font.postScriptName, size: 15))
                            .frame(width: 27).help(workspace.name)
                    }
                    Spacer(minLength: 12)
                    Text(previewTime).font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(DisplayGeometry.current().previewHeight))
                .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
            }.padding(.bottom, 10)

            VStack(spacing: 9) {
                ForEach(visibleWorkspaceIDs, id: \.self) { id in
                    if let index = model.layout.workspaces.firstIndex(where: { $0.id == id }) {
                        workspaceCard(at: index)
                    }
                }
            }
            Button {
                var number = 1
                while model.layout.workspaces.contains(where: { $0.id == "custom\(number)" }) { number += 1 }
                model.layout.workspaces.append(.init(id: "custom\(number)", name: "Workspace \(number)",
                                                      glyph: "star", shortcutKey: ""))
            } label: { Label("Add workspace", systemImage: "plus") }
                .padding(.top, 4)
            if let error = model.workspaceError(in: model.layout) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .padding(.vertical, 8)
            }
            if !model.message.isEmpty {
                Text(model.message).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func workspaceCard(at i: Int) -> some View {
        let item = model.layout.workspaces[i]
        let icon = item.resolvedIcon
        return HStack(spacing: 12) {
            Label("Drag", systemImage: "circle.grid.3x3.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 40)
                .help("Drag this card to insert it at another position")
                .accessibilityLabel("Drag workspace \(item.name)")
            TextField("Workspace name", text: $model.layout.workspaces[i].name)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Workspace name")
            Button { glyphWorkspaceID = item.id } label: {
                Group {
                    if icon.symbol == "?" {
                        Text("Glyph").font(.system(size: 12, weight: .medium))
                    } else {
                        Text(icon.symbol).font(.custom(icon.font.postScriptName, size: 21))
                    }
                }
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
            }
            .help("Select workspace symbol")
            .accessibilityLabel("Select symbol for \(item.name)")
            Button {
                model.selectedWorkspace = i
                model.appSheet = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: 17))
                    Text("\(model.layout.forSelectedTasks(model.scope == .full ? model.picker.selected : nil,
                        installedBundleIDs: installedIDs).workspaces[i].apps.count)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }.frame(width: 86, height: 38)
            }.help("Edit applications assigned to \(item.name)")
                .accessibilityLabel("Applications for \(item.name)")
            Picker("Key", selection: Binding(
                get: {
                    item.shortcutKey ?? item.shortcuts?.switchTo?.key
                        ?? (WorkspaceConfiguration.keys.indices.contains(i) ? WorkspaceConfiguration.keys[i] : "")
                },
                set: { key in
                    model.layout.workspaces[i].shortcutKey = key
                    model.layout.workspaces[i].shortcuts = nil
                })) {
                Text("No key").tag("")
                ForEach(workspaceKeys, id: \.self) { key in
                    Text(WorkspaceShortcut.keyLabel(key)).tag(key)
                }
            }.pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 104, height: 38)
                .help("Key for switching to and moving a window to \(item.name)")
            Button { model.layout.workspaces.remove(at: i) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 40, height: 38)
            }
            .disabled(model.layout.workspaces.count == 1)
            .help("Remove workspace")
            .accessibilityLabel("Remove workspace \(item.name)")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(alignment: .top) {
            if dropTargetWorkspaceID == item.id {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .draggable("mac-setup-workspace:\(workspaceDragSession):\(item.id)") {
            HStack(spacing: 13) {
                Image(systemName: "circle.grid.3x3.fill").foregroundStyle(.secondary)
                Text(icon.symbol).font(.custom(icon.font.postScriptName, size: 20))
                Text(item.name).fontWeight(.medium)
                Spacer()
                Label("\(item.apps.count)", systemImage: "square.grid.2x2.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(17)
            .frame(width: 510)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        }
        .dropDestination(for: String.self) { dragged, location in
            let prefix = "mac-setup-workspace:\(workspaceDragSession):"
            guard dragged.count == 1, let value = dragged.first,
                  value.hasPrefix(prefix) else { return false }
            let source = String(value.dropFirst(prefix.count))
            guard visibleWorkspaceIDs.contains(source) else { return false }
            model.layout.insertWorkspace(source, at: location.y > 29 ? i + 1 : i)
            dropTargetWorkspaceID = nil
            return true
        } isTargeted: { hovering in
            if hovering { dropTargetWorkspaceID = item.id }
            else if dropTargetWorkspaceID == item.id { dropTargetWorkspaceID = nil }
        }
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
        VStack(alignment: .leading, spacing: 18) {
            Text(model.current?.title ?? "Test your setup").font(.title2.bold())
            Text("Task \(model.index + 1) of \(model.tasks.count). The app or settings for this task has opened. This checklist is saved locally. Detected Karabiner permissions are checked automatically; you still test the physical shortcuts.").foregroundStyle(.secondary)
            ForEach(Array(model.steps.enumerated()), id: \.offset) { i, instruction in
                Toggle(isOn: Binding(get: { model.checkedSteps.contains(i) }, set: { enabled in
                    model.setGuideStep(i, enabled)
                })) {
                    Text("\(i + 1). \(instruction)").fixedSize(horizontal: false, vertical: true)
                }.toggleStyle(.checkbox).padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            Label(model.message, systemImage: model.checkReady ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(model.checkReady ? Color.primary : Color.orange)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Open app again") { if let task = model.current { do { try model.engine.openGuide(task) } catch { model.message = String(describing: error) } } }
                    Button("Check again") { model.checkAgain() }.disabled(model.busy)
                    if model.busy { ProgressView().controlSize(.small) }
                }
                HStack {
                    if model.current?.id == "karabiner-access" {
                        Button("Services & Driver Extensions") { model.openSettings() }
                        Button("Accessibility") { model.openPermissionPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
                        Button("Input Monitoring") { model.openPermissionPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") }
                    } else if let task = model.current, case let .guide(url, _, _) = task.action, url != nil {
                        Button(task.id == "raycast-access" ? "Keyboard Settings" : "Open permission settings") { model.openSettings() }
                    }
                }
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
            Text("Move the pointer to the bottom edge: the Dock should reveal after about one second. The macOS menu bar should hide when the pointer leaves the top. Its reveal timing is controlled by macOS. If it still stays visible, set Automatically hide and show the menu bar to Always in System Settings, then log out and back in.")
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

    @ViewBuilder private var footer: some View {
        HStack {
            switch model.page {
            case .features:
                Text("\(model.picker.selectedCount) selected tasks").foregroundStyle(.secondary)
                Spacer()
                Button("Continue") {
                    model.scope = .full
                    model.shortcutsConfirmed = false
                    if model.picker.selected.contains("aerospace-profile")
                        || model.picker.selected.contains("karabiner-profile")
                        || model.picker.selected.contains("raycast-profile") {
                        model.page = .shortcuts
                    } else { model.review() }
                }.disabled(model.busy || model.picker.selectedCount == 0).keyboardShortcut(.defaultAction)
            case .shortcuts:
                Button("Back") { model.page = .features }; Spacer()
                Button("Continue") {
                    if model.scope == .shortcuts { model.review() }
                    else if model.picker.selected.contains("aerospace-profile") { model.page = .workspaces }
                    else { model.review() }
                }.disabled(model.workspaceError(in: model.layout) != nil)
                    .keyboardShortcut(.defaultAction)
            case .workspaces:
                Button("Back") { model.page = model.scope == .full ? .shortcuts : .features }; Spacer()
                Button("Review changes") { model.review() }.keyboardShortcut(.defaultAction)
            case .review:
                Button("Back") { model.page = model.scope == .workspaces ? .workspaces : .shortcuts }; Spacer()
                Button("Start setup") { model.start() }.keyboardShortcut(.defaultAction)
            case .guide:
                Button("Leave pending & continue") { model.skip() }.disabled(model.busy); Spacer()
                Button("Test passed — continue") { model.completeGuide() }.disabled(model.busy || !model.checkReady || model.checkedSteps.count != model.steps.count).keyboardShortcut(.defaultAction)
            case .failed:
                Button("Review selection") { model.returnToFeatures() }
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
                    workspaceEditor: Bool = false, shortcutEditor: Bool = false) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if let icon = AppResources.iconURL, let image = NSImage(contentsOf: icon) { app.applicationIconImage = image }
        let model = try SetupModel(ids: ids, preset: preset)
        if workspaceEditor { model.openEditor(.workspaces) }
        if shortcutEditor { model.openEditor(.shortcuts) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 930, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Mac Setup"
        window.contentView = NSHostingView(rootView: SetupView(model: model))
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
