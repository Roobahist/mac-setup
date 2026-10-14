import Foundation
import MacSetupCore

/// An editor for workspace IDs, their Nerd Font glyphs, and application routing.
/// Reuses the existing raw terminal so entering from the setup checklist does not
/// tear down and recreate the terminal or lose key presses.
struct WorkspacePickerUI {
    private enum Page {
        case workspaces, glyphs, apps, editID, editName, manualApp, confirmDelete
    }

    private var layout: WorkspaceConfiguration
    private let installed: [InstalledApplication]
    private var page: Page = .workspaces
    private var selected = 0
    private var resultCursor = 0
    private var query = ""
    private var editing = ""
    private var message = ""

    init(layout: WorkspaceConfiguration, installed: [InstalledApplication]) {
        self.layout = layout
        self.installed = installed
    }

    mutating func run(in terminal: RawTerminal) -> WorkspaceConfiguration? {
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

            if case .interrupt = key { return nil }
            switch page {
            case .workspaces:
                switch key {
                case .up: selected = max(0, selected - 1)
                case .down: selected = min(layout.workspaces.count - 1, selected + 1)
                case .escape: return nil
                case .character(let c):
                    switch c {
                    case "q": return nil
                    case "s":
                        do { try layout.validate(); return layout }
                        catch { message = String(describing: error) }
                    case "a":
                        guard layout.workspaces.count < WorkspaceConfiguration.keys.count else {
                            message = "All 13 keyboard shortcuts are in use."; break
                        }
                        var id = "workspace"
                        var index = 2
                        while layout.workspaces.contains(where: { $0.id == id }) {
                            id = "workspace\(index)"
                            index += 1
                        }
                        layout.workspaces.insert(
                            WorkspaceDefinition(id: id, name: "New Workspace", glyph: "terminal"),
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
                        page = .glyphs; query = ""; resultCursor = 0
                    case "p":
                        page = .apps; query = ""; resultCursor = 0
                    case "[":
                        if selected > 0 {
                            layout.workspaces.swapAt(selected, selected - 1)
                            selected -= 1
                        }
                    case "]":
                        if selected < layout.workspaces.count - 1 {
                            layout.workspaces.swapAt(selected, selected + 1)
                            selected += 1
                        }
                    default: break
                    }
                default: break
                }
            case .confirmDelete:
                switch key {
                case .character("y"):
                    guard layout.workspaces.count > 1 else {
                        message = "At least one workspace is required."; page = .workspaces; break
                    }
                    layout.workspaces.remove(at: selected)
                    selected = min(selected, layout.workspaces.count - 1)
                    page = .workspaces
                case .character("n"), .escape: page = .workspaces
                default: break
                }
            case .glyphs:
                let matches = WorkspaceGlyph.matching(query)
                switch key {
                case .up: resultCursor = max(0, resultCursor - 1)
                case .down: resultCursor = min(max(0, matches.count - 1), resultCursor + 1)
                case .enter:
                    if !matches.isEmpty {
                        layout.workspaces[selected].glyph = matches[resultCursor].name
                        page = .workspaces
                    }
                case .backspace:
                    if !query.isEmpty { query.removeLast(); resultCursor = 0 }
                case .escape:
                    if query.isEmpty { page = .workspaces }
                    else { query = ""; resultCursor = 0 }
                case .character(let c):
                    if c == "/" && query.isEmpty { break }
                    query.append(c); resultCursor = 0
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
                        layout.workspaces[selected].name = candidate
                        page = .workspaces
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
        let apps = installed.filter { app in
            query.isEmpty || app.name.localizedCaseInsensitiveContains(query)
                || app.bundleID.localizedCaseInsensitiveContains(query)
        }
        return apps
    }

    private func fitted(_ text: String, width: Int) -> String {
        let count = max(5, width)
        return text.count > count ? String(text.prefix(count - 1)) + "…" : text
    }

    private func render(width: Int, height: Int) -> String {
        let usable = max(15, width - 4)
        var lines = [
            "  ◈  WORKSPACE EDITOR",
            "  \(layout.workspaces.count)/\(WorkspaceConfiguration.keys.count) workspaces  ·  Hack Nerd Font icons",
            "  " + String(repeating: "─", count: min(75, usable))
        ]
        switch page {
        case .workspaces, .confirmDelete:
            lines.append("  ↑↓ Select  [ ] Reorder  A Add  D Remove  R Rename ID  N Label")
            lines.append("  G Glyph  P Apps  S Save  Q Cancel")
            lines.append("")
            let available = max(3, height - 14)
            let first = max(0, min(max(0, layout.workspaces.count - available), selected - available / 2))
            for index in first..<min(layout.workspaces.count, first + available) {
                let ws = layout.workspaces[index]
                let key = WorkspaceConfiguration.keys[index]
                let glyph = WorkspaceConfiguration.symbol(for: ws.glyph) ?? "?"
                let marker = index == selected ? "❯" : " "
                lines.append(fitted("  \(marker) ⌥\(key)  \(glyph)  \(ws.name)  [\(ws.id)]  ·  \(ws.apps.count) apps", width: usable))
            }
            lines.append("")
            let current = layout.workspaces[selected]
            if !current.apps.isEmpty {
                lines.append("  Assigned app bundle IDs:")
                let names = Dictionary(installed.map { ($0.bundleID, $0.name) },
                                       uniquingKeysWith: { first, _ in first })
                for id in current.apps.prefix(max(1, height - lines.count - 5)) {
                    lines.append(fitted("    " + (names[id] ?? id), width: usable))
                }
            } else {
                lines.append("  No applications assigned. Apps stay in the workspace where you open them.")
            }
            if page == .confirmDelete {
                lines.append("  Remove \(current.name) and its app rules? Y Yes  N Cancel")
            }
        case .glyphs:
            lines.append("  Type to filter glyph names or keywords  ·  ↑↓ Choose  Enter Select  Esc Back")
            lines.append("  Search: \(query)▌")
            lines.append("")
            let matches = WorkspaceGlyph.matching(query)
            let available = max(3, height - 9)
            let start = max(0, min(max(0, matches.count - available), resultCursor - available / 2))
            for index in start..<min(matches.count, start + available) {
                let item = matches[index]
                lines.append(fitted("  \(index == resultCursor ? "❯" : " ")  \(item.symbol)  \(item.name)  ·  \(item.keywords)",
                                    width: usable))
            }
            if matches.isEmpty { lines.append("  No matching glyphs.") }
        case .apps:
            lines.append("  Type to filter installed apps  ·  ↑↓ Select  Space Assign/Remove  + Bundle ID")
            lines.append("  Esc Clear/Back  ·  Selected workspace: \(layout.workspaces[selected].name)")
            lines.append("  Search: \(query)▌    \(installed.count) installed apps found")
            lines.append("")
            let matches = filteredApps()
            let available = max(3, height - 10)
            let start = max(0, min(max(0, matches.count - available), resultCursor - available / 2))
            for index in start..<min(matches.count, start + available) {
                let app = matches[index]
                let owner = layout.workspaces.firstIndex(where: { $0.apps.contains(app.bundleID) })
                let assigned = owner.map { layout.workspaces[$0].name } ?? "Unassigned"
                lines.append(fitted("  \(index == resultCursor ? "❯" : " ") \(owner == selected ? "[x]" : "[ ]") \(app.name)  ·  \(assigned)",
                                    width: usable))
                lines.append(fitted("        \(app.bundleID)", width: usable))
            }
            if matches.isEmpty { lines.append("  No matching applications. + adds a bundle ID manually.") }
        case .editID, .editName, .manualApp:
            lines.append(page == .editID ? "  Rename AeroSpace workspace ID (letters, digits, _ and -):" :
                         page == .editName ? "  Change the descriptive workspace label:" :
                         "  Enter the application's CFBundleIdentifier:")
            lines.append("  \(editing)▌")
            lines.append("")
            lines.append("  Enter Save  ·  Backspace Delete  ·  Esc Cancel")
        }
        if !message.isEmpty {
            lines.append("")
            lines.append(fitted("  " + message, width: usable))
        }
        if lines.count > height { lines = Array(lines.prefix(height)) }
        return "\u{001B}[H\u{001B}[2J" + lines.map { fitted($0, width: width) }.joined(separator: "\r\n") + "\r\n"
    }
}
