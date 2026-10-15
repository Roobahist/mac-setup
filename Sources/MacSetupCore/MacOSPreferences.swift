import Foundation
import CoreFoundation

/// Portable, user-editable values. Local preference backups never belong in this file.
public struct MacOSSetting {
    public let id: String
    public let title: String
    public let domain: String
    public let key: String
    public let enabled: Bool
    public let value: Any?
    public let tasks: [String]
    public let restart: String?
    public let minimumOS: Int
    public let operation: String

    public func resolvedValue(previous: Any?) -> Any? {
        guard operation == "finder-list", let options = value as? [String: Any] else { return value }
        return MacOSProfile.finderListDefaults(previous as? [String: Any] ?? [:], options: options)
    }
}

public struct MacOSProfile {
    private var document: [String: Any]
    public var enabled: Bool { document["enabled"] as! Bool }
    public let settings: [MacOSSetting]

    public init(data: Data) throws {
        guard let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              doc["version"] as? Int == 1, !Self.isBool(doc["version"]), Self.isBool(doc["enabled"]),
              let rows = doc["settings"] as? [[String: Any]], !rows.isEmpty else {
            throw SetupError("macOS preferences require version 1, an enabled boolean and a nonempty settings array.")
        }
        var ids = Set<String>(), targets = Set<String>(), parsed: [MacOSSetting] = []
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty, ids.insert(id).inserted,
                  let title = row["title"] as? String, !title.isEmpty,
                  Self.isBool(row["enabled"]), let active = row["enabled"] as? Bool,
                  let domain = row["domain"] as? String,
                  domain.range(of: "^(NSGlobalDomain|com\\.apple\\.[A-Za-z0-9.-]+)$", options: .regularExpression) != nil,
                  let key = row["key"] as? String, !key.isEmpty, !key.hasPrefix("-"),
                  targets.insert(domain + "/" + key).inserted,
                  let tasks = row["tasks"] as? [String], row.keys.contains("value") else {
                throw SetupError("Invalid or duplicate macOS setting. Each setting needs a unique id/target, title, enabled, domain, key, value and tasks.")
            }
            let restart = row["restart"] as? String
            guard row["restart"] == nil || ["Dock", "Finder", "SystemUIServer"].contains(restart ?? "") else {
                throw SetupError("Unsupported macOS refresh process for \(id).")
            }
            let minimum = row["minimumOS"] as? Int ?? 13
            guard minimum >= 13, minimum <= 99,
                  row["minimumOS"] == nil || (row["minimumOS"] as? Int != nil && !Self.isBool(row["minimumOS"])) else {
                throw SetupError("Invalid minimumOS for \(id).")
            }
            let operation = row["operation"] as? String ?? "set"
            let value = row["value"] is NSNull ? nil : row["value"]
            guard row["operation"] == nil || row["operation"] is String,
                  ["set", "finder-list"].contains(operation),
                  value == nil || PropertyListSerialization.propertyList(value!, isValidFor: .xml) else {
                throw SetupError("Invalid preference value or operation for \(id).")
            }
            if operation == "finder-list" {
                guard domain == "com.apple.finder", key == "StandardViewSettings",
                      let options = value as? [String: Any],
                      let icon = options["iconSize"] as? NSNumber, (16...512).contains(icon.doubleValue),
                      let text = options["textSize"] as? NSNumber, (9...40).contains(text.doubleValue),
                      let sort = options["sortColumn"] as? String, Self.columnIDs.contains(sort),
                      let columns = options["visibleColumns"] as? [String], columns.contains("name"),
                      columns.allSatisfy(Self.columnIDs.contains),
                      ["useRelativeDates", "calculateAllSizes", "showIconPreview", "sortAscending"].allSatisfy({ Self.isBool(options[$0]) }) else {
                    throw SetupError("Invalid Finder list options for \(id).")
                }
            }
            parsed.append(MacOSSetting(id: id, title: title, domain: domain, key: key,
                                       enabled: active, value: value, tasks: tasks, restart: restart,
                                       minimumOS: minimum, operation: operation))
        }
        document = doc; settings = parsed
    }

    private static func isBool(_ value: Any?) -> Bool {
        guard let value = value as? NSNumber else { return false }
        return CFGetTypeID(value) == CFBooleanGetTypeID()
    }

    public func encoded() throws -> Data {
        try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
    }

    public func settingEnabled(_ enabled: Bool) throws -> MacOSProfile {
        var copy = document; copy["enabled"] = enabled
        return try Self(data: JSONSerialization.data(withJSONObject: copy))
    }

    public func updating(domain: String, key: String, value: Any?) throws -> MacOSProfile {
        guard enabled else { throw SetupError("The macOS preference profile is off. Enable it in Appearance before editing its settings.") }
        var rows = document["settings"] as! [[String: Any]]
        guard let index = rows.firstIndex(where: { $0["domain"] as? String == domain && $0["key"] as? String == key }) else {
            throw SetupError("This preference is missing from macos/preferences.json. Add it there before editing it in Mac Setup.")
        }
        rows[index]["value"] = value ?? NSNull(); rows[index]["enabled"] = true
        var copy = document; copy["settings"] = rows
        return try Self(data: JSONSerialization.data(withJSONObject: copy))
    }

    static let columnIDs = ["name", "dateModified", "size", "kind", "dateCreated", "dateLastOpened", "dateAdded", "version", "comments", "label", "ubiquity", "shareOwner", "shareLastEditor", "invitationStatus"]

    static func finderListDefaults(_ original: [String: Any], options: [String: Any]) -> [String: Any] {
        var views = original
        let existing = ["ListViewSettings", "ExtendedListViewSettingsV2"].filter { views[$0] is [String: Any] }
        let visible = Set(options["visibleColumns"] as! [String])
        let sort = options["sortColumn"] as! String
        for key in existing.isEmpty ? ["ListViewSettings"] : existing {
            var list = views[key] as? [String: Any] ?? [:]
            for name in ["iconSize", "textSize", "sortColumn", "useRelativeDates", "calculateAllSizes", "showIconPreview"] { list[name] = options[name] }
            if var columns = list["columns"] as? [[String: Any]] {
                for index in columns.indices {
                    if let identifier = columns[index]["identifier"] as? String {
                        columns[index]["visible"] = visible.contains(identifier)
                        if identifier == sort { columns[index]["ascending"] = options["sortAscending"] }
                    }
                }
                for id in columnIDs where !columns.contains(where: { $0["identifier"] as? String == id }) {
                    columns.append(["identifier": id, "visible": visible.contains(id), "ascending": id == sort ? options["sortAscending"]! : true])
                }
                list["columns"] = columns
            } else {
                var columns = list["columns"] as? [String: [String: Any]] ?? [:]
                for (index, id) in columnIDs.enumerated() {
                    var column = columns[id] ?? ["index": index]
                    column["visible"] = visible.contains(id)
                    if id == sort { column["ascending"] = options["sortAscending"] }
                    columns[id] = column
                }
                for id in Array(columns.keys) where !visible.contains(id) { columns[id]?["visible"] = false }
                list["columns"] = columns
            }
            views[key] = list
        }
        return views
    }
}

private struct ManagedMacOSPreference: Codable {
    let id: String
    let domain: String
    let key: String
    let tasks: [String]
    let restart: String?
    let before: Data?
    var after: Data?
}

/// One implementation for dotfiles commands, setup tasks and individual GUI edits.
public final class MacOSPreferenceService {
    public static let groupDidChange = Notification.Name("MacSetupMacOSPreferenceGroupDidChange")
    public let paths: Paths
    public let profileURL: URL
    private let journal: Journal
    private let runner: CommandRunning
    private let osMajor: Int
    private let explicitProfile: Bool
    private var stateURL: URL { paths.state.appendingPathComponent("macos-managed.json") }

    public init(paths: Paths, journal: Journal, runner: CommandRunning, profileURL: URL? = nil,
                osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.paths = paths; self.journal = journal; self.runner = runner; self.osMajor = osMajor
        explicitProfile = profileURL != nil
        self.profileURL = profileURL ?? paths.config.appendingPathComponent("macos/preferences.json")
    }

    public func profile() throws -> MacOSProfile {
        let url = explicitProfile || Journal.exists(profileURL) ? profileURL : paths.profile.appendingPathComponent("macos/preferences.json")
        do { return try MacOSProfile(data: Data(contentsOf: url)) }
        catch { throw SetupError("Cannot load macOS preferences at \(url.path): \(error)") }
    }

    private func managed() throws -> [ManagedMacOSPreference] {
        guard Journal.exists(stateURL) else { return [] }
        return try JSONDecoder().decode([ManagedMacOSPreference].self, from: Data(contentsOf: stateURL))
    }

    private struct Change {
        let domain: String
        let key: String
        let value: Any?
        let restart: String?
        let title: String
    }
    private struct Plan {
        var changes: [Change] = []
        var managed: [ManagedMacOSPreference]
        var notes: [String] = []
    }

    private func plan(_ profile: MacOSProfile, taskID: String? = nil, settingID: String? = nil) throws -> Plan {
        var plan = Plan(managed: try managed())
        var domains: [String: [String: Any]] = [:]
        func current(_ domain: String, _ key: String) throws -> Any? {
            if domains[domain] == nil { domains[domain] = try journal.preferences(domain) }
            return domains[domain]?[key]
        }
        let selected: (MacOSSetting) -> Bool = { (taskID == nil || $0.tasks.contains(taskID!)) && (settingID == nil || $0.id == settingID) }
        let active = profile.settings.filter { selected($0) && profile.enabled && $0.enabled && $0.minimumOS <= osMajor }
        let activeIDs = Set(active.map(\.id))
        for old in plan.managed where !activeIDs.contains(old.id)
            && (taskID == nil || old.tasks.contains(taskID!)) && (settingID == nil || old.id == settingID) {
            let live = try current(old.domain, old.key)
            let last = try old.after.map(plistValue)
            let before = try old.before.map(plistValue)
            if equalPreference(live, last) {
                if !equalPreference(live, before) {
                    plan.changes.append(Change(domain: old.domain, key: old.key, value: before, restart: old.restart, title: "Restore " + (profile.settings.first { $0.id == old.id }?.title ?? old.id)))
                    domains[old.domain]?[old.key] = before
                }
            } else {
                plan.notes.append("Keep later manual edit: \(old.id). The profile no longer owns this preference.")
            }
            plan.managed.removeAll { $0.id == old.id }
        }
        for setting in active {
            let live = try current(setting.domain, setting.key)
            let desired = setting.resolvedValue(previous: live)
            if let index = plan.managed.firstIndex(where: { $0.id == setting.id }) {
                guard plan.managed[index].domain == setting.domain, plan.managed[index].key == setting.key else {
                    throw SetupError("The target for \(setting.id) changed. Disable and apply it before changing its domain/key.")
                }
                plan.managed[index].after = try desired.map(plistData)
            } else {
                plan.managed.append(ManagedMacOSPreference(id: setting.id, domain: setting.domain, key: setting.key,
                                                          tasks: setting.tasks, restart: setting.restart,
                                                          before: try live.map(plistData), after: try desired.map(plistData)))
            }
            if !equalPreference(live, desired) {
                plan.changes.append(Change(domain: setting.domain, key: setting.key, value: desired,
                                           restart: setting.restart, title: setting.title))
            }
        }
        for setting in profile.settings where selected(setting) && profile.enabled && setting.enabled && setting.minimumOS > osMajor {
            plan.notes.append("Unavailable on this macOS version: \(setting.title) (requires macOS \(setting.minimumOS)+).")
        }
        return plan
    }

    public func preview(enabled: Bool? = nil, taskID: String? = nil) throws -> [String] {
        let loaded = try profile()
        let requested = try enabled.map { try loaded.settingEnabled($0) } ?? loaded
        let planned = try plan(requested, taskID: taskID)
        var lines = ["Configuration: \(profileURL.path)", "macOS preferences: \(requested.enabled ? "on" : "off")"]
        lines += try planned.changes.map { change in
            "\(change.title) → \(try Self.describe(change.value))"
        }
        if requested.enabled {
            for setting in requested.settings where setting.enabled && setting.minimumOS <= osMajor
                && (taskID == nil || setting.tasks.contains(taskID!))
                && !planned.changes.contains(where: { $0.domain == setting.domain && $0.key == setting.key }) {
                lines.append("Already matches: \(setting.title)")
            }
        }
        if planned.changes.isEmpty { lines.append("No stored preference changes needed.") }
        lines += planned.notes
        lines.append("Previous values stay in private local backups. Some changes require logout or reopening apps; macOS does not watch this JSON file.")
        return lines
    }

    private static func describe(_ value: Any?) throws -> String {
        guard let value else { return "Use system default" }
        if value is [String: Any] { return "Update saved options; preserve unrelated preferences" }
        if let list = value as? [Any] { return list.isEmpty ? "Empty list" : "\(list.count) items" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "On" : "Off"
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), as: UTF8.self)
    }

    public func matches(taskID: String? = nil) throws -> Bool {
        try plan(profile(), taskID: taskID).changes.isEmpty
    }

    /// Caller owns the setup lock and transaction; setup task restarts are coordinated by Engine.
    public func apply(_ profile: MacOSProfile, transaction: String, taskID: String? = nil, settingID: String? = nil) throws -> Set<String> {
        let planned = try plan(profile, taskID: taskID, settingID: settingID)
        let destination = profileURL.resolvingSymlinksInPath()
        let data = try profile.encoded()
        if (try? Data(contentsOf: destination)) != data { try journal.write(destination, data: data, transaction: transaction) }
        for change in planned.changes {
            if let value = change.value { try journal.setPreference(change.domain, change.key, value, transaction: transaction) }
            else { try journal.clearPreference(change.domain, change.key, transaction: transaction) }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try journal.write(stateURL, data: encoder.encode(planned.managed), transaction: transaction, permissions: 0o600)
        return Set(planned.changes.compactMap(\.restart))
    }

    @discardableResult
    public func apply(enabled: Bool? = nil, expected: Data? = nil) throws -> TweakChangeResult {
        let loaded = try profile()
        if let expected, try loaded.encoded() != expected { throw SetupError("The preference file changed after review. Review it again before applying.") }
        let lock = try SetupLock(paths: paths)
        defer { withExtendedLifetime(lock) {} }
        guard try profile().encoded() == loaded.encoded() else { throw SetupError("The preference file changed. Review it again before applying.") }
        let requested = try enabled.map { try loaded.settingEnabled($0) } ?? loaded
        let transaction = try journal.begin("macos-preferences")
        do {
            let restarts = try apply(requested, transaction: transaction)
            try journal.finish(transaction)
            var warnings: [String] = []
            for process in restarts.sorted() {
                if let warning = TweakService.refresh(process, runner: runner) { warnings.append(warning) }
            }
            NotificationCenter.default.post(name: Self.groupDidChange, object: nil)
            return TweakChangeResult(transaction: transaction, refreshWarning: warnings.isEmpty ? nil : warnings.joined(separator: "\n"))
        } catch {
            do { try journal.restore(transaction) }
            catch { throw SetupError("macOS preferences failed and recovery needs attention: \(error). Recovery record: \(transaction)") }
            throw SetupError("macOS preferences were not applied. Previous files and values were restored. \(error)")
        }
    }
}
