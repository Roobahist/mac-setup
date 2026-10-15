import Foundation

/// Compares the running SketchyBar item order with the intended configuration.
/// AeroSpace's list-workspaces command is sorted by workspace name rather than
/// persistent-workspaces order, so it must not be used as an ordering oracle.
public enum WorkspaceRuntimeVerification {
    public static func sketchyBarWorkspaceIDs(from data: Data) throws -> [String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [String] else {
            throw SetupError("SketchyBar returned a bar query without an items array.")
        }
        return items.compactMap { item in
            item.hasPrefix("space.") ? String(item.dropFirst("space.".count)) : nil
        }
    }

    public static func sketchyBarOrderIssue(query: Data, expectedIDs: [String]) -> String? {
        do {
            let actual = try sketchyBarWorkspaceIDs(from: query)
            guard actual == expectedIDs else {
                return "SketchyBar is showing a different workspace order. Expected: "
                    + expectedIDs.joined(separator: ", ") + ". Active: "
                    + actual.joined(separator: ", ") + ". Reload SketchyBar and inspect its logs."
            }
            return nil
        } catch {
            return "Could not verify SketchyBar's active workspace order: \(error)"
        }
    }

    public static func missingAeroSpaceIDs(output: String, expectedIDs: [String]) -> [String] {
        let running = Set(output.split(whereSeparator: \.isNewline).map(String.init))
        return expectedIDs.filter { !running.contains($0) }
    }
}
