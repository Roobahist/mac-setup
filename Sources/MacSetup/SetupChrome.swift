import Foundation

/// Shared visual language for the feature checklist, workspace editor and review.
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

    static func tint(_ text: String, _ code: String) -> String {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NO_COLOR"] == nil, environment["TERM"] != "dumb" else { return text }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
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
}
