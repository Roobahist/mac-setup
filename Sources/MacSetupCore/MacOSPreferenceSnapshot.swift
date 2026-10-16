import Foundation

public struct MacOSPreferenceEdit {
    public let id: String
    public var enabled: Bool
    public var value: Any?
    public init(id: String, enabled: Bool, value: Any?) {
        self.id = id; self.enabled = enabled; self.value = value
    }
}

public struct MacOSPreferenceSnapshot {
    public let profile: MacOSProfile
    // Raw current values are private, in-memory comparison tokens, never profile metadata.
    let live: [String: Data]
    public func value(for id: String) throws -> Any? { try live[id].map(plistValue) }

    public func preservingBaseline(for ids: Set<String>, from older: Self) -> Self {
        var values = live
        for id in ids { values[id] = older.live[id] }
        return Self(profile: profile, live: values)
    }
}
