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
    @LocalViewState private var destination: ControlDestination? = .home
    @LocalViewState private var previousDestination: ControlDestination = .home
    @LocalViewState private var query = ""
    @LocalViewState private var activeFeature: String?
    @LocalViewState private var compactSidebar = false

    init(model: SetupModel, initialDestination: ControlDestination = .home) {
        self.model = model
        _destination = LocalViewState(initialValue: initialDestination)
        _previousDestination = LocalViewState(initialValue: initialDestination)
    }

    private let customization: [ControlDestination] = [
        .home, .appearance, .dock, .menuBar, .finder, .workspaces, .shortcuts, .apps
    ]
    private let management: [ControlDestination] = [.guidedSetup, .updates]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: compactSidebar ? 70 : 248)
                .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            Group {
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
                    case .guidedSetup: SetupView(model: model)
                    }
                }
            }
            // Do not let content scroll under the opaque macOS title bar.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            switch next {
            case .workspaces: model.openEditor(.workspaces)
            case .shortcuts: model.openEditor(.shortcuts)
            case .guidedSetup:
                model.scope = .full
                model.page = .features
            default: break
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mac Setup").font(.headline)
                        Text("Customize your Mac").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)

            if compactSidebar {
                Button { compactSidebar = false } label: {
                    Image(systemName: "magnifyingglass").frame(width: 36, height: 32)
                }
                .buttonStyle(.plain)
                .help("Expand to search settings")
                .padding(.horizontal, 16)
            } else {
                TextField("Search settings", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search settings and features")
                    .padding(.horizontal, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if !compactSidebar {
                        Text("CUSTOMIZE")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 16).padding(.top, 4)
                    }
                    ForEach(customization) { item in sidebarRow(item) }
                    Divider().padding(.vertical, 7)
                    if !compactSidebar {
                        Text("MAC SETUP")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    ForEach(management) { item in sidebarRow(item) }
                }
                .padding(.horizontal, 9)
            }
            Spacer(minLength: 0)
            HStack {
                if !compactSidebar { Text("Version \\(MacSetupVersion.installed)") }
                else { Image(systemName: "info.circle").help("Version \\(MacSetupVersion.installed)") }
                Spacer(minLength: 2)
                Circle().fill(model.busy ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(model.busy ? "Checking settings" : "Ready")
            }
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    private func sidebarRow(_ item: ControlDestination) -> some View {
        Button { jump(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 30, height: 30)
                if !compactSidebar {
                    Text(item.title)
                        .font(.system(size: 13, weight: destination == item ? .semibold : .regular))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compactSidebar ? 9 : 12)
            .frame(height: 39)
            .foregroundStyle(destination == item ? Color.accentColor : Color.primary)
            .background(
                destination == item ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
    }

    private func jump(_ item: ControlDestination) {
        destination = item
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
                        Text("\\(configured) of \\(total) setup components verified")
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
