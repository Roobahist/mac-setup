import Foundation
import Darwin
import MacSetupCore

enum PickerKey {
    case up, down, tab, backTab, enter, space, escape, backspace, character(Character), interrupt, idle
}

/// Isolates terminal mode changes and restores the original configuration on every exit.
final class RawTerminal {
    private var saved: termios
    private var pendingByte: UInt8?

    init?() {
        guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else { return nil }
        var value = termios()
        guard tcgetattr(STDIN_FILENO, &value) == 0 else { return nil }
        saved = value
        var raw = value
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { return nil }
        write("\u{001B}[?1049h\u{001B}[?25l")
    }

    deinit {
        var value = saved
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &value)
        write("\u{001B}[?25h\u{001B}[?1049l")
    }

    func write(_ value: String) {
        FileHandle.standardOutput.write(Data(value.utf8))
    }

    private func readByte(_ timeout: Int32? = nil) -> UInt8? {
        if let byte = pendingByte { pendingByte = nil; return byte }
        if let timeout {
            var pending = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&pending, 1, timeout) > 0 else { return nil }
        }
        var byte: UInt8 = 0
        return Darwin.read(STDIN_FILENO, &byte, 1) == 1 ? byte : nil
    }

    func nextKey(timeout: Int32 = 100) -> PickerKey {
        guard let byte = readByte(timeout) else { return .idle }
        switch byte {
        case 3, 4: return .interrupt
        case 9: return .tab
        case 13, 10: return .enter
        case 32: return .space
        case 127, 8: return .backspace
        case 27:
            guard let prefix = readByte(120) else { return .escape }
            guard prefix == 91 || prefix == 79 else {
                pendingByte = prefix  // Preserve a key typed quickly after Escape.
                return .escape
            }

            // CSI: ESC [ A / B, ESC [ 1 ; modifier A / B.
            // SS3: ESC O A / B (application cursor-key mode).
            for _ in 0..<12 {
                guard let code = readByte(120) else { return .escape }
                // Intermediate parameters are ASCII 0x20-0x3F. A final byte
                // is 0x40-0x7E, regardless of modifier parameter length.
                guard code >= 0x40 && code <= 0x7E else { continue }
                switch code {
                case 65: return .up
                case 66: return .down
                case 90: return .backTab
                default: return .escape
                }
            }
            return .escape
        default:
            if byte >= 33 && byte <= 126,
               let scalar = UnicodeScalar(Int(byte)) {
                return .character(Character(scalar))
            }
            return .idle
        }
    }

    var dimensions: (width: Int, height: Int) {
        var window = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &window) == 0 {
            return (max(28, Int(window.ws_col)), max(14, Int(window.ws_row)))
        }
        return (80, 24)
    }
}

/// Runs potentially slow Homebrew and preferences checks outside the input loop.
/// Only the cached result is ever read by the renderer.
private final class TaskStatusLookup {
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "mac-setup.picker.status", qos: .utility)
    private var values: [String: String] = [:]
    private var submitted = Set<String>()
    private var generation = 0
    private var closed = false

    var revision: Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func status(for task: SetupTask, engine: Engine) -> String {
        lock.lock()
        if let value = values[task.id] {
            lock.unlock()
            return value
        }
        let enqueue = !closed && submitted.insert(task.id).inserted
        lock.unlock()
        if enqueue {
            worker.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let cancelled = self.closed
                self.lock.unlock()
                if cancelled { return }
                let value: String
                do { value = try engine.state(task).rawValue }
                catch { value = "Status unavailable" }
                self.lock.lock()
                if !self.closed {
                    self.values[task.id] = value
                    self.generation += 1
                }
                self.lock.unlock()
            }
        }
        return "Checking…"
    }

    func inspectAll(engine: Engine) {
        for task in Catalog.tasks { _ = status(for: task, engine: engine) }
    }

    var snapshot: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return values
    }

    func cancel() {
        lock.lock()
        closed = true
        lock.unlock()
    }

    /// Wait only when execution might mutate state. Cancel never blocks quitting.
    func finishBeforeApplying() {
        cancel()
        worker.sync {}
    }
}

/// Interactive picker is deliberately separate from the execution engine.
struct TaskPickerUI {
    private var state = TaskPickerState()
    private var searchMode = false
    private var helpVisible = false
    private var reviewMode = false
    private var workspaceMessage: String?
    private let statusLookup = TaskStatusLookup()
    private let engine: Engine
    private let colorEnabled: Bool

    init(engine: Engine) {
        self.engine = engine
        colorEnabled = ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && ProcessInfo.processInfo.environment["TERM"] != "dumb"
    }

    mutating func run() throws -> (ids: [String], updates: Set<String>)? {
        guard let terminal = RawTerminal() else {
            throw SetupError("Interactive selection requires a terminal. Use setup --preset complete, --all, or task IDs in scripts.")
        }
        defer { statusLookup.cancel() }
        statusLookup.inspectAll(engine: engine)
        var needsRedraw = true
        var lastRevision = -1
        while true {
            let inventory = statusLookup.snapshot
            state.available = Set(inventory.filter {
                [TaskState.done.rawValue, TaskState.confirmed.rawValue].contains($0.value)
            }.keys)
            state.unknown = Set(inventory.filter { $0.value == "Status unavailable" }.keys)
            let revision = statusLookup.revision
            if needsRedraw || revision != lastRevision {
                terminal.write(render(size: terminal.dimensions))
                lastRevision = statusLookup.revision
                needsRedraw = false
            }
            let key = terminal.nextKey()
            if case .idle = key { continue }
            needsRedraw = true
            if !searchMode && !helpVisible && inventory.count < state.tasks.count {
                switch key {
                case .space, .enter: continue
                case .character(let character) where character == "a" || character == "u": continue
                default: break
                }
            }
            if searchMode {
                switch key {
                case .enter: searchMode = false
                case .escape: searchMode = false; state.clearSearch()
                case .backspace: state.removeSearchCharacter()
                case let .character(character): state.appendSearch(character)
                case .interrupt: return nil
                default: break
                }
                continue
            }
            if helpVisible {
                if case .interrupt = key { return nil }
                helpVisible = false
                continue
            }
            if reviewMode {
                switch key {
                case .enter:
                    statusLookup.finishBeforeApplying()
                    return (state.orderedSelection, state.updates)
                case .escape: reviewMode = false
                case .interrupt: return nil
                case let .character(character):
                    if character == "b" { reviewMode = false }
                    if character == "q" { return nil }
                default: break
                }
                continue
            }
            switch key {
            case .up: state.move(-1)
            case .down: state.move(1)
            case .tab: state.cycleCategory()
            case .backTab: state.cycleCategory(-1)
            case .space: state.toggleFocused()
            case .backspace: state.removeSearchCharacter()
            case .escape: state.clearSearch()
            case .enter: reviewMode = true
            case .interrupt: return nil
            case .idle: continue
            case let .character(character):
                switch character {
                case "q": return nil
                case "j": state.move(1)
                case "k": state.move(-1)
                case "/": searchMode = true
                case "a": state.toggleVisible()
                case "u":
                    if let task = state.focusedTask, inventory[task.id] == TaskState.done.rawValue { state.toggleUpdate(task.id) }
                case "w":
                    var editor = WorkspacePickerUI(
                        layout: try WorkspaceConfiguration.load(from: engine.paths)
                            .forSelectedTasks(state.selected),
                        installed: ApplicationDiscovery.scan(home: engine.paths.home))
                    if let updated = editor.run(in: terminal) {
                        try updated.save(to: engine.paths)
                        workspaceMessage = "Workspace layout saved. The AeroSpace and SketchyBar profile tasks will apply it."
                    }
                case "?": helpVisible = true
                case "1": state.choose(.minimal)
                case "2": state.choose(.productivity)
                case "3": state.choose(.developer)
                case "4": state.choose(.complete)
                default: break
                }
            }
        }
    }

    private func taskStatus(_ task: SetupTask) -> String {
        statusLookup.status(for: task, engine: engine)
    }

    private func tint(_ text: String, _ code: String) -> String {
        colorEnabled ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
    }

    private func clip(_ text: String, to width: Int) -> String {
        let limit = max(5, width)
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    private mutating func render(size: (width: Int, height: Int)) -> String {
        let width = size.width
        let height = size.height
        let category = state.category
        let profile = state.preset?.title ?? "Custom"
        var lines: [String] = []
        lines.append(tint("  ◈  MAC SETUP", "1;38;5;255") + tint("   /   configure your Mac", "38;5;245"))
        lines.append(tint("  \(state.selectedCount)/\(state.tasks.count) selected", "1;38;5;81") +
                     tint("     Profile: \(profile)     Category: \(category)", "38;5;245"))
        lines.append(tint("  1 Minimal  2 Productivity  3 Developer  4 Complete", "38;5;81"))
        lines.append(tint("  ↑↓ Move  Space Toggle  W Workspaces  U Update  Tab Category  / Search  Enter Continue  Q Quit", "38;5;245"))
        lines.append("  " + String(repeating: "─", count: max(5, min(85, width - 4))))

        if reviewMode {
            lines.append(tint("  REVIEW SELECTION", "1;38;5;81"))
            lines.append("  \(state.selectedCount) tasks selected in the following categories:")
            for category in state.categories.dropFirst() {
                let count = state.tasks.filter { $0.category == category && state.selected.contains($0.id) }.count
                if count > 0 { lines.append("    [x] \(category): \(count)") }
            }
            lines.append("")
            lines.append("  Only checked tasks will run; installed unchecked parents satisfy dependencies.")
            lines.append("  \(state.updates.count) installed task(s) marked for update.")
            lines.append("  Each task still shows a preview and asks before making changes.")
            lines.append("  Existing settings are journaled for recovery; apps are not uninstalled.")
            lines.append(tint("  Enter: start setup   Esc / B: edit selection   Q: cancel", "1;36"))
        } else if helpVisible {
            lines.append("  HELP")
            for line in [
                "  Connected branches show children; shared requirements appear below.",
                "  Installed parents can stay unchecked while their children are selected.",
                "  Unchecking a missing parent also unchecks children that need it.",
                "  U toggles updates for an installed Homebrew or package task.",
                "  1-4 choose a preset. Space toggles the focused task.",
                "  Tab and Shift+Tab switch categories. / starts a text filter.",
                "  W opens the workspace editor (order, names, glyphs, app routing).",
                "  A toggles all visible tasks. Esc clears a filter.",
                "  Enter reviews the selected steps. Q and Ctrl+C cancel.",
                "  Press any key to return to the checklist."
            ] { lines.append(clip(line, to: width - 1)) }
        } else {
            if searchMode || !state.query.isEmpty {
                lines.append(tint("  Search: \(state.query)" + (searchMode ? "▌" : ""), "36"))
            } else {
                lines.append(tint("  Select features to install. Changes still require confirmation.", "2"))
            }

            let visible = state.visibleTasks
            let extraParentLines = max(0, (state.focusedTask?.dependencies.count ?? 0) - 1)
            let available = max(3, height - 14 - extraParentLines)
            var rows: [(index: Int?, guide: String)] = []
            for (index, task) in visible.enumerated() {
                rows.append((index, ""))
                if index + 1 < visible.count, let spacer = state.hierarchySpacer(after: task, before: visible[index + 1]) {
                    rows.append((nil, spacer))
                }
            }
            let focusedRow = rows.firstIndex { $0.index == state.cursorIndex } ?? 0
            let start = max(0, min(max(0, rows.count - available), focusedRow - available / 2))
            if visible.isEmpty {
                lines.append(tint("  No matching tasks. Press Esc to clear the filter.", "33"))
            }
            for row in rows[start..<min(rows.count, start + available)] {
                guard let index = row.index else {
                    lines.append(tint("       " + row.guide, "2;36"))
                    continue
                }
                let task = visible[index]
                let focused = index == state.cursorIndex
                let checked = state.selected.contains(task.id)
                let type = state.updates.contains(task.id) ? "UPDATE" : (task.guided ? "GUIDED" : "")
                let prefix = focused ? " ❯ " : "   "
                let marker = checked ? "[x]" : "[ ]"
                let tree = state.hierarchyPrefix(for: task)
                let body = clip(prefix + marker + " " + tree + task.title, to: width - type.count - 5)
                let padding = String(repeating: " ", count: max(2, width - 3 - body.count - type.count))
                if focused {
                    lines.append(tint(body + padding + type, "1;38;5;231;48;5;24"))
                } else {
                    let checkbox = tint(prefix + marker + " ", checked ? "0" : "2")
                    let guide = tint(tree, "2;36")
                    let label = String(body.dropFirst((prefix + marker + " " + tree).count))
                    let style = !checked ? "2" : (tree.isEmpty ? "1" : "0")
                    lines.append(checkbox + guide + tint(label, style) + padding + tint(type, state.updates.contains(task.id) ? "33" : "2"))
                }
            }

            lines.append("  " + String(repeating: "─", count: max(5, min(85, width - 4))))
            if let task = state.focusedTask {
                lines.append(tint("  \(task.title)", "1;38;5;81") +
                             tint("   [\(taskStatus(task))]", "2"))
                lines.append("  " + clip(task.summary, to: width - 4))
                if !task.dependencies.isEmpty {
                    for (index, parent) in task.dependencies.enumerated() {
                        let label = state.tasks.first { $0.id == parent }?.title ?? parent
                        let readiness = state.available.contains(parent) ? "installed/ready" : (state.unknown.contains(parent) ? "status unknown" : "not ready")
                        lines.append(tint((index == 0 ? "  Parents: " : "           ") + label + " [" + parent + "] — " + readiness, "2"))
                    }
                }
            } else {
                lines.append(tint("  Choose a task or switch categories.", "2"))
            }
            let inspected = statusLookup.snapshot.count
            lines.append(tint(inspected < state.tasks.count
                ? "  Checking installed tasks (\(inspected)/\(state.tasks.count)); selection changes unlock when finished."
                : "  Inventory checked. Installed tasks are kept; U marks a package for update.", "2"))
        }

        if let workspaceMessage { lines.append(tint("  " + workspaceMessage, "36")) }
        if lines.count > height { lines = Array(lines.prefix(height)) }
        let output = lines.map { clipANSIText($0, width: width) }.joined(separator: "\r\n")
        return "\u{001B}[H\u{001B}[2J" + output + "\r\n"
    }

    /// Truncate visible text without cutting ANSI color sequences in half.
    private func clipANSIText(_ value: String, width: Int) -> String {
        var rendered = ""
        var visible = 0
        var escape = false
        for scalar in value.unicodeScalars {
            if scalar == "\u{001B}" {
                escape = true
                rendered.append(String(scalar))
                continue
            }
            if escape {
                rendered.append(String(scalar))
                if scalar == "m" { escape = false }
                continue
            }
            if visible >= max(1, width - 1) { break }
            rendered.append(String(scalar))
            visible += 1
        }
        return rendered + "\u{001B}[0m"
    }
}
