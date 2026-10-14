import Foundation
import Darwin

/// Common screen shell for every step in the interactive setup.
enum SetupChrome {
    enum Step {
        case features, workspaces, review

        var label: String {
            switch self {
            case .features: return "Features"
            case .workspaces: return "Workspaces"
            case .review: return "Review"
            }
        }
    }

    private static var colorEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["NO_COLOR"] == nil && environment["TERM"] != "dumb"
    }

    static func tint(_ value: String, _ code: String) -> String {
        colorEnabled ? "\u{001B}[\(code)m\(value)\u{001B}[0m" : value
    }

    static func rule(width: Int) -> String {
        "  " + String(repeating: "─", count: min(100, max(5, width - 4)))
    }

    static func header(step: Step, summary: String, context: String, width: Int) -> [String] {
        let steps: [Step] = [.features, .workspaces, .review]
        var navigation = tint("  ◈  MAC SETUP", "1;38;5;255") + tint("    /    ", "38;5;245")
        for (index, candidate) in steps.enumerated() {
            if index > 0 { navigation += tint("   ›   ", "38;5;245") }
            navigation += tint("\(index + 1) \(candidate.label)",
                               candidate == step ? "1;38;5;81" : "38;5;245")
        }
        return [
            navigation,
            tint("  " + summary, "1;38;5;81"),
            tint("  " + context, "38;5;245"),
            rule(width: width),
            ""
        ]
    }

    /// Each screen reserves the same footer lines regardless of its content.
    /// Details and keyboard hints therefore never jump when switching steps.
    static let footerHeight = 7
    static let headerHeight = 5

    static func bodyCapacity(height: Int) -> Int {
        max(0, height - 1 - headerHeight - footerHeight)
    }

    static func footer(title: String, description: String, status: String,
                       primary: String, secondary: String, width: Int) -> [String] {
        [
            rule(width: width),
            tint("  " + title, "1;38;5;81"),
            tint("  " + description, "38;5;252"),
            tint("  " + status, "38;5;245"),
            rule(width: width),
            tint("  " + primary, "1;38;5;81"),
            tint("  " + secondary, "38;5;245")
        ]
    }

    /// Render at most height - 1 rows to avoid a final CRLF scrolling the
    /// alternate screen and making its navigation header disappear.
    static func render(header: [String], body: [String], footer: [String],
                       width: Int, height: Int, indentBody: Bool = false) -> String {
        let safeHeight = max(1, height - 1)
        let headerLines = Array(header.prefix(safeHeight))
        let footerLines = Array(footer.prefix(max(0, safeHeight - headerLines.count)))
        let bodyLimit = max(0, safeHeight - headerLines.count - footerLines.count)
        var rows = headerLines
        rows += body.prefix(bodyLimit).map { indentBody ? "  " + $0 : $0 }
        while rows.count < safeHeight - footerLines.count { rows.append("") }
        rows += footerLines

        // Clip only after composing the screen, preserving ANSI escapes and
        // counting terminal cells rather than Swift string characters.
        let output = rows.map { clipANSI($0, width: width) }.joined(separator: "\r\n")
        return "\u{001B}[H\u{001B}[2J" + output
    }

    private static func clipANSI(_ text: String, width: Int) -> String {
        let scalars = Array(text.unicodeScalars)
        let limit = max(1, width - 1)
        var result = ""
        var index = 0
        var occupied = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\u{001B}", index + 1 < scalars.count {
                let next = scalars[index + 1]
                if next == "[" {
                    var end = index + 2
                    while end < scalars.count && !(64...126).contains(Int(scalars[end].value)) {
                        end += 1
                    }
                    if end < scalars.count {
                        result.unicodeScalars.append(contentsOf: scalars[index...end])
                        index = end + 1
                        continue
                    }
                } else if next == "7" || next == "8" {
                    result.unicodeScalars.append(contentsOf: scalars[index...index + 1])
                    index += 2
                    continue
                }
            }
            let cellWidth = max(0, Int(Darwin.wcwidth(Int32(scalar.value))))
            if occupied + cellWidth > limit { break }
            result.unicodeScalars.append(scalar)
            occupied += cellWidth
            index += 1
        }
        return result + "\u{001B}[0m"
    }
}
