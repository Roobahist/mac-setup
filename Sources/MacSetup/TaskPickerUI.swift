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
    private var reviewedWorkspaceSelection: Set<String>?
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
            case .enter:
                let relevant = workspaceSelectionSignature()
                if relevant.contains("aerospace-profile"),
                   reviewedWorkspaceSelection != relevant {
                    if try configureWorkspaces(in: terminal, automatic: true) {
                        reviewMode = true
                    }
                } else {
                    reviewMode = true
                }
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
                    _ = try configureWorkspaces(in: terminal, automatic: false)
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

    /// Reopen Step 2 only if the relevant app/profile choices have changed.
    /// This also ensures a user who already configured via W is not interrupted again.
    private func workspaceSelectionSignature() -> Set<String> {
        state.selected.intersection(["aerospace-profile", "sketchybar-profile", "tomito"])
    }

    @discardableResult
    private mutating func configureWorkspaces(in terminal: RawTerminal,
                                              automatic: Bool) throws -> Bool {
        let stored = try WorkspaceConfiguration.load(from: engine.paths)
        let filtered = stored.forSelectedTasks(state.selected)
        var editor = WorkspacePickerUI(
            layout: filtered,
            installed: ApplicationDiscovery.scan(home: engine.paths.home),
            context: automatic ? .setup : .standalone
        )
        switch editor.run(in: terminal) {
        case .saved(let changed):
            let merged = try stored.mergingVisible(changed, selectedTasks: state.selected)
            try merged.save(to: engine.paths)
            workspaceMessage = "Workspace settings saved for AeroSpace and SketchyBar."
        case .kept:
            workspaceMessage = "Existing workspace settings kept."
        case .cancelled:
            return false
        }
        reviewedWorkspaceSelection = workspaceSelectionSignature()
        return true
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
        let profile = state.preset?.title ?? "Custom"
        let step: SetupChrome.Step = reviewMode ? .review : .features
        let header = SetupChrome.header(
            step: step,
            summary: reviewMode ? "REVIEW SELECTION   |   \(state.selectedCount) selected tasks"
                                : "FEATURE SELECTION   |   \(state.selectedCount)/\(state.tasks.count) selected",
            context: "Profile: \(profile)   |   Category: \(state.category)",
            width: width
        )

        var body: [String] = []
        var detailTitle = ""
        var detailDescription = ""
        var detailStatus = ""
        var primary = ""
        var secondary = ""

        if reviewMode {
            body.append(tint("  REVIEW SELECTION", "1;38;5;81"))
            body.append("  \(state.selectedCount) tasks selected in the following categories:")
            body.append("")
            for category in state.categories.dropFirst() {
                let count = state.tasks.filter { $0.category == category && state.selected.contains($0.id) }.count
                if count > 0 { body.append("    [x] \(category): \(count)") }
            }
            detailTitle = "READY TO INSTALL"
            detailDescription = "Checked tasks will run with previews, confirmation and recovery where supported."
            detailStatus = "\(state.updates.count) installed task(s) marked for update."
            primary = "Enter Start setup   Esc / B Back to features   Q Cancel"
            secondary = "Review your choices before applying changes."
        } else if helpVisible {
            body.append(tint("  KEYBOARD HELP", "1;38;5;81"))
            for line in [
                "  Dependencies form an indented tree. Shared prerequisites stay visible.",
                "  Installed parents can remain unchecked while their children are selected.",
                "  Unchecking a missing parent also unchecks dependent tasks.",
                "  1-4 choose a preset. Space toggles the focused task.",
                "  Tab and Shift+Tab switch categories. / starts a text filter.",
                "  W opens workspace configuration; it also appears automatically before review.",
                "  A toggles visible tasks. Esc clears the current search.",
                "  Enter continues through workspace setup (if selected) and review.",
                "  Q and Ctrl+C cancel."
            ] { body.append(clip(line, to: width - 1)) }
            detailTitle = "KEYBOARD HELP"
            detailDescription = "Navigate the setup with your keyboard; no changes are applied here."
            detailStatus = "Press any key to return."
            primary = "Any key Back to features"
            secondary = "Nothing is installed until the review is confirmed."
        } else {
            body.append(tint("  INSTALLATION TASKS", "1;38;5;81"))
            body.append(tint("  1 Minimal   2 Productivity   3 Developer   4 Complete", "38;5;81"))
            if searchMode || !state.query.isEmpty {
                body.append(tint("  Search: \(state.query)" + (searchMode ? "▌" : ""), "1;38;5;81"))
            } else {
                body.append(tint("  Select features to install. Changes still require confirmation.", "38;5;245"))
            }

            let visible = state.visibleTasks
            var rows: [(index: Int?, guide: String)] = []
            for (index, task) in visible.enumerated() {
                rows.append((index, ""))
                if index + 1 < visible.count,
                   let spacer = state.hierarchySpacer(after: task, before: visible[index + 1]) {
                    rows.append((nil, spacer))
                }
            }
            let available = max(0, SetupChrome.bodyCapacity(height: height) - body.count)
            let focusedRow = rows.firstIndex { $0.index == state.cursorIndex } ?? 0
            let start = max(0, min(max(0, rows.count - available), focusedRow - available / 2))
            if visible.isEmpty {
                body.append(tint("  No matching tasks. Press Esc to clear the filter.", "38;5;221"))
            }
            for row in rows[start..<min(rows.count, start + available)] {
                guard let index = row.index else {
                    body.append(tint("       " + row.guide, "38;5;81"))
                    continue
                }
                let task = visible[index]
                let focused = index == state.cursorIndex
                let checked = state.selected.contains(task.id)
                let type = state.updates.contains(task.id) ? "UPDATE" : (task.guided ? "GUIDED" : "")
                let prefix = focused ? " ❯ " : "   "
                let marker = checked ? "[x]" : "[ ]"
                let tree = state.hierarchyPrefix(for: task)
                let bodyText = clip(prefix + marker + " " + tree + task.title, to: width - type.count - 5)
                let padding = String(repeating: " ", count: max(2, width - 3 - bodyText.count - type.count))
                if focused {
                    body.append(tint(bodyText + padding + type, "1;38;5;231;48;5;24"))
                } else {
                    let checkbox = tint(prefix + marker + " ", checked ? "38;5;252" : "38;5;245")
                    let guide = tint(tree, "38;5;81")
                    let label = String(bodyText.dropFirst((prefix + marker + " " + tree).count))
                    let style = !checked ? "38;5;245" : (tree.isEmpty ? "1;38;5;252" : "38;5;252")
                    body.append(checkbox + guide + tint(label, style) + padding +
                                tint(type, state.updates.contains(task.id) ? "38;5;221" : "38;5;245"))
                }
            }

            if let task = state.focusedTask {
                detailTitle = "\(task.title)  [\(taskStatus(task))]"
                detailDescription = task.summary
            } else {
                detailTitle = "INSTALLATION TASKS"
                detailDescription = "Choose a task or switch categories."
            }
            let inspected = statusLookup.snapshot.count
            detailStatus = workspaceMessage ?? (inspected < state.tasks.count
                ? "Checking installed tasks (\(inspected)/\(state.tasks.count)); selection changes unlock when finished."
                : "Inventory checked. Installed tasks are kept; U marks a package for update.")
            primary = "↑↓ Move   Space Toggle   W Workspaces   Tab Category   / Search   Enter Continue"
            secondary = "1-4 Presets   A Visible tasks   U Update   ? Help   Q Quit"
        }

        let footer = SetupChrome.footer(
            title: detailTitle,
            description: detailDescription,
            status: detailStatus,
            primary: primary,
            secondary: secondary,
            width: width
        )
        return SetupChrome.render(header: header, body: body, footer: footer,
                                  width: width, height: height)
    }
}
