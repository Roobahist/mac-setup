import AppKit

public struct DisplayMetrics: Codable, Equatable {
    public let name: String
    public let height: Int
    public let usableTopInset: Int
    public let notched: Bool
    public var gap: Int { max(0, height - usableTopInset) + 2 }

    public init(name: String, statusThickness: Double, safeTop: Double, visibleTopInset: Double = 0, menuAutoHides: Bool = true) {
        self.name = name
        notched = safeTop > 0
        height = max(1, Int(ceil(max(statusThickness, safeTop, menuAutoHides ? 0 : visibleTopInset))))
        usableTopInset = max(0, Int(ceil(max(safeTop, menuAutoHides ? 0 : visibleTopInset))))
    }
}

public struct DisplayGeometry: Codable, Equatable {
    public let displays: [DisplayMetrics]
    public let baseHeight: Int
    public var notchHeight: Int { displays.filter(\.notched).map(\.height).max() ?? 0 }
    public var previewHeight: Int { displays.first?.height ?? baseHeight }
    public static let marker = "# mac-setup: adaptive top gap"

    public init(displays: [DisplayMetrics], fallbackHeight: Int = 22) {
        self.displays = displays
        baseHeight = displays.filter { !$0.notched }.map(\.height).max() ?? fallbackHeight
    }

    public static func current() -> DisplayGeometry {
        let thickness = NSStatusBar.system.thickness
        let hides = UserDefaults.standard.object(forKey: "_HIHideMenuBar") as? Bool ?? false
        let displays = NSScreen.screens.map { screen in
            DisplayMetrics(name: screen.localizedName, statusThickness: thickness,
                           safeTop: screen.safeAreaInsets.top,
                           visibleTopInset: screen.frame.maxY - screen.visibleFrame.maxY,
                           menuAutoHides: hides)
        }
        return DisplayGeometry(displays: displays, fallbackHeight: max(1, Int(ceil(thickness))))
    }

    public var gapLine: String {
        let entries = displays.map { display in
            let pattern = "^" + NSRegularExpression.escapedPattern(for: display.name) + "$"
            let escaped = pattern.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "{ monitor.\"\(escaped)\" = \(display.gap) }"
        }
        let value = entries.isEmpty ? String(baseHeight + 2) : "[" + (entries + [String(baseHeight + 2)]).joined(separator: ", ") + "]"
        return "outer.top = \(value) \(Self.marker)"
    }

    public func applying(to source: String) -> String {
        source.components(separatedBy: "\n").map { line in
            line.range(of: "^outer\\.top\\s*=", options: .regularExpression) != nil ? gapLine : line
        }.joined(separator: "\n")
    }

    public static func barShell(_ source: String) -> String {
        var result = source
        let header = """
        # AppKit supplies logical point heights for this host and its notch.
        BAR_HEIGHT=22
        NOTCH_HEIGHT=0
        if [ -x "$PLUGIN_DIR/mac-setup-display" ]; then
          read -r BAR_HEIGHT NOTCH_HEIGHT < <("$PLUGIN_DIR/mac-setup-display" sizes)
        fi
        """
        if !result.contains("# AppKit supplies logical point heights") {
            result = result.replacingOccurrences(of: "source \"$PLUGIN_DIR/colors.sh\"", with: "source \"$PLUGIN_DIR/colors.sh\"\n" + header)
        }
        result = result.components(separatedBy: "\n").map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("height=") { return "  height=\"$BAR_HEIGHT\" \\" }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("topmost=") { return "  topmost=window \\" }
            return line
        }.joined(separator: "\n")
        if !result.contains("notch_display_height=") {
            result = result.replacingOccurrences(of: "  height=\"$BAR_HEIGHT\" \\", with: "  height=\"$BAR_HEIGHT\" \\\n  notch_display_height=\"$NOTCH_HEIGHT\" \\\n  y_offset=0 \\\n  notch_offset=0 \\\n  margin=0 \\")
        }
        if !result.contains("##### Host Display Geometry #####") {
            result += """

            ##### Host Display Geometry #####
            sketchybar --add item display_geometry left \\
              --set display_geometry drawing=off updates=on update_freq=0 \\
                script="/bin/bash '$PLUGIN_DIR/geometry.sh'" \\
              --subscribe display_geometry display_change system_woke
            if [ -x "$PLUGIN_DIR/mac-setup-display" ]; then
              /bin/bash "$PLUGIN_DIR/geometry.sh"
            fi

            """
        }
        return result
    }

    /// Only the generated geometry line is runtime-owned. Other edits remain protected.
    public static func stableConfiguration(_ data: Data) -> Data {
        let source = String(decoding: data, as: UTF8.self)
        let stable = source.components(separatedBy: "\n").map { line in
            line.hasPrefix("outer.top = ") && line.hasSuffix(marker) ? "outer.top = adaptive \(marker)" : line
        }.joined(separator: "\n")
        return Data(stable.utf8)
    }
}

public enum AppResources {
    public static var iconURL: URL? {
        Bundle.main.url(forResource: "MacSetup", withExtension: "icns")
            ?? Bundle.module.url(forResource: "MacSetup", withExtension: "icns")
    }

    public static var displayHelperURL: URL? {
        let app = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/mac-setup-display")
        let cli = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().appendingPathComponent("mac-setup-display")
        return [app, cli].first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
