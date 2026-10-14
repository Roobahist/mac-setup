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
    @LocalViewState private var expandedFeatureCategories = Set<String>()

    init(model: SetupModel, initialDestination: ControlDestination = .home,
         startGuided: Bool = false, hasPreparedSelection: Bool = false) {
        self.model = model
        self.hasPreparedSelection = hasPreparedSelection
        let initial: ControlDestination = startGuided ? .apps : initialDestination
        _destination = LocalViewState(initialValue: initial)
        _previousDestination = LocalViewState(initialValue: initial)
        _guidedStep = LocalViewState(initialValue: startGuided ? 0 : nil)
    }

    // Navigation order matches the guided walkthrough exactly after Overview.
    private let customization: [ControlDestination] = [
        .home, .apps, .shortcuts, .workspaces, .appearance, .dock, .menuBar, .finder
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
                        hasUnappliedEdits: (GuidedTourStep.steps[index].destination == .workspaces
                            && model.workspaceHasDraftChanges)
                            || (GuidedTourStep.steps[index].destination == .shortcuts
                                && model.shortcutsHaveDraftChanges),
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

    // Expanded and collapsed sidebar use identical rows, icon sizes, and
    // leading offsets. Collapsing only removes their titles.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Button {
                    compactSidebar.toggle()
                    if compactSidebar { query = "" }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 44, height: 42)
                }
                .buttonStyle(.plain)
                .help(compactSidebar ? "Expand sidebar" : "Collapse sidebar")
                .accessibilityLabel(compactSidebar ? "Expand sidebar" : "Collapse sidebar")

                if !compactSidebar {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac Setup").font(.headline)
                        Text("Your Mac, your way")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 5)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.top, 12)
            .padding(.bottom, 14)

            Group {
                if compactSidebar {
                    Button { compactSidebar = false } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 34)
                    }
                    .buttonStyle(.plain)
                    .help("Expand sidebar to search settings")
                    .accessibilityLabel("Expand sidebar to search settings")
                } else {
                    TextField("Search settings", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 34)
                        .accessibilityLabel("Search settings and features")
                }
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    sidebarSectionTitle("Customize")
                    ForEach(customization) { item in sidebarItem(item) }
                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                    sidebarSectionTitle("Mac Setup")
                    Button(action: beginGuided) {
                        sidebarRowContent("Guided Setup", symbol: "checklist",
                            selected: guidedStep != nil)
                    }
                    .buttonStyle(.plain)
                    .help("Walk through the existing customization sections")
                    .accessibilityLabel("Guided Setup")
                    sidebarItem(.updates)
                }
                .padding(.top, 4)
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .frame(width: 44)
                    .help("Version \(MacSetupVersion.installed)")
                if !compactSidebar {
                    Text("Version \(MacSetupVersion.installed)")
                }
                Spacer(minLength: 0)
                if !compactSidebar {
                    Circle().fill(model.busy ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(model.busy ? "Checking settings" : "Ready")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 13)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func sidebarSectionTitle(_ title: String) -> some View {
        if !compactSidebar {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 25)
                .padding(.top, 9)
                .padding(.bottom, 5)
        }
    }

    private func sidebarRowContent(_ title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 44, height: 42)
            if !compactSidebar {
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .frame(height: 43)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 13)
    }

    private func sidebarItem(_ item: ControlDestination) -> some View {
        Button { selectDestination(item) } label: {
            sidebarRowContent(item.title, symbol: item.symbol, selected: destination == item)
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
                        .font(SetupDesign.pageTitle)
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
            .padding(SetupDesign.pagePadding)
            .frame(maxWidth: SetupDesign.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func scrollSettings(_ title: String, category: String, includeAccent: Bool = false) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(SetupDesign.pageTitle)
                Text("Changes are applied individually and saved to the recovery journal.")
                    .foregroundStyle(.secondary).font(.callout)
                if includeAccent { DesktopAccentControls(engine: model.engine) }
                ForEach(TweakRegistry.filtered("", category: category)) { tweak in
                    TweakControl(tweak: tweak,
                        service: TweakService(journal: model.engine.journal,
                                              runner: model.engine.runner, paths: model.engine.paths))
                }
            }.padding(SetupDesign.pagePadding).frame(maxWidth: SetupDesign.pageWidth, alignment: .leading)
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
                Text("Search results").font(SetupDesign.pageTitle)
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
            }.padding(SetupDesign.pagePadding).frame(maxWidth: SetupDesign.pageWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }

    private var appFeatures: some View {
        Group {
            if activeFeature != nil {
                SetupView(model: model, embedded: true, onReturn: resetFeature)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Apps & Features").font(SetupDesign.pageTitle)
                        Text("Choose a ready-made setup or select entire categories. You don't need to open each feature individually.")
                            .font(.callout).foregroundStyle(.secondary)
                        featureBatchControls
                        TextField("Find a feature", text: $model.search)
                            .textFieldStyle(.roundedBorder)
                        ForEach(model.picker.categories.dropFirst(), id: \.self) { category in
                            featureCategory(category)
                        }
                        Text("Nothing is installed by selecting a checkbox. Review the selected tasks and confirm before anything runs. Dependencies are included automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(SetupDesign.pagePadding)
                    .frame(maxWidth: SetupDesign.pageWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var featureBatchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(SetupPreset.allCases, id: \.self) { preset in
                        Button(preset.title) { model.picker.choose(preset) }
                    }
                    Divider()
                    Button("Select all (including optional)") { model.picker.selectAll() }
                    Button("Clear selection") { model.picker.clearSelection() }
                } label: {
                    Label("Choose a setup", systemImage: "square.stack.3d.up")
                }
                .disabled(model.busy)
                Spacer()
                Text("\(model.picker.selectedCount) of \(Catalog.tasks.count) selected")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let preset = model.picker.preset {
                Text("\(preset.title): \(preset.summary)")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Custom selection. Required dependencies are added automatically.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Review & apply selected features") { reviewSelectedFeatures() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.picker.selectedCount == 0)
                Text("Review first. No automatic installation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.message.isEmpty {
                Text(model.message).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func featureCategory(_ category: String) -> some View {
        let tasks = Catalog.tasks.filter { $0.category == category }
        let selectedCount = tasks.filter { model.picker.selected.contains($0.id) }.count
        let expanded = expandedFeatureCategories.contains(category)
            || !model.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if expandedFeatureCategories.contains(category) {
                        expandedFeatureCategories.remove(category)
                    } else {
                        expandedFeatureCategories.insert(category)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .frame(width: 16)
                        Text(category).font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text("\(selectedCount)/\(tasks.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button(selectedCount == tasks.count ? "Clear group" : "Select group") {
                    model.picker.selectCategory(category, enabled: selectedCount != tasks.count)
                }
                .disabled(model.busy)
                .buttonStyle(.borderless)
            }
            .padding(15)
            if expanded {
                Divider()
                ForEach(tasks.filter {
                    model.search.isEmpty || [$0.title, $0.summary, $0.id]
                        .contains { $0.localizedCaseInsensitiveContains(model.search) }
                }, id: \.id) { task in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { model.picker.selected.contains(task.id) },
                            set: { _ in model.picker.toggle(task.id) })) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title).fontWeight(.medium)
                                Text(task.summary)
                                    .font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(model.states[task.id] ?? "Checking...")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(model.busy)
                        Spacer(minLength: 8)
                        Text(task.guided ? "Approval" : "Automatic")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
    }

    private func reviewSelectedFeatures() {
        guard model.picker.selectedCount > 0 else { return }
        model.scope = .full
        model.review()
        if model.page == .review { activeFeature = "batch-selection" }
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
