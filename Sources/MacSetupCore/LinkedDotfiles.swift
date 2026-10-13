import Foundation

/// Location and allowlist for the portable configuration repository.
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

/// Clones and updates the canonical source, and creates selected config links with journaled rollback.
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
        return checkoutIsDirectory(source.checkout) &&
            checkoutIsDirectory(source.checkout.appendingPathComponent(".git")) ? .done : .blocked
    }

    public func install(transaction: String) throws {
        let destination = source.checkout
        if Journal.exists(destination) {
            guard status() == .done else {
                throw SetupError("The dot-files path exists but is not a valid Git checkout: \(destination.path)")
            }
            try verifyRemote()
            return
        }

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("mac-setup-dotfiles-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try runner.checked(git(), ["clone", "--depth", "1", "--", source.remoteURL, staging.path], interactive: true)
        guard checkoutIsDirectory(staging), checkoutIsDirectory(staging.appendingPathComponent(".git")) else {
            throw SetupError("Dotfiles clone did not create a valid checkout.")
        }
        for name in source.folders where !checkoutIsDirectory(staging.appendingPathComponent(name)) {
            throw SetupError("Dotfiles checkout is missing configuration folder: \(name)")
        }
        try journal.replace(destination, with: staging, transaction: transaction)
    }

    public func link(_ name: String, transaction: String) throws {
        guard source.folders.contains(name) else { throw SetupError("Unsupported dotfiles profile: \(name)") }
        guard status() == .done else { throw SetupError("Clone dot-files before linking configurations.") }
        try verifyRemote()
        guard checkoutIsDirectory(source.checkout.appendingPathComponent(name)) else {
            throw SetupError("Dotfiles checkout is missing configuration folder: \(name)")
        }
        let target = paths.config.appendingPathComponent(name)
        if source.isLinked(name, config: paths.config) { return }
        if isSymlink(target) {
            throw SetupError("\(target.path) links to another location. Resolve that link manually before continuing.")
        }

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createSymbolicLink(at: staging,
            withDestinationURL: source.checkout.appendingPathComponent(name))
        try journal.replace(target, with: staging, transaction: transaction)
    }

    public func update() throws {
        guard status() == .done else { throw SetupError("No valid dot-files checkout to update.") }
        try verifyRemote()
        let directory = source.checkout.path
        let changes = try runner.checked(git(), ["-C", directory, "status", "--porcelain"]).text
        guard changes.isEmpty else {
            throw SetupError("The dot-files checkout has local changes. Commit or stash them before updating.")
        }
        try runner.checked(git(), ["-C", directory, "pull", "--ff-only"], interactive: true)
    }

    public func isSymlink(_ location: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: location.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private func verifyRemote() throws {
        let remote = try runner.checked(git(), ["-C", source.checkout.path,
                                                "remote", "get-url", "origin"]).text
        let accepted = [source.remoteURL, "https://github.com/Roobahist/dot-files",
                        "git@github.com:Roobahist/dot-files.git"]
        guard accepted.contains(remote) else {
            throw SetupError("The dot-files checkout uses an unexpected Git remote. No changes made.")
        }
    }

    private func git() -> String { executable("git") ?? "/usr/bin/git" }

    private func checkoutIsDirectory(_ location: URL) -> Bool {
        guard !isSymlink(location) else { return false }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: location.path, isDirectory: &directory)
            && directory.boolValue
    }
}
