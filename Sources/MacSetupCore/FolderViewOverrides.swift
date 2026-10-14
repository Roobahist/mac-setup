import Foundation

/// Find Finder's per-folder override files without entering symlinks, application
/// bundles, hidden directories, or Library. Deletion is handled by Journal.
public enum FolderViewOverrides {
    public static func discover(in roots: [URL], maximumFiles: Int = 10_000,
                                fileManager: FileManager = .default) throws -> [URL] {
        guard maximumFiles > 0 else { throw SetupError("Maximum file count must be positive.") }
        var found: [URL] = []
        var visited = Set<String>()
        let packageExtensions: Set<String> = ["app", "bundle", "framework", "photoslibrary", "library",
                                               "aplibrary", "pkg", "plugin", "appex", "xcodeproj", "xcworkspace"]
        func walk(_ directory: URL) throws {
            let path = directory.standardizedFileURL.path
            guard visited.insert(path).inserted else { return }
            let entries = try fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
                options: [])
            for entry in entries {
                let info = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard info.isSymbolicLink != true else { continue }
                if entry.lastPathComponent == ".DS_Store" {
                    found.append(entry)
                    if found.count > maximumFiles {
                        throw SetupError("Too many Finder override files (more than \(maximumFiles)). Narrow the selected folders.")
                    }
                } else if info.isDirectory == true {
                    guard !entry.lastPathComponent.hasPrefix("."),
                          !packageExtensions.contains(entry.pathExtension.lowercased()) else { continue }
                    try walk(entry)
                }
            }
        }
        for root in roots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            let info = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else { continue }
            try walk(root)
        }
        return found.sorted { $0.path < $1.path }
    }
}
