import Foundation
import Darwin

public struct SetupError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public struct CommandResult {
    public let status: Int32
    public let output: Data
    public var text: String { String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    public init(status: Int32, output: Data = Data()) { self.status = status; self.output = output }
}

public protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String], interactive: Bool, input: Data?) throws -> CommandResult
}

public extension CommandRunning {
    func run(_ executable: String, _ arguments: [String] = [], interactive: Bool = false, input: Data? = nil) throws -> CommandResult {
        try run(executable, arguments, interactive: interactive, input: input)
    }
    @discardableResult
    func checked(_ executable: String, _ arguments: [String] = [], interactive: Bool = false, input: Data? = nil) throws -> CommandResult {
        let result = try run(executable, arguments, interactive: interactive, input: input)
        guard result.status == 0 else {
            throw SetupError("\(URL(fileURLWithPath: executable).lastPathComponent) failed (\(result.status)). \(result.text)")
        }
        return result
    }
}

public struct ProcessRunner: CommandRunning {
    private let timeout: TimeInterval
    public init(timeout: TimeInterval = 20) { self.timeout = timeout }
    public func run(_ executable: String, _ arguments: [String], interactive: Bool, input: Data?) throws -> CommandResult {
        let process = Process()
        var interactiveStatusFile: URL?
        if interactive {
            // Privileged installers need a controlling terminal for sudo prompts.
            // Foundation's child process may otherwise be placed in a background
            // process group and suspended by terminal job control (SIGTTIN).
            guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
                throw SetupError("Interactive installation requires a terminal. Run mac-setup in Terminal and retry.")
            }
            let statusFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            interactiveStatusFile = statusFile
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            process.arguments = ["-q", "/dev/null", "/bin/sh", "-c",
                "\"$@\"; status=$?; printf '%s' \"$status\" > \"$MAC_SETUP_STATUS_FILE\"; exit \"$status\"",
                "mac-setup-interactive", executable] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        }
        var environment = ProcessInfo.processInfo.environment
        // GUI-launched tools and launch agents may not inherit the user's shell PATH.
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        if let interactiveStatusFile { environment["MAC_SETUP_STATUS_FILE"] = interactiveStatusFile.path }
        process.environment = environment
        // A file avoids pipe-buffer deadlocks on verbose subprocesses.
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close(); try? FileManager.default.removeItem(at: outputURL) }
        if !interactive { process.standardOutput = output; process.standardError = output }
        var inputURL: URL?
        var inputHandle: FileHandle?
        if let input {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try input.write(to: url)
            inputURL = url
            inputHandle = try FileHandle(forReadingFrom: url)
            process.standardInput = inputHandle
        }
        defer { try? inputHandle?.close(); if let inputURL { try? FileManager.default.removeItem(at: inputURL) } }
        let foregroundGroup = interactive ? tcgetpgrp(STDIN_FILENO) : -1
        try process.run()
        if interactive {
            // Swift Process launches the installer in a separate process group.
            // Give that group terminal access, then restore the setup UI.
            let oldHandler = signal(SIGTTOU, SIG_IGN)
            defer {
                if foregroundGroup > 0 { _ = tcsetpgrp(STDIN_FILENO, foregroundGroup) }
                _ = signal(SIGTTOU, oldHandler)
            }
            let childGroup = getpgid(process.processIdentifier)
            if childGroup <= 0 || tcsetpgrp(STDIN_FILENO, childGroup) != 0 {
                _ = kill(process.processIdentifier, SIGTERM)
                process.waitUntilExit()
                throw SetupError("Could not give the interactive installer terminal control.")
            }
            if childGroup != foregroundGroup { _ = kill(-childGroup, SIGCONT) }
            process.waitUntilExit()
        } else {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.1)
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw SetupError("\(URL(fileURLWithPath: executable).lastPathComponent) did not respond within \(Int(timeout)) seconds. Open the app and retry this check.")
            }
            process.waitUntilExit()
        }
        defer {
            if let interactiveStatusFile { try? FileManager.default.removeItem(at: interactiveStatusFile) }
        }
        if let interactiveStatusFile {
            guard let contents = try? String(contentsOf: interactiveStatusFile, encoding: .utf8),
                  let status = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SetupError("Interactive installer ended without a verified exit status. Check the installation before retrying.")
            }
            return CommandResult(status: status)
        }
        return CommandResult(status: process.terminationStatus, output: try Data(contentsOf: outputURL))
    }
}

public struct Paths {
    public let home: URL
    public let config: URL
    public let state: URL
    public let profile: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, profile: URL? = nil) {
        self.home = home
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/"), home == FileManager.default.homeDirectoryForCurrentUser {
            config = URL(fileURLWithPath: xdg)
        } else { config = home.appendingPathComponent(".config") }
        state = home.appendingPathComponent("Library/Application Support/mac-setup")
        self.profile = profile ?? Bundle.main.url(forResource: "Profile", withExtension: nil)
            ?? Bundle.module.url(forResource: "Profile", withExtension: nil)!
    }
}

public func executable(_ name: String) -> String? {
    let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] +
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    return paths.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
}

public func appPath(_ name: String, home: URL) -> String? {
    ["/Applications/\(name).app", home.appendingPathComponent("Applications/\(name).app").path]
        .first { FileManager.default.fileExists(atPath: $0) }
}

public func plistData(_ value: Any) throws -> Data {
    // Wrapping scalars permits property-list serialization on every supported OS.
    try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .xml, options: 0)
}

public func plistValue(_ data: Data) throws -> Any {
    guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let value = dictionary["value"] else {
        throw SetupError("Invalid preference backup.")
    }
    return value
}

public func equalPlist(_ lhs: Any?, _ rhs: Any?) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    return NSDictionary(dictionary: ["value": lhs]).isEqual(to: ["value": rhs])
}
