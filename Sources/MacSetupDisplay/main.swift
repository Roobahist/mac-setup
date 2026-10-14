import Foundation
import MacSetupCore

// This small helper ships as a binary; end users do not need Swift or Xcode.
do {
    let geometry = DisplayGeometry.current()
    switch CommandLine.arguments.dropFirst().first ?? "json" {
    case "json":
        print(String(decoding: try JSONEncoder().encode(geometry), as: UTF8.self))
    case "sizes": print("\(geometry.baseHeight) \(geometry.notchHeight)")
    case "refresh":
        guard let sketchybar = executable("sketchybar") else { throw SetupError("SketchyBar is not installed.") }
        let runner = ProcessRunner()
        try runner.checked(sketchybar, ["--bar", "height=\(geometry.baseHeight)", "notch_display_height=\(geometry.notchHeight)", "topmost=window", "y_offset=0", "notch_offset=0", "margin=0"])
        guard CommandLine.arguments.count == 3 else { throw SetupError("Pass the generated AeroSpace config path.") }
        let config = URL(fileURLWithPath: CommandLine.arguments[2])
        // Never change a symlink or an unmarked personal/public configuration.
        var item = config
        while item.path != "/" {
            if (try? FileManager.default.attributesOfItem(atPath: item.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                throw SetupError("Adaptive geometry will not edit a symlink: \(item.path)")
            }
            item.deleteLastPathComponent()
        }
        let old = try String(contentsOf: config, encoding: .utf8)
        guard old.components(separatedBy: "\n").contains(where: { $0.hasPrefix("outer.top = ") && $0.hasSuffix(DisplayGeometry.marker) }) else { exit(0) }
        let updated = geometry.applying(to: old)
        if updated != old {
            try updated.write(to: config, atomically: true, encoding: .utf8)
            if let aerospace = executable("aerospace") {
                let running = try runner.run(aerospace, ["list-workspaces", "--all"])
                if running.status == 0 { try runner.checked(aerospace, ["reload-config"]) }
            }
        }
    default: throw SetupError("Use json, sizes, or refresh with a generated config path.")
    }
} catch { fputs("Display geometry: \(error)\n", stderr); exit(1) }
