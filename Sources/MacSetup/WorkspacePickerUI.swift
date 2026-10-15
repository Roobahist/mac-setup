import Foundation
import MacSetupCore

/// An editor for workspace IDs, their Nerd Font glyphs, and application routing.
/// Reuses the existing raw terminal so entering from the setup checklist does not
/// tear down and recreate the terminal or lose key presses.
struct WorkspacePickerUI {
    enum Context { case setup, standalone }
    enum Outcome {
        case saved(WorkspaceConfiguration)
        case kept
        case cancelled
    }

    private typealias Page = WorkspacePickerView.Page

    private var layout: WorkspaceConfiguration
    private let initialLayout: WorkspaceConfiguration
    private let installed: [InstalledApplication]
    private let context: Context
    private let maximumWorkspaces: Int
    private var page: Page = .workspaces
    private var selected = 0
    private var resultCursor = 0
    private var query = ""
    private var editing = ""
    private var message = ""
    private var glyphFont: GlyphFont
    private var glyphs: [FontGlyph] = []
    private var fonts: [GlyphFont] = []

    init(layout: WorkspaceConfiguration, installed: [InstalledApplication],
         context: Context = .standalone,
         maximumWorkspaces: Int = Int.max) {
        self.layout = layout
        self.initialLayout = layout
        self.installed = installed
        self.context = context
        self.maximumWorkspaces = maximumWorkspaces
        glyphFont = layout.workspaces[0].resolvedIcon.font
    }

    mutating func run(in terminal: RawTerminal) -> Outcome {
        var redraw = true
        while true {
            if redraw {
                terminal.write(render(width: terminal.dimensions.width,
                                      height: terminal.dimensions.height))
                redraw = false
            }
            let key = terminal.nextKey(timeout: 120)
            if case .idle = key { continue }
            redraw = true
            message = ""

            if case .interrupt = key { return .cancelled }
            switch page {
            case .workspaces:
                switch key {
                case .up: selected = max(0, selected - 1)
                case .down: selected = min(layout.workspaces.count - 1, selected + 1)
                case .escape:
                    if layout == initialLayout { return .cancelled }
                    page = .confirmCancel
                case .character(let c):
                    switch c {
                    case "q":
                        if layout == initialLayout { return .cancelled }
                        page = .confirmCancel
                    case "k":
                        if context == .setup {
                            if layout == initialLayout { return .kept }
                            message = "Save edits with S, or Q to discard them before keeping the current layout."
                        }
                    case "s":
                        do { try layout.validate(); return .saved(layout) }
                        catch { message = String(describing: error) }
                    case "a":
                        guard layout.workspaces.count < maximumWorkspaces else {
                            message = "All available workspace slots are in use. Optional disabled workspaces are preserved."; break
                        }
                        var id = "workspace"
                        var index = 2
                        while layout.workspaces.contains(where: { $0.id == id }) {
                            id = "workspace\(index)"
                            index += 1
                        }
                        layout.workspaces.insert(
                            WorkspaceDefinition(id: id, name: "New Workspace", glyph: "terminal", shortcutKey: ""),
                            at: selected + 1)
                        selected += 1
                        message = "Choose R to rename the workspace ID, N for its label, or G for a glyph."
                    case "d": page = .confirmDelete
                    case "r":
                        editing = layout.workspaces[selected].id
                        page = .editID
                    case "n":
                        editing = layout.workspaces[selected].name
                        page = .editName
                    case "g":
                        fonts = FontGlyphCatalog.fonts()
                        glyphFont = layout.workspaces[selected].resolvedIcon.font
                        do { glyphs = try FontGlyphCatalog.glyphs(in: glyphFont) }
                        catch { glyphs = []; message = String(describing: error) + " Press Tab to choose a font." }
                        page = .glyphs; query = ""; resultCursor = 0
                    case "p":
                        page = .apps; query = ""; resultCursor = 0
                    case "[":
                        if selected > 0 {
                            layout.insertWorkspace(layout.workspaces[selected].id, at: selected - 1)
                            selected -= 1
                        }
                    case "]":
                        if selected < layout.workspaces.count - 1 {
                            layout.insertWorkspace(layout.workspaces[selected].id, at: selected + 2)
                            selected += 1
                        }
                    default: break
                    }
                case .enter:
                    if context == .setup {
                        if layout == initialLayout { return .kept }
                        message = "Press S to save changes and continue, or Q to return without saving."
                    }
                default: break
                }
            case .confirmCancel:
                switch key {
                case .character("y"): return .cancelled
                case .character("n"), .escape: page = .workspaces
                default: break
                }
            case .confirmDelete:
                switch key {
                case .character("y"):
                    guard layout.workspaces.count > 1 else {
                        message = "At least one workspace is required."; page = .workspaces; break
                    }
                    layout.removeWorkspace(layout.workspaces[selected].id)
                    selected = min(selected, layout.workspaces.count - 1)
                    page = .workspaces
                case .character("n"), .escape: page = .workspaces
                default: break
                }
            case .glyphs:
                let matches = FontGlyphCatalog.matching(glyphs, query: query)
                switch key {
                case .up: resultCursor = max(0, resultCursor - 1)
                case .down: resultCursor = min(max(0, matches.count - 1), resultCursor + 1)
                case .enter:
                    if !matches.isEmpty {
                        layout.workspaces[selected].icon = matches[resultCursor].selection
                        page = .workspaces
                    }
                case .tab:
                    page = .fonts; query = ""; resultCursor = 0
                case .backspace:
                    if !query.isEmpty { query.removeLast(); resultCursor = 0 }
                case .space: query.append(" "); resultCursor = 0
                case .escape:
                    if query.isEmpty { page = .workspaces }
                    else { query = ""; resultCursor = 0 }
                case .character(let c):
                    if c == "/" && query.isEmpty { break }
                    query.append(c); resultCursor = 0
                default: break
                }
            case .fonts:
                let words = query.split(whereSeparator: \.isWhitespace)
                let matches = fonts.filter { font in words.allSatisfy { font.title.localizedCaseInsensitiveContains($0) || font.id.localizedCaseInsensitiveContains($0) } }
                switch key {
                case .up: resultCursor = max(0, resultCursor - 1)
                case .down: resultCursor = min(max(0, matches.count - 1), resultCursor + 1)
                case .enter:
                    if let font = matches.indices.contains(resultCursor) ? matches[resultCursor] : nil {
                        do {
                            glyphs = try FontGlyphCatalog.glyphs(in: font); glyphFont = font
                            page = .glyphs; query = ""; resultCursor = 0
                        } catch { message = String(describing: error) }
                    }
                case .tab: page = .glyphs; query = ""; resultCursor = 0
                case .backspace:
                    if !query.isEmpty { query.removeLast(); resultCursor = 0 }
                case .space: query.append(" "); resultCursor = 0
                case .escape:
                    if query.isEmpty { page = .glyphs }
                    else { query = ""; resultCursor = 0 }
                case .character(let c): query.append(c); resultCursor = 0
                default: break
                }
            case .apps:
                let matches = filteredApps()
                switch key {
                case .up: resultCursor = max(0, resultCursor - 1)
                case .down: resultCursor = min(max(0, matches.count - 1), resultCursor + 1)
                case .space, .enter:
                    if !matches.isEmpty { toggleApp(matches[resultCursor].bundleID) }
                case .backspace:
                    if !query.isEmpty { query.removeLast(); resultCursor = 0 }
                case .escape:
                    if query.isEmpty { page = .workspaces }
                    else { query = ""; resultCursor = 0 }
                case .character(let c):
                    if c == "/" && query.isEmpty { break }
                    if c == "+" && query.isEmpty {
                        editing = ""; page = .manualApp
                    } else {
                        query.append(c); resultCursor = 0
                    }
                default: break
                }
            case .editID, .editName, .manualApp:
                switch key {
                case .enter:
                    let candidate = editing.trimmingCharacters(in: .whitespacesAndNewlines)
                    if page == .editID {
                        let old = layout.workspaces[selected].id
                        layout.workspaces[selected].id = candidate
                        if (try? layout.validate()) == nil {
                            layout.workspaces[selected].id = old
                            message = "ID must be unique and contain only letters, digits, _ or -."
                        } else { page = .workspaces }
                    } else if page == .editName {
                        guard !candidate.isEmpty else { message = "Name cannot be empty."; break }
                        do {
                            try layout.renameWorkspace(layout.workspaces[selected].id, to: candidate)
                            page = .workspaces
                        } catch { message = String(describing: error) }
                    } else {
                        guard !candidate.isEmpty else { message = "Enter an app bundle ID."; break }
                        let previous = layout
                        toggleApp(candidate)
                        if (try? layout.validate()) == nil {
                            layout = previous
                            message = "Bundle ID may only contain letters, numbers, dots, _ or -."
                        } else { page = .apps }
                    }
                case .backspace: if !editing.isEmpty { editing.removeLast() }
                case .space: if page == .editName { editing.append(" ") }
                case .escape: page = page == .manualApp ? .apps : .workspaces
                case .character(let c): editing.append(c)
                default: break
                }
            }
        }
    }

    private mutating func toggleApp(_ id: String) {
        if let index = layout.workspaces[selected].apps.firstIndex(of: id) {
            layout.workspaces[selected].apps.remove(at: index)
        } else {
            // Moving an app into a workspace removes its previous routing rule.
            for index in layout.workspaces.indices {
                layout.workspaces[index].apps.removeAll { $0 == id }
            }
            layout.workspaces[selected].apps.append(id)
            layout.workspaces[selected].apps.sort()
        }
    }

    private func filteredApps() -> [InstalledApplication] {
        // Include saved app rules even when the app is not installed. Otherwise
        // users cannot remove an obsolete assignment from the configuration.
        let discovered = Set(installed.map(\.bundleID))
        let saved = Set(layout.workspaces.flatMap(\.apps)).subtracting(discovered)
            .map { InstalledApplication(name: $0, bundleID: $0, path: "") }
        return (installed + saved).filter { app in
            query.isEmpty || app.name.localizedCaseInsensitiveContains(query)
                || app.bundleID.localizedCaseInsensitiveContains(query)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func render(width: Int, height: Int) -> String {
        WorkspacePickerView(
            layout: layout,
            installed: installed,
            glyphFont: glyphFont,
            glyphs: glyphs,
            fonts: fonts,
            page: page,
            selected: selected,
            resultCursor: resultCursor,
            query: query,
            editing: editing,
            message: message,
            modified: layout != initialLayout,
            guidedSetup: context == .setup,
            maximumWorkspaces: maximumWorkspaces,
            width: width,
            height: height
        ).render()
    }
}
