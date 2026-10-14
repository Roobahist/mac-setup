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
    @State private var destination: ControlDestination? = .home
    @State private var previousDestination: ControlDestination = .home
    @State private var query = ""
    @State private var activeFeature: String?

    init(model: SetupModel, initialDestination: ControlDestination = .home) {
        self.model = model
        _destination = State(initialValue: initialDestination)
        _previousDestination = State(initialValue: initialDestination)
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac Setup").font(.headline)
                        Text("Your Mac, your way").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 10)

                TextField("Search settings", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .accessibilityLabel("Search settings and features")

                List(selection: $destination) {
                    Section("Customize") {
                        ForEach([ControlDestination.home, .appearance, .dock, .menuBar, .finder,
                                 .workspaces, .shortcuts, .apps]) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    Section("Mac Setup") {
                        ForEach([ControlDestination.guidedSetup, .updates]) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                }
                .listStyle(.sidebar)

                HStack {
                    Text("Version \(MacSetupVersion.installed)")
                    Spacer()
                    Circle().fill(model.busy ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(model.busy ? "Checking or applying settings" : "Ready")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
            .frame(minWidth: 220)
        } detail: {
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
            .frame(minWidth: 680, minHeight: 670)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1050, minHeight: 740)
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

    private func jump(_ item: ControlDestination) {
        destination = item
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Make this Mac yours").font(.system(size: 29, weight: .semibold))
                        Text("Customize one thing at a time, or apply the entire setup.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Guided setup") { jump(.guidedSetup) }
                        .buttonStyle(.borderedProminent)
                }
                Text("PERSONALIZE")
                    .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach([ControlDestination.appearance, .dock, .menuBar, .finder,
                             .workspaces, .shortcuts, .apps]) { item in
                        Button { jump(item) } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 22, weight: .medium))
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(Color.accentColor)
                                Text(item.title).font(.headline).foregroundStyle(.primary)
                                Text(description(for: item))
                                    .font(.callout).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 0)
                                HStack {
                                    Text("Customize").font(.caption.weight(.medium))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }.foregroundStyle(Color.accentColor)
                            }
                            .padding(18).frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Customize \(item.title)")
                    }
                }
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                    Text("New features are delivered through versioned updates.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check updates") { jump(.updates) }
                }.font(.callout).padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }.padding(28)
        }
    }

    private func description(for destination: ControlDestination) -> String {
        switch destination {
        case .appearance: return "Wallpaper colors, accent watcher and native accent."
        case .dock: return "Reveal timing, animations and icon size."
        case .menuBar: return "Clock format and visible menu bar details."
        case .finder: return "Paths, hidden files and window information."
        case .workspaces: return "Arrange desktops and route applications."
        case .shortcuts: return "Manage the shared keyboard layout."
        case .apps: return "Install and configure individual components."
        default: return ""
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
