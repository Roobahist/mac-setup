import Foundation

public struct GuideRequirement: Codable, Equatable {
    public let id: String
    public let title: String
    public let ready: Bool
    public init(_ id: String, _ title: String, _ ready: Bool) { self.id = id; self.title = title; self.ready = ready }
}

public struct GuideProgress: Codable {
    public var completedSteps: [String: Set<String>] = [:]
    public var observedRequirements: [String: [GuideRequirement]] = [:]
    public var lastChecked: [String: Date] = [:]
    public init() {}
    public static func load(from paths: Paths) throws -> GuideProgress {
        let file = paths.state.appendingPathComponent("guided-checklist.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return GuideProgress() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }
    public func save(to paths: Paths) throws {
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = paths.state.appendingPathComponent("guided-checklist.json")
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
