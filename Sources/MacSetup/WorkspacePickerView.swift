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
    let width: Int
    let height: Int

    private enum Tone {
        case normal, muted, accent, title, selected, success, caution, danger
    }

    private struct Line {
        let text: String
        let tone: Tone
        init(_ text: String = "", _ tone: Tone = .normal) {
            self.text = text
            self.tone = tone
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

    private func styled(_ line: Line, width: Int, padded: Bool = false) -> String {
        color(fit(line.text, to: width, padded: padded), line.tone)
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

    private func tableRow(_ index: Int, width: Int, includeID: Bool) -> Line {
        let ws = layout.workspaces[index]
        let highlighted = index == selected
        let keyWidth = 9
        let glyphWidth = width >= 63 ? 13 : 10
        let appsWidth = 5
        let idWidth = includeID ? min(20, max(12, width / 4)) : 0
        let fixed = 3 + keyWidth + 2 + glyphWidth + 2 + appsWidth + (includeID ? 2 + idWidth : 0)
        let nameWidth = max(7, width - fixed)
        let text = " \(highlighted ? ">" : " ") "
            + fit(shortcut(at: index), to: keyWidth, padded: true) + "  "
            + fit(ws.name, to: nameWidth, padded: true) + "  "
            + fit(ws.glyph, to: glyphWidth, padded: true)
            + (includeID ? "  " + fit(ws.id, to: idWidth, padded: true) : "")
            + "  " + fit(String(ws.apps.count), to: appsWidth, padded: true)
        return Line(fit(text, to: width, padded: true), highlighted ? .selected : .normal)
    }

    private func tableHeading(width: Int, includeID: Bool) -> Line {
        let keyWidth = 9
        let glyphWidth = width >= 63 ? 13 : 10
        let appsWidth = 5
        let idWidth = includeID ? min(20, max(12, width / 4)) : 0
        let fixed = 3 + keyWidth + 2 + glyphWidth + 2 + appsWidth + (includeID ? 2 + idWidth : 0)
        let nameWidth = max(7, width - fixed)
        let text = "   "
            + fit("SHORTCUT", to: keyWidth, padded: true) + "  "
            + fit("NAME", to: nameWidth, padded: true) + "  "
            + fit("GLYPH", to: glyphWidth, padded: true)
            + (includeID ? "  " + fit("ID", to: idWidth, padded: true) : "")
            + "  " + fit("APPS", to: appsWidth, padded: true)
        return Line(text, .accent)
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
            Line("  \(workspace.glyph)", .normal),
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
        let listHeight = max(3, height - (wide ? 12 : 18))
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
                + styled(r, width: rightWidth)
        }
    }

    private func glyphRows() -> [Line] {
        let matches = WorkspaceGlyph.matching(query)
        var lines: [Line] = [
            Line("GLYPH LIBRARY   /   \(workspace.name)", .accent),
            Line("Type to filter glyph names and keywords", .muted),
            Line("Search: \(query)\(useColor ? "▌" : "_")    \(matches.count) matches", .title),
            Line(),
            Line("   GLYPH NAME            KEYWORDS / DESCRIPTION", .accent)
        ]
        let pageRows = max(3, height - 15)
        for index in selectionRange(total: matches.count, limit: pageRows, cursor: resultCursor) {
            let glyph = matches[index]
            let label = fit(glyph.name, to: 20, padded: true)
            let text = " \(index == resultCursor ? ">" : " ") " + label
                + "  " + glyph.keywords
            lines.append(Line(text, index == resultCursor ? .selected : .normal))
        }
        if matches.isEmpty { lines.append(Line("  No matching glyphs. Try another keyword.", .caution)) }
        if let candidate = matches.indices.contains(resultCursor) ? matches[resultCursor] : nil {
            lines += [
                Line(),
                Line("SELECTED GLYPH", .accent),
                Line("  Name: \(candidate.name)    Code point: U+\(String(candidate.symbol.unicodeScalars.first!.value, radix: 16).uppercased())", .normal),
                Line("  Preview: \(candidate.symbol)   (requires Nerd Font in your terminal)", .muted)
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
        let bundleWidth = max(10, usable - appWidth - ownerWidth - 9)
        var lines: [Line] = [
            Line("APP ROUTING   /   \(workspace.name)", .accent),
            Line("Type to filter installed apps or bundle IDs", .muted),
            Line("Search: \(query)\(useColor ? "▌" : "_")   \(matches.count) results   ·   \(installed.count) installed apps found", .title),
            Line(),
            Line("    " + fit("APPLICATION", to: appWidth, padded: true) + "  "
                 + fit("BUNDLE ID", to: bundleWidth, padded: true) + "  "
                 + "ASSIGNED TO", .accent)
        ]
        let pageRows = max(3, height - 13)
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
                Line("S Save  ·  Q Cancel     Changes are saved locally; apply AeroSpace / SketchyBar profiles afterward.", .muted)
            ]
        case .glyphs:
            return [Line("↑↓ Select     Enter Use glyph     Type to search     Esc Clear search / Back", .accent),
                    Line("Glyph previews need a Nerd Font terminal. Names remain readable without it.", .muted)]
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
        var output: [String] = [
            styled(Line("WORKSPACE EDITOR    /    mac-setup", .title), width: availableWidth),
            styled(Line("\(layout.workspaces.count) of \(WorkspaceConfiguration.keys.count) workspace slots    |    \(saveState)", modified ? .caution : .muted), width: availableWidth),
            styled(divider(), width: availableWidth),
            ""
        ]

        let body: [String]
        switch page {
        case .workspaces: body = tableAndInspector()
        case .glyphs: body = glyphRows().map { styled($0, width: availableWidth) }
        case .apps: body = appRows().map { styled($0, width: availableWidth) }
        case .editID, .editName, .manualApp: body = promptRows().map { styled($0, width: availableWidth) }
        case .confirmDelete, .confirmCancel: body = warningRows().map { styled($0, width: availableWidth) }
        }
        let footers = shortcuts().map { styled($0, width: availableWidth) }
        let status = message.isEmpty ? "" : styled(Line(message, .caution), width: availableWidth)
        let bodySpace = max(0, height - output.count - footers.count - 3)
        output += Array(body.prefix(bodySpace))
        while output.count < height - footers.count - 3 { output.append("") }
        output += [styled(divider(), width: availableWidth), status] + footers
        if output.count > height { output = Array(output.prefix(height)) }
        // Prefix lines are limited in terminal cells before styling, so ANSI
        // sequences can never be sliced or leave the next redraw colored.
        return "\u{001B}[H\u{001B}[2J" + output.map { "  " + $0 }.joined(separator: "\r\n") + "\r\n"
    }
}
