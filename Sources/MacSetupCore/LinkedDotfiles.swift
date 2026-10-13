import Foundation

/// Portable configuration checkout. The URL and path can be injected for testing.
public struct DotfilesSource {
    public let remoteURL: String
    public let checkout: URL
    public let folders: [String]

    public init(
        home: URL,
        remoteURL: String = "https://github.com/Roobahist/dot-files.git",
        directoryName: String = "dot-files",
        folders: [String] = ["aerospace", "alacritty", "atuin", "karabiner", "sketchybar", "unsplash"]
    ) {
        self.remoteURL = remoteURL
        checkout = home.appendingPathComponent(directoryName)
        self.folders = folders
    }

    public func isLinked(_ name: String, config: URL) -> Bool {
        let location = config.appendingPathComponent(name)
        guard (try? FileManager.default.attributesOfItem(atPath: location.path)[.type] as? FileAttributeType) == .typeSymbolicLink else {
            return false
        }
        return location.resolvingSymlinksInPath().standardizedFileURL ==
            checkout.appendingPathComponent(name).standardizedFileURL
    }
}

public final class LinkedDotfiles {
    public let source: DotfilesSource
    private let paths: Paths
    private let runner: CommandRunning
    private let journal: Journal

    public init(paths: Paths, runner: CommandRunning, journal: Journal, source: DotfilesSource? = nil) {
        self.paths = paths
        self.runner = runner
        self.journal = journal
        self.source = source ?? DotfilesSource(home: paths.home)
    }

    public func status() -> TaskState {
        if !Journal.exists(source.checkout) { return .ready }
        guard checkoutIsDirectory(source.checkout), checkoutIsDirectory(source.checkout.appendingPathComponent(".git")) else {
            return .blocked
        }
        return source.folders.allSatisfy { source.isLinked($0, config: paths.config) } ? .done : .ready
    }

    public func install(transaction: String) throws {
        let destination = source.checkout
        let git = executable("git") ?? "/usr/bin/git"
        let cloned: URL?
        if Journal.exists(destination) {
            guard checkoutIsDirectory(destination), checkoutIsDirectory(destination.appendingPathComponent(".git")) else {
                throw SetupError("The dot-files checkout path already exists but is not a Git directory: \(destination.path)")
            }
            cloned = nil
        } else {
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("mac-setup-dotfiles-" + UUID().uuidString)
            cloned = staging
            try runner.checked(git, ["clone", "--depth", "1", "--", source.remoteURL, staging.path], interactive: true)
        }
        defer { if let cloned { try? FileManager.default.removeItem(at: cloned) } }
        let checkout = cloned ?? destination
        guard checkoutIsDirectory(checkout), checkoutIsDirectory(checkout.appendingPathComponent(".git")) else {
            throw SetupError("Dotfiles clone did not create a valid checkout.")
        }

        // An existing checkout must belong to the intended repository.
        if cloned == nil {
            let remote = try runner.checked(git, ["-C", checkout.path, "remote", "get-url", "origin"]).text
            let acceptable = [source.remoteURL,
                              "git@github.com:Roobahist/dot-files.git",
                              "https://github.com/Roobahist/dot-files"]
            guard acceptable.contains(remote) else {
                throw SetupError("Existing checkout points to another remote. Refusing to replace it.")
            }
        }

        for name in source.folders {
            guard checkoutIsDirectory(checkout.appendingPathComponent(name)) else {
                throw SetupError("Dotfiles checkout is missing configuration folder: \(name)")
            }
            let target = paths.config.appendingPathComponent(name)
            if isSymlink(target), !source.isLinked(name, config: paths.config) {
                throw SetupError("\(target.path) is linked to another checkout. Resolve this link manually before continuing.")
            }
        }

        if let cloned {
            try journal.replace(destination, with: cloned, transaction: transaction)
        }
        for name in source.folders where !source.isLinked(name, config: paths.config) {
            let target = paths.config.appendingPathComponent(name)
            let temporaryLink = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporaryLink) }
            try FileManager.default.createSymbolicLink(
                at: temporaryLink, withDestinationURL: destination.appendingPathComponent(name)
            )
            try journal.replace(target, with: temporaryLink, transaction: transaction)
        }
    }

    public func isSymlink(_ location: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: location.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private func checkoutIsDirectory(_ location: URL) -> Bool {
        guard !isSymlink(location) else { return false }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: location.path, isDirectory: &directory)
            && directory.boolValue
    }
}
