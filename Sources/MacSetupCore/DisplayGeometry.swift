import AppKit

public struct DisplayMetrics: Codable, Equatable {
    public let name: String
    public let height: Int
    public let usableTopInset: Int
    public let notched: Bool
    public var gap: Int { max(0, height - usableTopInset) + 2 }

    public init(name: String, statusThickness: Double, safeTop: Double, visibleTopInset: Double = 0, menuAutoHides: Bool = true, menuBarHeight: Double? = nil) {
        self.name = name
        notched = safeTop > 0
        height = max(1, Int(ceil(max(menuBarHeight ?? statusThickness, safeTop, menuAutoHides ? 0 : visibleTopInset))))
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
        // The terminal picker blocks its main thread for input. Do not dispatch
        // synchronously to it from inventory/apply workers; the helper owns its
        // own AppKit main thread and is also used by the generated bar scripts.
        if !Thread.isMainThread {
            if let helper = AppResources.displayHelperURL,
               let result = try? ProcessRunner().runTimed(helper.path, ["json"], timeout: 5),
               result.status == 0,
               let geometry = try? JSONDecoder().decode(Self.self, from: result.output) {
                return geometry
            }
            return DisplayGeometry(displays: [], fallbackHeight: 30)
        }
        let thickness = NSStatusBar.system.thickness
        if NSApp == nil {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
        }
        if NSApp.mainMenu == nil { NSApp.mainMenu = NSMenu(title: "") }
        let menuHeight = NSApp.mainMenu?.menuBarHeight ?? thickness
        let hides = UserDefaults.standard.object(forKey: "_HIHideMenuBar") as? Bool ?? false
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let displays = NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let bounds = number.map { CGDisplayBounds($0.uint32Value) } ?? .zero
            // Window bounds are logical points, including auto-hidden menu bars.
            // Each display can have a different menu height at its current scaling.
            let actualHeight = windows.compactMap { window -> Double? in
                guard (window[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)),
                      let raw = window[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: raw),
                      abs(frame.minX - bounds.minX) < 1,
                      abs(frame.width - bounds.width) < 1,
                      abs(frame.minY - bounds.minY) <= frame.height,
                      (16...128).contains(frame.height) else { return nil }
                return frame.height
            }.first ?? menuHeight
            return DisplayMetrics(name: screen.localizedName, statusThickness: thickness,
                                  safeTop: screen.safeAreaInsets.top,
                                  visibleTopInset: screen.frame.maxY - screen.visibleFrame.maxY,
                                  menuAutoHides: hides, menuBarHeight: actualHeight)
        }
        return DisplayGeometry(displays: displays, fallbackHeight: max(1, Int(ceil(menuHeight))))
    }

    /// Enforce the whole bar even when AeroSpace's gap already matches.
    public func refresh(config: URL, runner: CommandRunning, sketchybar: String, aerospace: String?) throws {
        guard !displays.isEmpty else { throw SetupError("No display measurements are available; bar height was preserved.") }
        // The generated sketchybarrc sets topmost=window at startup. Reasserting it
        // on every wake/display event unconditionally recreates all SketchyBar windows.
        try runner.checked(sketchybar, ["--bar", "height=\(baseHeight)", "notch_display_height=\(notchHeight)",
                                       "y_offset=0", "notch_offset=0", "margin=0"])
        var item = config
        while item.path != "/" {
            if (try? FileManager.default.attributesOfItem(atPath: item.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                throw SetupError("Adaptive geometry will not edit a symlink: \(item.path)")
            }
            item.deleteLastPathComponent()
        }
        let old = try String(contentsOf: config, encoding: .utf8)
        guard old.components(separatedBy: "\n").contains(where: { $0.hasPrefix("outer.top = ") && $0.hasSuffix(Self.marker) }) else { return }
        let updated = applying(to: old)
        guard updated != old else { return }
        try updated.write(to: config, atomically: true, encoding: .utf8)
        if let aerospace, try runner.run(aerospace, ["list-workspaces", "--all"]).status == 0 {
            try runner.checked(aerospace, ["reload-config"])
        }
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
        let referenceHeight = source.components(separatedBy: "\n").compactMap { line -> Int? in
            let text = line.trimmingCharacters(in: .whitespaces)
            let prefix = text.hasPrefix("height=") ? "height=" : "BAR_HEIGHT="
            guard text.hasPrefix(prefix) else { return nil }
            return Int(text.dropFirst(prefix.count).prefix(while: { $0.isNumber }))
        }.first ?? 30
        let header = """
        # AppKit supplies logical point heights for this host and its notch.
        BAR_HEIGHT=\(referenceHeight)
        NOTCH_HEIGHT=0
        if [ -x "$PLUGIN_DIR/mac-setup-display" ]; then
          if read -r measured_height measured_notch < <("$PLUGIN_DIR/mac-setup-display" sizes) &&
             [[ "$measured_height" =~ ^[1-9][0-9]*$ && "$measured_notch" =~ ^[0-9]+$ ]]; then
            BAR_HEIGHT="$measured_height"
            NOTCH_HEIGHT="$measured_notch"
          fi
        fi
        """
        if let start = result.range(of: "# AppKit supplies logical point heights"),
           let end = result.range(of: "\nfi", range: start.lowerBound..<result.endIndex) {
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: header)
        } else {
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
