import Foundation

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
    public init() {}
    public func run(_ executable: String, _ arguments: [String], interactive: Bool, input: Data?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // GUI-launched tools and launch agents may not inherit the user's shell PATH.
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
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
        try process.run()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: interactive ? Data() : try Data(contentsOf: outputURL))
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
        self.profile = profile ?? Bundle.module.url(forResource: "Profile", withExtension: nil)!
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
