import AppKit
import SwiftUI
import MacSetupCore

private enum SetupPage: Hashable { case features, workspaces, review, running, guide, failed, finished }

private final class SetupModel: ObservableObject {
    @Published var page: SetupPage = .features
    @Published var picker = TaskPickerState(preset: .repair)
    @Published var states: [String: String] = [:]
    @Published var layout = WorkspaceConfiguration.defaultLayout
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
    private let worker = DispatchQueue(label: "mac-setup.native", qos: .userInitiated)
    private var setupLock: SetupLock?
    let runner = EmbeddedInstaller()
    let engine: Engine

    init(ids: [String]?, preset: SetupPreset?) throws {
        engine = try Engine(runner: runner)
        engine.deferRestarts = true
        layout = try WorkspaceConfiguration.load(from: engine.paths)
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

    func review() {
        do {
            try layout.validate()
            tasks = try Catalog.ordered(picker.orderedSelection, includingDependencies: false)
            message = ""
            page = .review
        } catch { message = String(describing: error) }
    }

    func start() {
        do {
            setupLock = try SetupLock(paths: engine.paths)
            try layout.save(to: engine.paths)
            engine.selectedWorkspaceTaskIDs = picker.selected
            index = 0; results = [:]
            advance()
        } catch { message = String(describing: error) }
    }

    func advance() {
        message = ""; details = ""; installerOutput = ""; response = ""
        checkedSteps = []; checkReady = false
        guard let task = current else {
            busy = true; page = .running
            worker.async { [self] in
                do {
                    try engine.finishRestarts()
                    DispatchQueue.main.async { self.busy = false; self.page = .finished; self.setupLock = nil }
                } catch {
                    DispatchQueue.main.async { self.busy = false; self.message = String(describing: error); self.page = .failed }
                }
            }
            return
        }
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
                // Guides are always revisited: previous yes/no answers are not a hardware test.
                if task.guided {
                    try engine.openGuide(task)
                    let check = try engine.checkGuide(task)
                    DispatchQueue.main.async {
                        self.busy = false; self.page = .guide
                        self.message = check.message; self.checkReady = check.ready
                    }
                    return
                }
                // A selected service task refreshes an existing bar after configuration changes.
                let state = try engine.state(task)
                let already = state == .done && task.id != "sketchybar-start"
                if !already { _ = try engine.apply(task) }
                DispatchQueue.main.async {
                    self.results[task.id] = already ? "Already configured" : "Complete"
                    self.busy = false; self.index += 1; self.advance()
                }
            } catch {
                DispatchQueue.main.async {
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
                DispatchQueue.main.async { self.message = check.message; self.checkReady = check.ready; self.busy = false }
            } catch {
                DispatchQueue.main.async { self.message = String(describing: error); self.checkReady = false; self.busy = false }
            }
        }
    }

    func completeGuide() {
        guard let task = current else { return }
        busy = true
        worker.async { [self] in
            do {
                if task.id != "tomito" { try engine.confirm(task) }
                else if try engine.state(task) != .done { throw SetupError("Tomito has not finished installing.") }
                DispatchQueue.main.async {
                    self.results[task.id] = "Complete"; self.busy = false; self.index += 1; self.advance()
                }
            } catch { DispatchQueue.main.async { self.message = String(describing: error); self.checkReady = false; self.busy = false } }
        }
    }

    func skip() {
        if let task = current { results[task.id] = "Pending"; index += 1 }
        advance()
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

    private var visibleWorkspaceIndices: [Int] {
        model.layout.workspaces.indices.filter { i in
            model.layout.workspaces[i].requiresTask.map(model.picker.selected.contains) ?? true
        }
    }

    private func moveWorkspace(_ i: Int, by direction: Int) {
        guard let position = visibleWorkspaceIndices.firstIndex(of: i) else { return }
        let destination = position + direction
        guard visibleWorkspaceIndices.indices.contains(destination) else { return }
        model.layout.workspaces.swapAt(i, visibleWorkspaceIndices[destination])
    }

    private var step: Int {
        switch model.page {
        case .features: return 1
        case .workspaces: return 2
        case .review: return 3
        default: return 4
        }
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
                Text("Step \(step) of 4").font(.headline)
            }.padding(24)
            HStack(spacing: 24) {
                ForEach(Array(["Choose features", "Workspaces", "Review", "Set up & test"].enumerated()), id: \.offset) { index, name in
                    Label(name, systemImage: index + 1 < step ? "checkmark.circle.fill" : "\(index + 1).circle")
                        .foregroundStyle(index + 1 == step ? Color.accentColor : Color.secondary)
                }
            }.padding(.horizontal, 24).padding(.bottom, 20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch model.page {
                    case .features: features
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
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose what to configure").font(.title2.bold())
            Text("Installed apps are kept. The next screens show your workspace layout and all selected changes. Permission approvals stay in the relevant app or System Settings.")
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

    private var workspaces: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your workspace bar").font(.title2.bold())
            Text("Use Option plus the key shown to switch. Option+Shift plus that key moves a window. Icons use the Nerd Font installed by setup.")
            HStack(spacing: 12) {
                ForEach(model.layout.forSelectedTasks(model.picker.selected).workspaces, id: \.id) { workspace in
                    Text(WorkspaceConfiguration.symbol(for: workspace.glyph) ?? workspace.name)
                        .font(.custom("Hack Nerd Font Mono", size: 22)).help(workspace.name)
                }
                Spacer(); Text(Date(), style: .time).font(.system(size: 17, weight: .bold, design: .monospaced))
            }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            ForEach(visibleWorkspaceIndices, id: \.self) { i in
                HStack {
                    Text("⌥ \(keyName(WorkspaceConfiguration.keys[visibleWorkspaceIndices.firstIndex(of: i)!]))").font(.system(.body, design: .monospaced)).frame(width: 60, alignment: .leading)
                    TextField("Name", text: $model.layout.workspaces[i].name).frame(width: 130)
                    Picker("Icon", selection: $model.layout.workspaces[i].glyph) {
                        ForEach(WorkspaceGlyph.all, id: \.name) { glyph in Text(glyph.name.capitalized).tag(glyph.name) }
                    }.frame(width: 150)
                    Button("Apps (\(model.layout.workspaces[i].apps.count))") { model.selectedWorkspace = i; model.appSheet = true }
                    Spacer()
                    Button { moveWorkspace(i, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(i == visibleWorkspaceIndices.first).help("Move workspace earlier")
                    Button { moveWorkspace(i, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(i == visibleWorkspaceIndices.last).help("Move workspace later")
                    Button { model.layout.workspaces.remove(at: i) } label: { Image(systemName: "minus.circle") }.disabled(model.layout.workspaces.count == 1).help("Remove workspace")
                }
            }
            Button("Add workspace") {
                var number = 1
                while model.layout.workspaces.contains(where: { $0.id == "custom\(number)" }) { number += 1 }
                model.layout.workspaces.append(.init(id: "custom\(number)", name: "Workspace \(number)", glyph: "star"))
            }.disabled(model.layout.workspaces.count >= WorkspaceConfiguration.keys.count)
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.red) }
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
            Text("Automatic tasks run together after you start. Setup pauses for each permission or visible test. Existing files and preferences are backed up before changes. Finder, Dock and menu bar refresh once at the end.")
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
            if model.acceptsInput {
                Text("The installer is running here. If it requests an administrator password or a response, enter it below and press Send. The secure field forwards it directly to the local installer.")
                ScrollView { Text(model.installerOutput).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 240)
                HStack { SecureField("Installer password or response", text: $model.response).onSubmit { model.sendInput() }; Button("Send") { model.sendInput() } }
            } else { ProgressView().controlSize(.large) }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.current?.title ?? "Test your setup").font(.title2.bold())
            Text("Task \(model.index + 1) of \(model.tasks.count). The app or settings for this task has opened. Follow these choices, then return here.").foregroundStyle(.secondary)
            ForEach(Array(model.steps.enumerated()), id: \.offset) { i, instruction in
                Toggle(isOn: Binding(get: { model.checkedSteps.contains(i) }, set: { enabled in
                    if enabled { model.checkedSteps.insert(i) } else { model.checkedSteps.remove(i) }
                })) {
                    Text("\(i + 1). \(instruction)").fixedSize(horizontal: false, vertical: true)
                }.toggleStyle(.checkbox).padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            Label(model.message, systemImage: model.checkReady ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(model.checkReady ? Color.primary : Color.orange)
            HStack {
                Button("Open app again") { if let task = model.current { do { try model.engine.openGuide(task) } catch { model.message = String(describing: error) } } }
                if let task = model.current, case let .guide(url, _, _) = task.action, url != nil { Button("Open permission settings") { model.openSettings() } }
                Button("Check again") { model.checkAgain() }.disabled(model.busy)
                if model.busy { ProgressView().controlSize(.small) }
            }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(model.current?.title ?? "Refresh needs attention", systemImage: "exclamationmark.triangle").font(.title2.bold())
            Text(model.message)
            Text(model.details).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
            if !model.installerOutput.isEmpty {
                DisclosureGroup("Installer details") { Text(model.installerOutput).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
            }
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.results.values.contains("Pending") ? "Setup saved; some tasks still need attention" : "Setup complete — check your desktop").font(.title2.bold())
            Text("Move the pointer to the bottom edge: the Dock should reveal after about one second. The macOS menu bar should hide when the pointer leaves the top. Its reveal timing is controlled by macOS. If it still stays visible, set Automatically hide and show the menu bar to Always in System Settings, then log out and back in.")
            Text("Press Option+1 and check the workspace highlight. Press Command+Tab to a window in another workspace and verify that the workspace follows. Check that glyphs and numbers are readable beside the clock.")
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
                Button("Continue") { model.page = model.picker.selected.contains("aerospace-profile") ? .workspaces : .review; if model.page == .review { model.review() } }.disabled(model.busy || model.picker.selectedCount == 0).keyboardShortcut(.defaultAction)
            case .workspaces:
                Button("Back") { model.page = .features }; Spacer()
                Button("Review changes") { model.review() }.keyboardShortcut(.defaultAction)
            case .review:
                Button("Back") { model.page = .features }; Spacer()
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
                Spacer(); Button("Close") { NSApplication.shared.terminate(nil) }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func keyName(_ key: String) -> String {
        switch key { case "backtick": return "`"; case "minus": return "−"; case "equal": return "="; default: return key }
    }
}

enum NativeSetup {
    static func run(ids: [String]? = nil, preset: SetupPreset? = nil, workspaceEditor: Bool = false) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let model = try SetupModel(ids: ids, preset: preset)
        if workspaceEditor { model.page = .workspaces }
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
