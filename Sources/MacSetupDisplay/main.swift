import Foundation
import MacSetupCore

// This small helper ships as a binary; end users do not need Swift or Xcode.
do {
    let geometry = DisplayGeometry.current()
    switch CommandLine.arguments.dropFirst().first ?? "json" {
    case "json":
        print(String(decoding: try JSONEncoder().encode(geometry), as: UTF8.self))
    case "sizes":
        guard !geometry.displays.isEmpty else { throw SetupError("No display measurements are available.") }
        print("\(geometry.baseHeight) \(geometry.notchHeight)")
    case "refresh":
        guard let sketchybar = executable("sketchybar") else { throw SetupError("SketchyBar is not installed.") }
        let runner = ProcessRunner()
        guard CommandLine.arguments.count == 3 else { throw SetupError("Pass the generated AeroSpace config path.") }
        try geometry.refresh(config: URL(fileURLWithPath: CommandLine.arguments[2]), runner: runner,
                             sketchybar: sketchybar, aerospace: executable("aerospace"))
    default: throw SetupError("Use json, sizes, or refresh with a generated config path.")
    }
} catch { fputs("Display geometry: \(error)\n", stderr); exit(1) }
