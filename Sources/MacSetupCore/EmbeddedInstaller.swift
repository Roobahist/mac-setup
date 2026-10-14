import Foundation

/// Runs installers in a pseudo-terminal hosted by the native setup window.
/// Arguments are passed as argv, never interpolated into a shell command.
public final class EmbeddedInstaller: CommandRunning {
    public var output: (String) -> Void = { _ in }
    public var inputChanged: (Bool) -> Void = { _ in }
    private let lock = NSLock()
    private var inputHandle: FileHandle?
    public init() {}

    public func send(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        try? inputHandle?.write(contentsOf: Data((text + "\n").utf8))
    }

    public func run(_ executable: String, _ arguments: [String], interactive: Bool, input: Data?) throws -> CommandResult {
        guard interactive else { return try ProcessRunner().run(executable, arguments, input: input) }
        let statusFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: statusFile) }
        let process = Process()
        let stdin = Pipe(), stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/sh", "-c",
            "\"$@\"; status=$?; printf '%s' \"$status\" > \"$MAC_SETUP_STATUS_FILE\"; exit \"$status\"",
            "mac-setup-installer", executable] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        environment["TERM"] = "dumb"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        environment["MAC_SETUP_STATUS_FILE"] = statusFile.path
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stdout
        try process.run()
        lock.lock(); inputHandle = stdin.fileHandleForWriting; lock.unlock()
        inputChanged(true)
        defer {
            lock.lock(); inputHandle = nil; lock.unlock()
            try? stdin.fileHandleForWriting.close()
            inputChanged(false)
        }
        if let input { try stdin.fileHandleForWriting.write(contentsOf: input) }
        var captured = Data()
        while true {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            captured.append(chunk)
            output(String(decoding: chunk, as: UTF8.self))
        }
        process.waitUntilExit()
        guard let value = try? String(contentsOf: statusFile, encoding: .utf8),
              let status = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SetupError("The installer stopped without a completion status. Check its output and retry this task.")
        }
        return CommandResult(status: status, output: captured)
    }
}
