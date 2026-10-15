import AppKit
import SwiftUI
import MacSetupCore

enum ControlDestination: String, CaseIterable, Identifiable {
    case home, apps, workspaces, workspaceBar, shortcuts, appearance, dock, menuBar, finder, updates, guidedSetup

    var id: Self { self }
    var title: String {
        switch self {
        case .home: return "Overview"
        case .apps: return "Apps & features"
        case .workspaces: return "Workspaces"
        case .workspaceBar: return "Workspace bar"
        case .shortcuts: return "Keyboard shortcuts"
        case .appearance: return "Appearance"
        case .dock: return "Dock"
        case .menuBar: return "Menu bar & clock"
        case .finder: return "Finder"
        case .updates: return "Updates"
        case .guidedSetup: return "Guided setup"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .apps: return "square.stack.3d.up"
        case .workspaces: return "rectangle.3.group"
        case .workspaceBar: return "menubar.rectangle"
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
    @LocalViewState private var hoveredDestination: ControlDestination?
    @LocalViewState private var compactSidebar = false
    @FocusState private var navigationFocus: ControlDestination?
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
        .home, .apps, .shortcuts, .workspaces, .workspaceBar, .appearance, .dock, .menuBar, .finder
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: compactSidebar ? SetupDesign.sidebarRail : SetupDesign.sidebarWidth)
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
                            || (GuidedTourStep.steps[index].destination == .workspaceBar
                                && model.barHasDraftChanges)
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
        .font(SetupDesign.body)
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
            case .workspaceBar: model.openEditor(.workspaceBar)
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
            case .workspaces, .workspaceBar, .shortcuts:
                SetupView(model: model, embedded: true, onReturn: resetFeature)
            case .appearance:
                scrollSettings("Appearance", category: "Appearance")
            case .dock: scrollSettings("Dock", category: "Dock")
            case .menuBar: scrollSettings("Menu bar & clock", category: "Menu Bar")
            case .finder: scrollSettings("Finder", category: "Finder")
            case .updates: UpdateCenter()
            case .guidedSetup: overview // This destination starts a tour, not another editor.
            }
        }
    }

    // One set of buttons in both modes. The icon rail never changes position;
    // the actual row width, including its selection background, does change.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Button {
                    compactSidebar.toggle()
                    if compactSidebar { query = "" }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: SetupDesign.sidebarIconColumn, height: SetupDesign.sidebarRowHeight)
                }
                .buttonStyle(.plain)
                .help(compactSidebar ? "Expand sidebar" : "Collapse sidebar")
                .accessibilityLabel(compactSidebar ? "Expand sidebar" : "Collapse sidebar")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Setup").font(SetupDesign.sectionTitle)
                    Text("Your Mac, your way").font(SetupDesign.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(width: compactSidebar ? 0 : nil, alignment: .leading)
                .opacity(compactSidebar ? 0 : 1).clipped().accessibilityHidden(compactSidebar)
            }
            .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 8)

            HStack(spacing: 0) {
                Button { compactSidebar = false } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 17))
                        .frame(width: SetupDesign.sidebarIconColumn, height: SetupDesign.sidebarRowHeight)
                }
                .buttonStyle(.plain).accessibilityLabel("Search settings")
                TextField("Search settings", text: $query)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(width: compactSidebar ? 0 : nil)
                    .opacity(compactSidebar ? 0 : 1).clipped()
                    .accessibilityHidden(compactSidebar)
            }
            .background(Color.primary.opacity(compactSidebar ? 0 : 0.04), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sidebarSection("Customize")
                    ForEach(customization) { item in sidebarNavigationRow(item) }
                    sidebarSection("Mac Setup").padding(.top, 12)
                    sidebarNavigationRow(.guidedSetup)
                    sidebarNavigationRow(.updates)
                }
                .padding(.horizontal, 8)
            }

            HStack(spacing: 0) {
                Circle().fill(model.busy ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                    .frame(width: SetupDesign.sidebarIconColumn, height: 24)
                    .accessibilityLabel(model.busy ? "Checking or applying settings" : "Ready")
                Text("Version \(MacSetupVersion.installed)").lineLimit(1)
                    .font(SetupDesign.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: compactSidebar ? 0 : nil, alignment: .leading)
                    .opacity(compactSidebar ? 0 : 1).clipped().accessibilityHidden(compactSidebar)
            }.padding(.horizontal, 8).padding(.bottom, 12)
        }
        .font(SetupDesign.body)
    }

    private func sidebarSection(_ title: String) -> some View {
        Text(title).font(SetupDesign.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(height: 20).padding(.leading, 12)
            .opacity(compactSidebar ? 0 : 1).accessibilityHidden(compactSidebar)
    }

    private func sidebarNavigationRow(_ item: ControlDestination) -> some View {
        let selected = item == .guidedSetup ? guidedStep != nil : destination == item && guidedStep == nil
        return Button { selectDestination(item) } label: {
            HStack(spacing: 0) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: SetupDesign.sidebarIconColumn, height: SetupDesign.sidebarRowHeight)
                    .accessibilityHidden(true)
                Text(item.title).fontWeight(selected ? .semibold : .regular).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: compactSidebar ? 0 : nil, alignment: .leading)
                    .opacity(compactSidebar ? 0 : 1).clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.primary)
            .background(selected ? Color.accentColor.opacity(0.15)
                        : hoveredDestination == item ? Color.primary.opacity(0.06) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredDestination = item }
            else if hoveredDestination == item { hoveredDestination = nil }
        }
        .help(item.title).accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .focused($navigationFocus, equals: item)
        .disabled(model.page == .running || model.page == .guide)
        .onMoveCommand { direction in
            let items = customization + [.guidedSetup, .updates]
            guard let index = items.firstIndex(of: item), direction == .up || direction == .down else { return }
            let next = index + (direction == .up ? -1 : 1)
            guard items.indices.contains(next) else { return }
            navigationFocus = items[next]
            selectDestination(items[next])
        }
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
            else if next == .workspaceBar { model.openEditor(.workspaceBar) }
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
            VStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
                SetupPageHeader("Mac Setup at a glance", subtitle: "Review your setup, customize each part of your Mac, or follow Guided Setup on a new machine.")
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Setup status", systemImage: "checkmark.circle")
                            .font(SetupDesign.sectionTitle)
                        Text("\(configured) of \(total) setup components verified")
                            .font(.title3.weight(.medium))
                        Text("Detected from this Mac. Unconfigured tasks are not errors.")
                            .font(SetupDesign.body).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("Review components") { jump(.apps) }
                                .buttonStyle(.borderedProminent)
                            Button("Refresh status") { model.refreshInventory() }
                                .disabled(model.busy)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .setupCard()
                    VStack(alignment: .leading, spacing: 9) {
                        Label("New to Mac Setup?", systemImage: "wand.and.stars")
                            .font(SetupDesign.sectionTitle)
                        Text("Use Guided Setup once to choose apps, shortcuts, and workspaces. You can change each area independently afterward.")
                            .font(SetupDesign.body).foregroundStyle(.secondary)
                        Button("Open guided setup") { jump(.guidedSetup) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .setupCard()
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
                .font(SetupDesign.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .setupCard()
            }
            .padding(SetupDesign.pagePadding)
            .frame(maxWidth: SetupDesign.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func scrollSettings(_ title: String, category: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
                SetupPageHeader(title, subtitle: "Changes are applied individually and saved to the recovery journal.")
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
            VStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
                SetupPageHeader("Search results", subtitle: "\(matches.count) settings and \(tasks.count) features for “\(needle)”")
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
                                Text(task.title).font(SetupDesign.sectionTitle)
                                Text(task.category).font(SetupDesign.body).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                if matches.isEmpty && tasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.title2)
                        Text("No matching controls").font(SetupDesign.sectionTitle)
                        Text("Try Dock, clock, accent, or workspaces.")
                            .font(SetupDesign.body).foregroundStyle(.secondary)
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
                    VStack(alignment: .leading, spacing: SetupDesign.pageSpacing) {
                        SetupPageHeader("Apps & features", subtitle: "Choose a ready-made setup or select individual components. Review your selection before applying changes.")
                        featureBatchControls
                        TextField("Find a feature", text: $model.search)
                            .textFieldStyle(.roundedBorder)
                        ForEach(model.picker.categories.dropFirst(), id: \.self) { category in
                            featureCategory(category)
                        }
                        Text("Nothing is installed by selecting a checkbox. Review the selected tasks and confirm before anything runs. Dependencies are included automatically.")
                            .font(SetupDesign.caption).foregroundStyle(.secondary)
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
                    .font(SetupDesign.body).foregroundStyle(.secondary)
            } else {
                Text("Custom selection. Required dependencies are added automatically.")
                    .font(SetupDesign.body).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Review & apply selected features") { reviewSelectedFeatures() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.picker.selectedCount == 0)
                Text("Review first. No automatic installation.")
                    .font(SetupDesign.caption).foregroundStyle(.secondary)
            }
            if !model.message.isEmpty {
                Text(model.message).font(SetupDesign.caption).foregroundStyle(.orange)
            }
        }
        .setupCard()
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
                        Text(category).font(SetupDesign.sectionTitle)
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
                                    .font(SetupDesign.body).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(model.states[task.id] ?? "Checking...")
                                    .font(SetupDesign.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(model.busy)
                        Spacer(minLength: 8)
                        Text(task.guided ? "Approval" : "Automatic")
                            .font(SetupDesign.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SetupDesign.cardRadius))
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
