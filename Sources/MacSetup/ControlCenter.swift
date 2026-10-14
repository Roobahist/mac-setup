import AppKit
import SwiftUI
import MacSetupCore

enum ControlDestination: String, CaseIterable, Identifiable {
    case home, apps, workspaces, shortcuts, appearance, dock, menuBar, finder, updates, guidedSetup

    var id: Self { self }
    var title: String {
        switch self {
        case .home: return "Overview"
        case .apps: return "Apps & Features"
        case .workspaces: return "Workspaces"
        case .shortcuts: return "Keyboard Shortcuts"
        case .appearance: return "Appearance"
        case .dock: return "Dock"
        case .menuBar: return "Menu Bar & Clock"
        case .finder: return "Finder"
        case .updates: return "Updates"
        case .guidedSetup: return "Guided Setup"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .apps: return "square.stack.3d.up"
        case .workspaces: return "rectangle.3.group"
        case .shortcuts: return "keyboard"
        case .appearance: return "paintpalette"
        case .dock: return "dock.rectangle"
        case .menuBar: return "menubar.rectangle"
        case .finder: return "folder"
        case .updates: return "arrow.triangle.2.circlepath"
        case .guidedSetup: return "checklist"
        }
    }
}

struct ControlCenterView: View {
    @ObservedObject var model: SetupModel
    let hasPreparedSelection: Bool
    @LocalViewState private var destination: ControlDestination? = .home
    @LocalViewState private var previousDestination: ControlDestination = .home
    @LocalViewState private var query = ""
    @LocalViewState private var activeFeature: String?
    @LocalViewState private var compactSidebar = false
    @LocalViewState private var guidedStep: Int?

    init(model: SetupModel, initialDestination: ControlDestination = .home,
         startGuided: Bool = false, hasPreparedSelection: Bool = false) {
        self.model = model
        self.hasPreparedSelection = hasPreparedSelection
        let initial: ControlDestination = startGuided ? .apps : initialDestination
        _destination = LocalViewState(initialValue: initial)
        _previousDestination = LocalViewState(initialValue: initial)
        _guidedStep = LocalViewState(initialValue: startGuided ? 0 : nil)
    }

    private let customization: [ControlDestination] = [
        .home, .appearance, .dock, .menuBar, .finder, .workspaces, .shortcuts, .apps
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: compactSidebar ? 70 : 248)
                // Retain the original native, translucent sidebar styling.
                .background(.regularMaterial)
            Divider()
            VStack(spacing: 0) {
                if let index = guidedStep,
                   GuidedTourStep.steps.indices.contains(index) {
                    GuidedTourBanner(
                        step: GuidedTourStep.steps[index],
                        index: index,
                        total: GuidedTourStep.steps.count,
                        canGoBack: index > 0,
                        canAdvance: model.page != .running && model.page != .guide,
                        onBack: { showGuidedStep(index - 1) },
                        onSkip: { showGuidedStep(index + 1) },
                        onNext: { showGuidedStep(index + 1) },
                        onExit: endGuided
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 8)
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1040, minHeight: 740)
        .onChange(of: destination) { next in
            // A running installer owns its editor until its operation completes.
            if model.page == .running || model.page == .guide {
                destination = previousDestination
                return
            }
            previousDestination = next ?? .home
            query = ""
            activeFeature = nil
            if let index = guidedStep,
               GuidedTourStep.steps.indices.contains(index),
               next != GuidedTourStep.steps[index].destination {
                // Clicking a normal sidebar item leaves the guided walkthrough.
                guidedStep = nil
            }
            switch next {
            case .workspaces: model.openEditor(.workspaces)
            case .shortcuts: model.openEditor(.shortcuts)
            default: break
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults
        } else {
            switch destination ?? .home {
            case .home: overview
            case .apps: appFeatures
            case .workspaces, .shortcuts:
                SetupView(model: model, embedded: true, onReturn: resetFeature)
            case .appearance:
                scrollSettings("Appearance", category: "Appearance", includeAccent: true)
            case .dock: scrollSettings("Dock", category: "Dock")
            case .menuBar: scrollSettings("Menu Bar & Clock", category: "Menu Bar")
            case .finder: scrollSettings("Finder", category: "Finder")
            case .updates: UpdateCenter()
            case .guidedSetup: overview // This destination starts a tour, not another editor.
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    compactSidebar.toggle()
                    if compactSidebar { query = "" }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(compactSidebar ? "Expand sidebar" : "Collapse sidebar")
                .accessibilityLabel(compactSidebar ? "Expand sidebar" : "Collapse sidebar")

                if !compactSidebar {
                    HStack(spacing: 9) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mac Setup").font(.headline)
                            Text("Your Mac, your way")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 19)
            .padding(.bottom, 12)

            if compactSidebar {
                Button {
                    compactSidebar = false
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17))
                        .frame(width: 38, height: 34)
                }
                .buttonStyle(.plain)
                .help("Expand sidebar to search settings")
                .padding(.horizontal, 15)
            } else {
                TextField("Search settings", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .accessibilityLabel("Search settings and features")
            }

            if compactSidebar {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(customization) { item in compactRow(item) }
                        Divider().padding(.vertical, 8)
                        Button(action: beginGuided) {
                            Image(systemName: "checklist")
                                .font(.system(size: 19))
                                .frame(width: 44, height: 43)
                                .background(guidedStep != nil ? Color.accentColor.opacity(0.14) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(guidedStep != nil ? Color.accentColor : Color.primary)
                        .help("Guided Setup")
                        .accessibilityLabel("Guided Setup")
                        compactRow(.updates)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
            } else {
                // Keep the original native sidebar lists and selection behavior.
                List(selection: $destination) {
                    Section("Customize") {
                        ForEach(customization) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    Section("Mac Setup") {
                        Button(action: beginGuided) {
                            Label("Guided Setup", systemImage: "checklist")
                                .foregroundStyle(guidedStep != nil ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .help("Walk through the existing customization sections")
                        Label(ControlDestination.updates.title,
                              systemImage: ControlDestination.updates.symbol)
                            .tag(ControlDestination.updates)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            HStack(spacing: 8) {
                if compactSidebar {
                    Image(systemName: "info.circle")
                        .help("Version \(MacSetupVersion.installed)")
                } else {
                    Text("Version \(MacSetupVersion.installed)")
                }
                Spacer(minLength: 0)
                Circle().fill(model.busy ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(model.busy ? "Checking or applying settings" : "Ready")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func compactRow(_ item: ControlDestination) -> some View {
        Button { selectDestination(item) } label: {
            Image(systemName: item.symbol)
                .font(.system(size: 19))
                .frame(width: 44, height: 43)
                .background(destination == item ? Color.accentColor.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(destination == item ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
    }

    private func selectDestination(_ item: ControlDestination) {
        if item == .guidedSetup {
            beginGuided()
        } else {
            guidedStep = nil
            destination = item
        }
    }

    private func beginGuided() {
        guard model.page != .running && model.page != .guide else { return }
        query = ""
        activeFeature = nil
        guidedStep = 0
        destination = GuidedTourStep.steps[0].destination
        // If this section is already visible, onChange will not run.
        model.scope = .full
        model.page = .features
        model.refreshInventory()
    }

    private func endGuided() {
        guidedStep = nil
    }

    private func showGuidedStep(_ index: Int) {
        guard model.page != .running && model.page != .guide else { return }
        guard GuidedTourStep.steps.indices.contains(index) else {
            endGuided()
            return
        }
        let next = GuidedTourStep.steps[index].destination
        guidedStep = index
        query = ""
        activeFeature = nil
        // Trigger the existing editor when navigating to its current destination.
        if destination == next {
            if next == .shortcuts { model.openEditor(.shortcuts) }
            else if next == .workspaces { model.openEditor(.workspaces) }
        }
        destination = next
    }

    private func jump(_ item: ControlDestination) {
        selectDestination(item)
    }

    private var overview: some View {
        let configured = Catalog.tasks.filter { model.states[$0.id] == TaskState.done.rawValue }.count
        let total = Catalog.tasks.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mac Setup at a glance")
                        .font(.system(size: 29, weight: .semibold))
                    Text("Your customization dashboard. Choose a setting from the sidebar, review what is installed, or run the guided setup on a new Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Setup status", systemImage: "checkmark.circle")
                            .font(.headline)
                        Text("\(configured) of \(total) setup components verified")
                            .font(.title3.weight(.medium))
                        Text("Detected from this Mac. Unconfigured tasks are not errors.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("Review components") { jump(.apps) }
                                .buttonStyle(.borderedProminent)
                            Button("Refresh status") { model.refreshInventory() }
                                .disabled(model.busy)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 9) {
                        Label("New to Mac Setup?", systemImage: "wand.and.stars")
                            .font(.headline)
                        Text("Use Guided Setup once to choose apps, shortcuts, and workspaces. You can change each area independently afterward.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Open guided setup") { jump(.guidedSetup) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("How changes work").font(.title3.weight(.semibold))
                    Label("Each setting is saved separately, with Undo and a system-default reset.", systemImage: "slider.horizontal.3")
                    Label("An unsuccessful refresh is reported instead of claiming macOS applied a change.", systemImage: "exclamationmark.circle")
                    Label("Optional services stay off until you explicitly enable them.", systemImage: "power")
                    Label("Changes to this app are delivered through versioned GitHub releases.", systemImage: "arrow.triangle.2.circlepath")
                    Button("Check for updates") { jump(.updates) }
                        .padding(.top, 4)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(28)
            .frame(maxWidth: 950, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func scrollSettings(_ title: String, category: String, includeAccent: Bool = false) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.system(size: 27, weight: .semibold))
                Text("Changes are applied individually and saved to the recovery journal.")
                    .foregroundStyle(.secondary).font(.callout)
                if includeAccent { DesktopAccentControls(engine: model.engine) }
                ForEach(TweakRegistry.filtered("", category: category)) { tweak in
                    TweakControl(tweak: tweak,
                        service: TweakService(journal: model.engine.journal,
                                              runner: model.engine.runner, paths: model.engine.paths))
                }
            }.padding(28).frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var searchResults: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = TweakRegistry.filtered(needle)
        let tasks = Catalog.tasks.filter {
            [$0.title, $0.summary, $0.category, $0.id]
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Search results").font(.system(size: 27, weight: .semibold))
                Text("\(matches.count) settings and \(tasks.count) features for “\(needle)”")
                    .foregroundStyle(.secondary)
                ForEach(matches) { tweak in
                    TweakControl(tweak: tweak,
                        service: TweakService(journal: model.engine.journal,
                                              runner: model.engine.runner, paths: model.engine.paths))
                }
                ForEach(tasks, id: \.id) { task in
                    Button {
                        query = ""
                        destination = .apps
                        DispatchQueue.main.async { openFeature(task) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(task.title).font(.headline)
                                Text(task.category).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                if matches.isEmpty && tasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.title2)
                        Text("No matching controls").font(.headline)
                        Text("Try Dock, clock, accent, or workspaces.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(40)
                }
            }.padding(28).frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }

    private var appFeatures: some View {
        Group {
            if activeFeature != nil {
                SetupView(model: model, embedded: true, onReturn: resetFeature)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Apps & Features").font(.system(size: 27, weight: .semibold))
                        Text("Set up only what you need. Installed components are detected without rerunning setup.")
                            .font(.callout).foregroundStyle(.secondary)
                        if hasPreparedSelection {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Prepared setup selection", systemImage: "list.bullet.clipboard")
                                    .font(.headline)
                                Text("\(model.picker.selectedCount) tasks were selected by the command that opened Mac Setup. Review them here before applying anything.")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button("Review selected setup") {
                                    model.scope = .full
                                    model.review()
                                    if model.page == .review { activeFeature = "prepared-setup" }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.busy || model.picker.selectedCount == 0)
                                if !model.message.isEmpty {
                                    Text(model.message).font(.caption).foregroundStyle(.orange)
                                }
                            }
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        ForEach(Array(Set(Catalog.tasks.map(\.category))).sorted(), id: \.self) { category in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(category).font(.headline)
                                ForEach(Catalog.tasks.filter { $0.category == category }, id: \.id) { task in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: model.states[task.id] == TaskState.done.rawValue
                                              ? "checkmark.circle" : "square.stack.3d.up")
                                            .foregroundStyle(.secondary).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(task.title).fontWeight(.medium)
                                            Text(task.summary).font(.caption).foregroundStyle(.secondary)
                                            Text(model.states[task.id] ?? "Checking...")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 10)
                                        Button("Configure") { openFeature(task) }
                                            .disabled(model.busy)
                                    }
                                    .padding(14)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        Text("App removal is not automatic. Mac Setup only offers reversible preference and profile changes where it can verify them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(28).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func openFeature(_ task: SetupTask) {
        do {
            model.tasks = try Catalog.ordered([task.id], includingDependencies: true)
            model.scope = .feature
            model.page = .review
            activeFeature = task.id
        } catch {
            model.message = String(describing: error)
        }
    }

    private func resetFeature() {
        activeFeature = nil
        model.scope = .full
        model.page = .features
        model.refreshInventory()
    }
}
