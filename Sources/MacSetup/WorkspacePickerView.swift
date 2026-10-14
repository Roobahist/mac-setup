import Foundation
import Darwin
import MacSetupCore

/// A renderer for the workspace editor. All layout decisions are based on
/// terminal cell widths so the same screens work in narrow and wide terminals.
struct WorkspacePickerView {
    enum Page {
        case workspaces, glyphs, apps, editID, editName, manualApp, confirmDelete, confirmCancel
    }

    let layout: WorkspaceConfiguration
    let installed: [InstalledApplication]
    let page: Page
    let selected: Int
    let resultCursor: Int
    let query: String
    let editing: String
    let message: String
    let modified: Bool
    let guidedSetup: Bool
    let maximumWorkspaces: Int
    let width: Int
    let height: Int

    private enum Tone {
        case normal, muted, accent, title, selected, success, caution, danger
    }

    /// The terminal may render a private-use glyph as one or two cells.
    /// Paint it over reserved blank cells rather than including it in the text
    /// used to calculate subsequent column positions.
    private struct GlyphPlacement {
        let symbol: String
        let offset: Int
    }

    private struct Line {
        let text: String
        let tone: Tone
        let glyph: GlyphPlacement?

        init(_ text: String = "", _ tone: Tone = .normal, glyph: GlyphPlacement? = nil) {
            self.text = text
            self.tone = tone
            self.glyph = glyph
        }
    }

    private var useColor: Bool {
        ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && ProcessInfo.processInfo.environment["TERM"] != "dumb"
    }

    private var availableWidth: Int { max(22, width - 4) }
    private var workspace: WorkspaceDefinition { layout.workspaces[selected] }
    private var wide: Bool { availableWidth >= 104 && height >= 22 }

    private func color(_ text: String, _ tone: Tone) -> String {
        guard useColor else { return text }
        let code: String
        switch tone {
        case .normal: code = "38;5;252"
        case .muted: code = "38;5;245"
        case .accent: code = "1;38;5;81"
        case .title: code = "1;38;5;255"
        case .selected: code = "1;38;5;231;48;5;24"
        case .success: code = "38;5;114"
        case .caution: code = "38;5;221"
        case .danger: code = "1;38;5;203"
        }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }

    // Swift Character.count is not the number of occupied terminal cells. In
    // particular, Nerd Font code points and East Asian characters can differ.
    private func cells(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { count, scalar in
            count + max(0, Int(Darwin.wcwidth(Int32(scalar.value))))
        }
    }

    private func fit(_ text: String, to maxWidth: Int, padded: Bool = false) -> String {
        let bound = max(0, maxWidth)
        guard cells(text) > bound else {
            return padded ? text + String(repeating: " ", count: bound - cells(text)) : text
        }
        guard bound > 1 else { return bound == 1 ? "…" : "" }
        var prefix = ""
        var used = 0
        for scalar in text.unicodeScalars {
            let size = max(0, Int(Darwin.wcwidth(Int32(scalar.value))))
            if used + size > bound - 1 { break }
            prefix.unicodeScalars.append(scalar)
            used += size
        }
        let clipped = prefix + "…"
        return padded ? clipped + String(repeating: " ", count: bound - cells(clipped)) : clipped
    }

    private func styled(_ line: Line, width: Int, padded: Bool = false,
                        startColumn: Int = 3) -> String {
        let text = color(fit(line.text, to: width, padded: padded), line.tone)
        guard let glyph = line.glyph, glyph.offset + 4 <= width else { return text }

        // Preserve the insertion point, move to the icon cell, draw the glyph,
        // then return to the next column. A missing-font rectangle can occupy
        // two cells without shifting any following text or the right-hand panel.
        let absoluteColumn = startColumn + glyph.offset
        return text + "\u{001B}7\u{001B}[\(absoluteColumn)G"
            + color(glyph.symbol, line.tone) + "\u{001B}8"
    }

    private func divider() -> Line {
        Line(String(repeating: "─", count: min(availableWidth, 100)), .muted)
    }

    private func shortcut(at index: Int) -> String {
        let key = WorkspaceConfiguration.keys[index]
        switch key {
        case "backtick": return "Alt+`"
        case "minus": return "Alt+-"
        case "equal": return "Alt+="
        default: return "Alt+" + key
        }
    }

    private func selectionRange(total: Int, limit: Int, cursor: Int) -> Range<Int> {
        guard total > 0 else { return 0..<0 }
        let count = min(total, max(1, limit))
        let start = min(max(0, total - count), max(0, cursor - count / 2))
        return start..<(start + count)
    }

    private func workspaceColumns(width: Int, includeID: Bool)
        -> (shortcut: Int, name: Int, icon: Int, glyph: Int, id: Int, apps: Int) {
        let shortcut = 9
        let icon = 4
        let glyph = width >= 63 ? 13 : 10
        let id = includeID ? min(20, max(12, width / 4)) : 0
        let apps = 5
        let spacing = 3 + shortcut + 2 + 2 + icon + 2
            + glyph + (includeID ? 2 + id : 0) + 2 + apps
        return (shortcut, max(7, width - spacing), icon, glyph, id, apps)
    }

    private func tableRow(_ index: Int, width: Int, includeID: Bool) -> Line {
        let ws = layout.workspaces[index]
        let columns = workspaceColumns(width: width, includeID: includeID)
        let symbol = WorkspaceConfiguration.symbol(for: ws.glyph) ?? "?"
        let iconOffset = 3 + columns.shortcut + 2 + columns.name + 2
        let text = " \(index == selected ? ">" : " ") "
            + fit(shortcut(at: index), to: columns.shortcut, padded: true) + "  "
            + fit(ws.name, to: columns.name, padded: true) + "  "
            + String(repeating: " ", count: columns.icon) + "  "
            + fit(ws.glyph, to: columns.glyph, padded: true)
            + (includeID ? "  " + fit(ws.id, to: columns.id, padded: true) : "")
            + "  " + fit(String(ws.apps.count), to: columns.apps, padded: true)
        return Line(fit(text, to: width, padded: true),
                    index == selected ? .selected : .normal,
                    glyph: GlyphPlacement(symbol: symbol, offset: iconOffset))
    }

    private func tableHeading(width: Int, includeID: Bool) -> Line {
        let columns = workspaceColumns(width: width, includeID: includeID)
        let text = "   "
            + fit("SHORTCUT", to: columns.shortcut, padded: true) + "  "
            + fit("NAME", to: columns.name, padded: true) + "  "
            + fit("ICON", to: columns.icon, padded: true) + "  "
            + fit("GLYPH", to: columns.glyph, padded: true)
            + (includeID ? "  " + fit("ID", to: columns.id, padded: true) : "")
            + "  " + fit("APPS", to: columns.apps, padded: true)
        return Line(fit(text, to: width), .accent)
    }

    private func appNames() -> [String] {
        let byID = Dictionary(installed.map { ($0.bundleID, $0.name) },
                              uniquingKeysWith: { first, _ in first })
        return workspace.apps.map { id in
            byID[id].map { "\($0)  [\(id)]" } ?? id
        }
    }

    private func inspector() -> [Line] {
        var lines: [Line] = [
            Line("SELECTED WORKSPACE", .accent), Line(),
            Line(fit(workspace.name, to: max(10, availableWidth / 3)), .title),
            Line(),
            Line("Shortcut    \(shortcut(at: selected))", .normal),
            Line("AeroSpace ID", .muted),
            Line("  \(workspace.id)", .normal),
            Line("SketchyBar glyph", .muted),
            Line("        \(workspace.glyph)", .normal,
                 glyph: GlyphPlacement(symbol: WorkspaceConfiguration.symbol(for: workspace.glyph) ?? "?",
                                       offset: 2)),
            Line(),
            Line("APP RULES  \(workspace.apps.count)", .accent)
        ]
        if workspace.apps.isEmpty {
            lines.append(Line("  No apps assigned", .muted))
        } else {
            let names = appNames()
            let show = max(1, min(names.count, height - 21))
            for name in names.prefix(show) {
                lines.append(Line("  • " + name))
            }
            if names.count > show { lines.append(Line("  +\(names.count - show) more", .muted)) }
        }
        lines += [Line(), Line("P  Edit app assignments", .accent),
                  Line("G  Browse glyphs", .accent)]
        return lines
    }

    private func tableAndInspector() -> [String] {
        let leftWidth = wide ? max(62, (availableWidth * 63) / 100) : availableWidth
        let rightWidth = wide ? availableWidth - leftWidth - 3 : 0
        let includeID = leftWidth >= 66
        let listHeight = max(1, SetupChrome.bodyCapacity(height: height) - (wide ? 4 : 7))
        let range = selectionRange(total: layout.workspaces.count, limit: listHeight, cursor: selected)
        var left: [Line] = [
            Line("WORKSPACE ORDER", .accent),
            Line(),
            tableHeading(width: leftWidth, includeID: includeID)
        ]
        for index in range { left.append(tableRow(index, width: leftWidth, includeID: includeID)) }
        if range.count < layout.workspaces.count {
            left.append(Line("  Showing \(range.lowerBound + 1)-\(range.upperBound) of \(layout.workspaces.count); use ↑↓ to scroll", .muted))
        }
        if !wide {
            left += [Line(), Line("SELECTED: \(workspace.name)  |  ID: \(workspace.id)  |  Glyph: \(workspace.glyph)", .accent)]
            if !workspace.apps.isEmpty {
                left.append(Line("Assigned: " + appNames().joined(separator: ", "), .muted))
            } else {
                left.append(Line("Assigned apps: none", .muted))
            }
            return left.map { styled($0, width: availableWidth) }
        }
        let right = inspector()
        let count = max(left.count, right.count)
        return (0..<count).map { index in
            let l = index < left.count ? left[index] : Line()
            let r = index < right.count ? right[index] : Line()
            return styled(l, width: leftWidth, padded: true)
                + color(" │ ", .muted)
                + styled(r, width: rightWidth, startColumn: leftWidth + 6)
        }
    }

    private func glyphRows() -> [Line] {
        let matches = WorkspaceGlyph.matching(query)
        var lines: [Line] = [
            Line("GLYPH LIBRARY   /   \(workspace.name)", .accent),
            Line("Type to filter glyph names and keywords", .muted),
            Line("Search: \(query)\(useColor ? "▌" : "_")    \(matches.count) matches", .title),
            Line(),
            Line("   ICON  GLYPH NAME            KEYWORDS / DESCRIPTION", .accent)
        ]
        let pageRows = max(1, SetupChrome.bodyCapacity(height: height) - 10)
        for index in selectionRange(total: matches.count, limit: pageRows, cursor: resultCursor) {
            let glyph = matches[index]
            let label = fit(glyph.name, to: 20, padded: true)
            let text = " \(index == resultCursor ? ">" : " ") "
                + "    " + "  " + label
                + "  " + glyph.keywords
            lines.append(Line(text, index == resultCursor ? .selected : .normal,
                              glyph: GlyphPlacement(symbol: glyph.symbol, offset: 3)))
        }
        if matches.isEmpty { lines.append(Line("  No matching glyphs. Try another keyword.", .caution)) }
        if let candidate = matches.indices.contains(resultCursor) ? matches[resultCursor] : nil {
            lines += [
                Line(),
                Line("SELECTED GLYPH", .accent),
                Line("  Name: \(candidate.name)    Code point: U+\(String(candidate.symbol.unicodeScalars.first!.value, radix: 16).uppercased())", .normal),
                Line("  Preview: \(candidate.symbol)", .muted)
            ]
        }
        return lines
    }

    private func knownApps() -> [InstalledApplication] {
        let existing = Set(installed.map(\.bundleID))
        let extra = Set(layout.workspaces.flatMap(\.apps)).subtracting(existing)
            .map { InstalledApplication(name: $0, bundleID: $0, path: "") }
        return (installed + extra).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func appRows() -> [Line] {
        let apps = knownApps()
        let matches = apps.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
        let usable = availableWidth
        let appWidth = max(14, usable * 32 / 100)
        let ownerWidth = max(12, usable * 23 / 100)
        let bundleWidth = max(10, usable - appWidth - ownerWidth - 11)
        var lines: [Line] = [
            Line("APP ROUTING   /   \(workspace.name)", .accent),
            Line("Type to filter installed apps or bundle IDs", .muted),
            Line("Search: \(query)\(useColor ? "▌" : "_")   \(matches.count) results   ·   \(installed.count) installed apps found", .title),
            Line(),
            Line("    " + fit("APPLICATION", to: appWidth, padded: true) + "  "
                 + fit("BUNDLE ID", to: bundleWidth, padded: true) + "  "
                 + "ASSIGNED TO", .accent)
        ]
        let pageRows = max(1, SetupChrome.bodyCapacity(height: height) - 9)
        for index in selectionRange(total: matches.count, limit: pageRows, cursor: resultCursor) {
            let app = matches[index]
            let owner = layout.workspaces.firstIndex { $0.apps.contains(app.bundleID) }
            let ownerName: String
            if owner == selected { ownerName = "THIS WORKSPACE" }
            else if let owner { ownerName = layout.workspaces[owner].name }
            else { ownerName = "Unassigned" }
            let checkbox = owner == selected ? "[x]" : "[ ]"
            let text = " \(index == resultCursor ? ">" : " ") \(checkbox) "
                + fit(app.name, to: appWidth, padded: true) + "  "
                + fit(app.bundleID, to: bundleWidth, padded: true) + "  "
                + fit(ownerName, to: ownerWidth)
            lines.append(Line(text, index == resultCursor ? .selected : owner == selected ? .success : .normal))
        }
        if matches.isEmpty { lines.append(Line("  No matching applications. Press + to enter a bundle ID.", .caution)) }
        if let app = matches.indices.contains(resultCursor) ? matches[resultCursor] : nil {
            lines += [Line(), Line("SELECTED APPLICATION", .accent),
                      Line("  \(app.name)  |  \(app.bundleID)", .normal),
                      Line("  Space assigns/removes it. Rules move windows, not launch apps.", .muted)]
        }
        return lines
    }

    private func promptRows() -> [Line] {
        let descriptor: String
        let explanation: String
        switch page {
        case .editID:
            descriptor = "RENAME WORKSPACE ID"
            explanation = "AeroSpace uses this unique ID in window rules and keyboard shortcuts."
        case .editName:
            descriptor = "CHANGE WORKSPACE LABEL"
            explanation = "The label is for this editor. SketchyBar displays your chosen glyph."
        default:
            descriptor = "ASSIGN AN APPLICATION"
            explanation = "Enter the application's bundle ID, such as com.example.app."
        }
        return [Line(descriptor, .accent), Line(), Line(explanation, .muted),
                Line(), Line("New value:", .title),
                Line("  \(editing)▌", .selected),
                Line(), Line("Enter  Confirm       Esc  Cancel", .muted)]
    }

    private func warningRows() -> [Line] {
        if page == .confirmCancel {
            return [Line("DISCARD YOUR CHANGES?", .danger), Line(),
                    Line("You have unsaved edits to this workspace layout."),
                    Line("Discard and return to the previous screen?", .muted),
                    Line(), Line("Y  Discard changes    N / Esc  Continue editing", .caution)]
        }
        return [Line("REMOVE WORKSPACE?", .danger), Line(),
                Line("Name: \(workspace.name)    AeroSpace ID: \(workspace.id)"),
                Line("This also removes its \(workspace.apps.count) app routing rule(s).", .caution),
                Line(), Line("Y  Remove workspace    N / Esc  Keep workspace", .caution)]
    }

    private func shortcuts() -> [Line] {
        switch page {
        case .workspaces:
            return [
                Line("↑↓ Select   [ ] Reorder   A Add   D Remove   R ID   N Label   G Glyph   P Apps", .accent),
                guidedSetup
                    ? Line("Enter / K Keep layout   S Save & Continue   Esc Back to features", .muted)
                    : Line("S Save   Q Cancel   Apply AeroSpace / SketchyBar profiles afterward.", .muted)
            ]
        case .glyphs:
            return [Line("↑↓ Select     Enter Use glyph     Type to search     Esc Clear search / Back", .accent),
                    Line("Icons are always shown. Set your terminal font to Hack Nerd Font for proper rendering.", .muted)]
        case .apps:
            return [Line("↑↓ Select    Space / Enter Assign or remove    + Manual bundle ID    Esc Clear / Back", .accent),
                    Line("An app belongs to at most one workspace. Reassigning it replaces its old rule.", .muted)]
        case .editID, .editName, .manualApp:
            return [Line("Enter  Confirm    Backspace  Delete    Esc  Cancel", .accent)]
        case .confirmDelete, .confirmCancel:
            return [Line("Y  Confirm    N / Esc  Go back", .caution)]
        }
    }

    func render() -> String {
        let saveState = modified ? "UNSAVED CHANGES" : "NO UNSAVED CHANGES"
        let header = SetupChrome.header(
            step: .workspaces,
            summary: "WORKSPACE EDITOR   |   \(layout.workspaces.count) of \(maximumWorkspaces) editable slots",
            context: "\(saveState)   |   \(guidedSetup ? "Keep existing layout or customize before review" : "Standalone configuration")",
            width: width
        )

        let body: [String]
        switch page {
        case .workspaces: body = tableAndInspector()
        case .glyphs: body = glyphRows().map { styled($0, width: availableWidth) }
        case .apps: body = appRows().map { styled($0, width: availableWidth) }
        case .editID, .editName, .manualApp: body = promptRows().map { styled($0, width: availableWidth) }
        case .confirmDelete, .confirmCancel: body = warningRows().map { styled($0, width: availableWidth) }
        }

        let controls = shortcuts()
        let status = !message.isEmpty ? message
            : modified ? "Unsaved edits are not applied until you save them."
            : "Workspace configuration is unchanged."
        let title: String
        let description: String
        switch page {
        case .workspaces:
            title = "\(workspace.name)  [\(workspace.id)]   |   \(workspace.apps.count) app rules"
            description = "Edit the selected workspace's shortcut order, label, glyph or application assignments."
        case .glyphs:
            title = "GLYPH LIBRARY   |   \(workspace.name)"
            description = "Type to filter glyph names; select one with Enter."
        case .apps:
            title = "APP ROUTING   |   \(workspace.name)"
            description = "Filter installed apps by name or bundle ID and toggle their workspace assignments."
        case .editID, .editName, .manualApp:
            title = "EDIT WORKSPACE   |   \(workspace.name)"
            description = "Enter a new value, then confirm or cancel."
        case .confirmDelete, .confirmCancel:
            title = "CONFIRM ACTION"
            description = "Review the change before confirming."
        }
        let footer = SetupChrome.footer(
            title: title,
            description: description,
            status: status,
            primary: controls.first?.text ?? "Esc Back",
            secondary: controls.dropFirst().first?.text ?? "Use the keys above to confirm or cancel.",
            width: width
        )
        return SetupChrome.render(header: header, body: body, footer: footer,
                                  width: width, height: height, indentBody: true)
    }
}
