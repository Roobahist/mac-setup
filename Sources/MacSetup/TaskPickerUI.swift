import Foundation
import Darwin
import MacSetupCore

private enum PickerKey {
    case up, down, tab, backTab, enter, space, escape, backspace, character(Character), interrupt
}

/// Isolates terminal mode changes and restores the original configuration on every exit.
private final class RawTerminal {
    private var saved: termios

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
        if let timeout {
            var pending = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&pending, 1, timeout) > 0 else { return nil }
        }
        var byte: UInt8 = 0
        return Darwin.read(STDIN_FILENO, &byte, 1) == 1 ? byte : nil
    }

    func nextKey() -> PickerKey {
        guard let byte = readByte() else { return .interrupt }
        switch byte {
        case 3, 4: return .interrupt
        case 9: return .tab
        case 13, 10: return .enter
        case 32: return .space
        case 127, 8: return .backspace
        case 27:
            guard let prefix = readByte(50) else { return .escape }
            if prefix == 91, let code = readByte(50) {
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
            return .escape
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

/// Interactive picker is deliberately separate from the execution engine.
struct TaskPickerUI {
    private var state = TaskPickerState()
    private var searchMode = false
    private var helpVisible = false
    private var reviewMode = false
    private var statusCache: [String: String] = [:]
    private let engine: Engine
    private let colorEnabled: Bool

    init(engine: Engine) {
        self.engine = engine
        colorEnabled = ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && ProcessInfo.processInfo.environment["TERM"] != "dumb"
    }

    mutating func run() throws -> [String]? {
        guard let terminal = RawTerminal() else {
            throw SetupError("Interactive selection requires a terminal. Use setup --preset complete, --all, or task IDs in scripts.")
        }
        while true {
            terminal.write(render(size: terminal.dimensions))
            let key = terminal.nextKey()
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
                case .enter: reviewMode = true
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
            case .enter: return state.orderedSelection
            case .interrupt: return nil
            case let .character(character):
                switch character {
                case "q": return nil
                case "j": state.move(1)
                case "k": state.move(-1)
                case "/": searchMode = true
                case "a": state.toggleVisible()
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

    private mutating func taskStatus(_ task: SetupTask) -> String {
        if let cached = statusCache[task.id] { return cached }
        let result: String
        do { result = try engine.state(task).rawValue }
        catch { result = "Could not inspect: \(error)" }
        statusCache[task.id] = result
        return result
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
        lines.append(tint("  ◈  MAC SETUP", "1;36") + tint("   /   configure your Mac", "2"))
        lines.append(tint("  \(state.selectedCount)/\(state.tasks.count) selected", "1") +
                     tint("     Profile: \(profile)     Category: \(category)", "2"))
        lines.append(tint("  1 Minimal  2 Productivity  3 Developer  4 Complete", "36"))
        lines.append(tint("  ↑↓ Move  Space Toggle  Tab Category  / Search  A All  Enter Continue  Q Quit", "2"))
        lines.append("  " + String(repeating: "─", count: max(5, min(85, width - 4))))

        if reviewMode {
            lines.append(tint("  REVIEW SELECTION", "1;36"))
            lines.append("  \(state.selectedCount) tasks selected in the following categories:")
            for category in state.categories.dropFirst() {
                let count = state.tasks.filter { $0.category == category && state.selected.contains($0.id) }.count
                if count > 0 { lines.append("    [x] \(category): \(count)") }
            }
            lines.append("")
            lines.append("  Each task still shows a preview and asks before making changes.")
            lines.append("  Existing settings are journaled for recovery; apps are not uninstalled.")
            lines.append(tint("  Enter: start setup   Esc / B: edit selection   Q: cancel", "1;36"))
        } else if helpVisible {
            lines.append("  HELP")
            for line in [
                "  Pick any combination of tasks. Dependencies are selected automatically.",
                "  Turning a prerequisite off also deselects tasks that require it.",
                "  1-4 choose a preset. Space toggles the focused task.",
                "  Tab and Shift+Tab switch categories. / starts a text filter.",
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
            let available = max(3, height - 14)
            let start = max(0, min(max(0, visible.count - available), state.cursorIndex - available / 2))
            if visible.isEmpty {
                lines.append(tint("  No matching tasks. Press Esc to clear the filter.", "33"))
            }
            for index in start..<min(visible.count, start + available) {
                let task = visible[index]
                let focused = index == state.cursorIndex
                let checked = state.selected.contains(task.id)
                let type = ["wallpaper-watcher", "dock-special-items"].contains(task.id)
                    ? "PENDING" : (task.guided ? "GUIDED " : "AUTO   ")
                let prefix = focused ? " ❯ " : "   "
                let marker = checked ? "[x]" : "[ ]"
                let title = clip(prefix + marker + "  " + task.title +
                                 "  " + type, to: width - 2)
                lines.append(focused ? tint(title, "1;46;30") : (checked ? title : tint(title, "2")))
            }

            lines.append("  " + String(repeating: "─", count: max(5, min(85, width - 4))))
            if let task = state.focusedTask {
                lines.append(tint("  \(task.title)", "1;36") +
                             tint("   [\(taskStatus(task))]", "2"))
                lines.append("  " + clip(task.summary, to: width - 4))
                if !task.dependencies.isEmpty {
                    lines.append(tint("  Needs: " + task.dependencies.joined(separator: ", "), "2"))
                }
            } else {
                lines.append(tint("  Choose a task or switch categories.", "2"))
            }
            lines.append(tint("  Dependencies are included. Existing tasks are checked before applying.", "2"))
        }

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
