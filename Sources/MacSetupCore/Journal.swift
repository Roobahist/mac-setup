import Foundation
import CryptoKit
import Darwin
import CoreFoundation

public enum ChangeKind: String, Codable { case path, preference, git, service, launchAgent }

public struct SavedChange: Codable {
    public let kind: ChangeKind
    public let target: String
    public let key: String?
    public let backup: String?
    public let before: Data?
    public let after: Data?
    public var restored: Bool
}

public struct Transaction: Codable {
    public let id: String
    public let date: Date
    public let task: String
    public var complete: Bool
    public var changes: [SavedChange]
}

public final class Journal {
    public let paths: Paths
    private let runner: CommandRunning
    public private(set) var transactions: [Transaction]
    private let file: URL

    public init(paths: Paths, runner: CommandRunning) throws {
        self.paths = paths; self.runner = runner
        file = paths.state.appendingPathComponent("journal.json")
        if FileManager.default.fileExists(atPath: file.path) {
            transactions = try JSONDecoder().decode([Transaction].self, from: Data(contentsOf: file))
        } else { transactions = [] }
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(transactions).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public func begin(_ task: String) throws -> String {
        try reload()
        let id = UUID().uuidString.lowercased()
        transactions.append(Transaction(id: id, date: Date(), task: task, complete: false, changes: []))
        try save(); return id
    }

    public func finish(_ id: String) throws {
        guard let index = transactions.firstIndex(where: { $0.id == id }) else { throw SetupError("Unknown backup.") }
        transactions[index].complete = true
        try save()
    }

    private func add(_ change: SavedChange, to id: String) throws {
        guard let index = transactions.firstIndex(where: { $0.id == id }) else { throw SetupError("Unknown backup.") }
        transactions[index].changes.append(change)
        try save() // The recovery record reaches disk before the change.
    }

    public static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    public static func fingerprint(_ url: URL) throws -> Data? {
        guard exists(url) else { return nil }
        var hasher = SHA256()
        func visit(_ item: URL, relative: String) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: item.path)
            let type = attributes[.type] as? FileAttributeType
            hasher.update(data: Data(relative.utf8)); hasher.update(data: Data([0]))
            if type == .typeSymbolicLink {
                hasher.update(data: Data("link".utf8))
                hasher.update(data: Data(try FileManager.default.destinationOfSymbolicLink(atPath: item.path).utf8))
            } else if type == .typeDirectory {
                hasher.update(data: Data("directory".utf8))
                for child in try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, relative: relative + "/" + child.lastPathComponent)
                }
            } else if type == .typeRegular {
                hasher.update(data: Data("file".utf8))
                hasher.update(data: Data(String(describing: attributes[.posixPermissions] ?? "").utf8))
                hasher.update(data: try Data(contentsOf: item))
            } else { throw SetupError("Unsupported file type: \(item.path)") }
            hasher.update(data: Data([0]))
        }
        try visit(url, relative: "")
        return Data(hasher.finalize())
    }

    public func replace(_ target: URL, with source: URL, transaction: String) throws {
        try refuseSymlinkParents(target)
        let before = try Self.fingerprint(target)
        let after = try Self.fingerprint(source)
        guard before != after else { return }
        let backupName = transaction + "-" + UUID().uuidString
        let backupURL = paths.state.appendingPathComponent("backups/" + backupName)
        if before != nil {
            try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.copyItem(at: target, to: backupURL)
        }
        try add(SavedChange(kind: .path, target: target.path, key: nil, backup: before == nil ? nil : backupName, before: before, after: after, restored: false), to: transaction)
        if Self.exists(target) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: target)
    }

    public func write(_ target: URL, data: Data, transaction: String, executable: Bool = false) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: temp.path)
        try replace(target, with: temp, transaction: transaction)
    }

    public func preference(_ domain: String, _ key: String) throws -> Any? {
        let result = try runner.run("/usr/bin/defaults", ["export", domain, "-"])
        if result.status != 0 {
            // Missing domains are normal. Other errors must not masquerade as absence.
            if result.text.contains("does not exist") || result.text.contains("not found") { return nil }
            throw SetupError("Cannot read preferences for \(domain): \(result.text)")
        }
        guard let values = try PropertyListSerialization.propertyList(from: result.output, format: nil) as? [String: Any] else {
            throw SetupError("Cannot decode preferences for \(domain).")
        }
        return values[key]
    }

    private func setPreference(_ domain: String, _ key: String, _ value: Any?) throws {
        guard let value else {
            if try preference(domain, key) != nil { try runner.checked("/usr/bin/defaults", ["delete", domain, key]) }
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: value is String || value is NSNumber ? ["value": value] : value, format: .xml, options: 0)
        if let string = value as? String {
            try runner.checked("/usr/bin/defaults", ["write", domain, key, "-string", string])
        } else if let number = value as? NSNumber {
            let type = String(cString: number.objCType)
            let isBoolean = CFGetTypeID(number) == CFBooleanGetTypeID()
            let flag = isBoolean ? "-bool" : (["f", "d"].contains(type) ? "-float" : "-int")
            // macOS defaults requires true/false for -bool, not NSNumber's 1/0.
            let argument = isBoolean ? (number.boolValue ? "true" : "false") : number.stringValue
            try runner.checked("/usr/bin/defaults", ["write", domain, key, flag, argument])
        } else {
            try runner.checked("/usr/bin/defaults", ["write", domain, key, String(decoding: data, as: UTF8.self)])
        }
    }

    public func setPreference(_ domain: String, _ key: String, _ value: Any, transaction: String) throws {
        let old = try preference(domain, key)
        guard !equalPlist(old, value) else { return }
        try add(SavedChange(kind: .preference, target: domain, key: key, backup: nil, before: try old.map(plistData), after: try plistData(value), restored: false), to: transaction)
        do {
            try setPreference(domain, key, value)
        } catch {
            // Include the target preference, not its potentially sensitive value.
            throw SetupError("Cannot update preference \(domain) / \(key): \(error)")
        }
        guard equalPlist(try preference(domain, key), value) else { throw SetupError("Preference verification failed: \(domain) \(key)") }
    }

    public func launchAgentLoaded(_ label: String) throws -> Bool {
        try runner.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]).status == 0
    }

    public func suspendLaunchAgent(_ label: String, plist: URL, transaction: String) throws {
        let old = try launchAgentLoaded(label)
        try add(SavedChange(kind: .launchAgent, target: label, key: plist.path, backup: nil,
            before: try plistData(old), after: try plistData(true), restored: false), to: transaction)
        if old { try stopLaunchAgent(label) }
    }

    public func stopLaunchAgent(_ label: String) throws {
        if try launchAgentLoaded(label) {
            try runner.checked("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        }
    }

    public func loadLaunchAgent(_ plist: URL) throws {
        try runner.checked("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plist.path])
    }

    public func gitValues(_ key: String) throws -> [String] {
        let result = try runner.run("/usr/bin/git", ["config", "--global", "--get-all", key])
        if result.status == 1 { return [] }
        guard result.status == 0 else { throw SetupError("Cannot read global Git configuration: \(result.text)") }
        var values = String(decoding: result.output, as: UTF8.self).components(separatedBy: "\n")
        if values.last == "" { values.removeLast() }
        return values
    }

    public func setGit(_ key: String, _ value: String, transaction: String) throws {
        let old = try gitValues(key)
        guard old != [value] else { return }
        try add(SavedChange(kind: .git, target: "global", key: key, backup: nil, before: try plistData(old), after: try plistData([value]), restored: false), to: transaction)
        try runner.checked("/usr/bin/git", ["config", "--global", "--replace-all", key, value])
    }

    public func serviceStarted() throws -> Bool {
        guard let brew = executable("brew") else { return false }
        let result = try runner.checked(brew, ["services", "info", "sketchybar", "--json"])
        guard let items = try JSONSerialization.jsonObject(with: result.output) as? [[String: Any]], let item = items.first else {
            throw SetupError("Cannot read SketchyBar service status.")
        }
        return item["status"] as? String == "started"
    }

    public func startService(transaction: String) throws {
        guard let brew = executable("brew") else { throw SetupError("Install Homebrew first.") }
        let old = try serviceStarted()
        if !old {
            try add(SavedChange(kind: .service, target: "sketchybar", key: nil, backup: nil, before: try plistData(old), after: try plistData(true), restored: false), to: transaction)
        }
        try runner.checked(brew, ["services", old ? "restart" : "start", "sketchybar"], interactive: true)
        guard try serviceStarted() else { throw SetupError("SketchyBar did not remain running. Run sketchybar in Terminal to inspect its config errors.") }
    }

    public func restore(_ id: String, force: Bool = false) throws {
        try reload()
        guard let index = transactions.firstIndex(where: { $0.id == id }) else { throw SetupError("Unknown backup: \(id)") }
        // Preflight all conflicts before restoring anything.
        for change in transactions[index].changes where !change.restored {
            let current = try currentValue(change)
            if !force && current != change.after && current != change.before {
                throw SetupError("\(change.target) changed since setup. Nothing restored. Inspect it first; --force explicitly discards later edits.")
            }
            if let backup = change.backup, !Self.exists(paths.state.appendingPathComponent("backups/" + backup)) {
                throw SetupError("Missing backup file for \(change.target).")
            }
            if change.kind == .path { try refuseSymlinkParents(URL(fileURLWithPath: change.target)) }
        }
        for change in transactions[index].changes where change.kind == .launchAgent && !change.restored {
            try stopLaunchAgent(change.target)
        }
        for changeIndex in transactions[index].changes.indices.reversed() {
            let change = transactions[index].changes[changeIndex]
            if change.restored { continue }
            switch change.kind {
            case .path:
                let url = URL(fileURLWithPath: change.target)
                if Self.exists(url) { try FileManager.default.removeItem(at: url) }
                if let backup = change.backup {
                    try FileManager.default.copyItem(at: paths.state.appendingPathComponent("backups/" + backup), to: url)
                }
            case .preference:
                try setPreference(change.target, change.key!, try change.before.map(plistValue))
            case .git:
                let key = change.key!
                if !(try gitValues(key)).isEmpty { try runner.checked("/usr/bin/git", ["config", "--global", "--unset-all", key]) }
                for value in (try plistValue(change.before!) as? [String] ?? []) {
                    try runner.checked("/usr/bin/git", ["config", "--global", "--add", key, value])
                }
            case .service:
                guard let brew = executable("brew") else { throw SetupError("Homebrew is required to restore the service state.") }
                let wasStarted = try plistValue(change.before!) as? Bool ?? false
                try runner.checked(brew, ["services", wasStarted ? "start" : "stop", "sketchybar"], interactive: true)
            case .launchAgent:
                if try plistValue(change.before!) as? Bool == true { try loadLaunchAgent(URL(fileURLWithPath: change.key!)) }
            }
            transactions[index].changes[changeIndex].restored = true
            try save()
        }
    }

    private func currentValue(_ change: SavedChange) throws -> Data? {
        switch change.kind {
        case .path: return try Self.fingerprint(URL(fileURLWithPath: change.target))
        case .preference: return try preference(change.target, change.key!).map(plistData)
        case .git: return try plistData(gitValues(change.key!))
        case .service: return try plistData(serviceStarted())
        case .launchAgent: return try plistData(launchAgentLoaded(change.target))
        }
    }

    private func reload() throws {
        if FileManager.default.fileExists(atPath: file.path) {
            transactions = try JSONDecoder().decode([Transaction].self, from: Data(contentsOf: file))
        }
    }

    private func refuseSymlinkParents(_ target: URL) throws {
        var parent = target.deletingLastPathComponent()
        while parent.path != "/" {
            if (try? FileManager.default.attributesOfItem(atPath: parent.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                // macOS itself aliases these root directories into /private.
                // User-created config symlinks are still refused.
                let systemAliases = ["/var": "/private/var", "/tmp": "/private/tmp", "/etc": "/private/etc"]
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: parent.path)
                let absoluteDestination = destination.hasPrefix("/") ? destination : "/" + destination
                if systemAliases[parent.path] != absoluteDestination {
                    throw SetupError("Parent directory is a symlink: \(parent.path). Choose a real configuration directory before setup.")
                }
            }
            parent.deleteLastPathComponent()
        }
    }
}

public final class SetupLock {
    private let descriptor: Int32
    public init(paths: Paths) throws {
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        descriptor = Darwin.open(paths.state.appendingPathComponent("setup.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw SetupError("Cannot create setup lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor); throw SetupError("Another mac-setup operation is running.")
        }
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
