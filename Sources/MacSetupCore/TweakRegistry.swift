import Foundation

/// A setting is data, not a view. New controls can be registered without
/// changing navigation, persistence, or the guided setup task catalog.
public enum TweakKind {
    case toggle
    case slider(minimum: Double, maximum: Double, step: Double)
    case selection([TweakChoice])
}

public struct TweakChoice: Identifiable {
    public let title: String
    public let value: Int
    public var id: Int { value }

    public init(_ title: String, _ value: Int) {
        self.title = title
        self.value = value
    }
}

public struct TweakDescriptor: Identifiable {
    public let id: String
    public let category: String
    public let title: String
    public let summary: String
    public let domain: String
    public let key: String
    public let fallback: NSNumber
    public let kind: TweakKind
    public let restart: String?
    public let warning: String?

    public init(_ id: String, category: String, title: String, summary: String,
                domain: String, key: String, fallback: NSNumber, kind: TweakKind,
                restart: String? = nil, warning: String? = nil) {
        self.id = id
        self.category = category
        self.title = title
        self.summary = summary
        self.domain = domain
        self.key = key
        self.fallback = fallback
        self.kind = kind
        self.restart = restart
        self.warning = warning
    }
}

public enum TweakRegistry {
    public static let all: [TweakDescriptor] = [
        .init("dock.autoHide", category: "Dock", title: "Automatically hide the Dock",
              summary: "Reveal the Dock when the pointer reaches the screen edge.",
              domain: "com.apple.dock", key: "autohide", fallback: NSNumber(value: false),
              kind: .toggle, restart: "Dock"),
        .init("dock.hoverDelay", category: "Dock", title: "Dock reveal delay",
              summary: "How long the pointer waits before a hidden Dock appears, in seconds.",
              domain: "com.apple.dock", key: "autohide-delay", fallback: NSNumber(value: 0.5),
              kind: .slider(minimum: 0, maximum: 2, step: 0.05), restart: "Dock"),
        .init("dock.animation", category: "Dock", title: "Dock reveal animation",
              summary: "Duration of the Dock's hide and reveal animation, in seconds.",
              domain: "com.apple.dock", key: "autohide-time-modifier", fallback: NSNumber(value: 0.5),
              kind: .slider(minimum: 0, maximum: 1.5, step: 0.05), restart: "Dock"),
        .init("dock.size", category: "Dock", title: "Dock icon size",
              summary: "Size of Dock icons, in points.",
              domain: "com.apple.dock", key: "tilesize", fallback: NSNumber(value: 48),
              kind: .slider(minimum: 16, maximum: 128, step: 1), restart: "Dock"),
        .init("dock.recents", category: "Dock", title: "Recent applications",
              summary: "Show recently used applications on the right side of the Dock.",
              domain: "com.apple.dock", key: "show-recents", fallback: NSNumber(value: true),
              kind: .toggle, restart: "Dock"),
        .init("finder.extensions", category: "Finder", title: "Show all filename extensions",
              summary: "Display the full extension for files in Finder.",
              domain: "NSGlobalDomain", key: "AppleShowAllExtensions", fallback: NSNumber(value: false),
              kind: .toggle, restart: "Finder"),
        .init("finder.hidden", category: "Finder", title: "Show hidden files",
              summary: "Include dotfiles and other hidden items in Finder.",
              domain: "com.apple.finder", key: "AppleShowAllFiles", fallback: NSNumber(value: false),
              kind: .toggle, restart: "Finder"),
        .init("finder.pathBar", category: "Finder", title: "Show path bar",
              summary: "Show the selected folder's location at the bottom of Finder windows.",
              domain: "com.apple.finder", key: "ShowPathbar", fallback: NSNumber(value: false),
              kind: .toggle, restart: "Finder"),
        .init("finder.statusBar", category: "Finder", title: "Show status bar",
              summary: "Display item counts and available disk space in Finder.",
              domain: "com.apple.finder", key: "ShowStatusBar", fallback: NSNumber(value: false),
              kind: .toggle, restart: "Finder"),
        .init("clock.24Hour", category: "Menu Bar", title: "24-hour clock",
              summary: "Use a 24-hour time display for the macOS menu bar clock.",
              domain: "com.apple.menuextra.clock", key: "Show24Hour", fallback: NSNumber(value: false),
              kind: .toggle, warning: "Some macOS versions manage the system clock through Control Center. Reopen System Settings if the change is not reflected."),
        .init("clock.seconds", category: "Menu Bar", title: "Show seconds",
              summary: "Display seconds in the macOS menu bar clock.",
              domain: "com.apple.menuextra.clock", key: "ShowSeconds", fallback: NSNumber(value: false),
              kind: .toggle, warning: "This modifies the macOS clock, not the separate SketchyBar clock."),
        .init("clock.weekday", category: "Menu Bar", title: "Show day of the week",
              summary: "Include the weekday in the macOS menu bar clock.",
              domain: "com.apple.menuextra.clock", key: "ShowDayOfWeek", fallback: NSNumber(value: false),
              kind: .toggle),
        .init("appearance.accent", category: "Appearance", title: "System accent color",
              summary: "Set the macOS accent used by supported native controls.",
              domain: "NSGlobalDomain", key: "AppleAccentColor", fallback: NSNumber(value: 4),
              kind: .selection([
                .init("Graphite", -1), .init("Red", 0), .init("Orange", 1),
                .init("Yellow", 2), .init("Green", 3), .init("Blue (default)", 4),
                .init("Purple", 5), .init("Pink", 6)
              ]),
              warning: "Blue restores the macOS system default. Running apps may need to reopen to pick up the change. This does not change SketchyBar colors.")
    ]

    public static var categories: [String] {
        Array(Set(all.map(\.category))).sorted()
    }

    public static func filtered(_ query: String, category: String? = nil) -> [TweakDescriptor] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { tweak in
            (category == nil || tweak.category == category) &&
            (needle.isEmpty || [tweak.title, tweak.summary, tweak.category, tweak.id]
                .contains { $0.localizedCaseInsensitiveContains(needle) })
        }
    }
}

/// An operation can save correctly even when macOS refuses to refresh an
/// already-running process. Keep the recovery record and show that distinction.
public struct TweakChangeResult {
    public let transaction: String
    public let refreshWarning: String?

    public init(transaction: String, refreshWarning: String?) {
        self.transaction = transaction
        self.refreshWarning = refreshWarning
    }
}

/// Applies only the selected preference. The existing recovery journal retains
/// the previous value so independent edits are as reversible as setup tasks.
public final class TweakService {
    private let journal: Journal
    private let runner: CommandRunning
    private let paths: Paths

    public init(journal: Journal, runner: CommandRunning, paths: Paths) {
        self.journal = journal
        self.runner = runner
        self.paths = paths
    }

    public func storedValue(for tweak: TweakDescriptor) throws -> NSNumber? {
        try journal.preference(tweak.domain, tweak.key) as? NSNumber
    }

    public func value(for tweak: TweakDescriptor) throws -> NSNumber {
        try storedValue(for: tweak) ?? tweak.fallback
    }

    public static func usesSystemDefault(_ tweak: TweakDescriptor, value: NSNumber) -> Bool {
        tweak.id == "appearance.accent" && value.intValue == 4
    }

    private func refreshed(_ tweak: TweakDescriptor) -> String? {
        if tweak.id == "appearance.accent" {
            // Notify running apps after changing global accent preferences.
            for name in ["AppleColorPreferencesChangedNotification", "AppleAquaColorVariantChanged"] {
                DistributedNotificationCenter.default().post(
                    name: Notification.Name(name), object: nil)
            }
        }
        return Self.refresh(tweak.restart, runner: runner)
    }

    static func refresh(_ process: String?, runner: CommandRunning) -> String? {
        guard let process else { return nil }
        do {
            let result = try runner.run("/usr/bin/killall", [process])
            // An active macOS Dock normally relaunches through launchd.
            // If the relaunch fails, try to recover it, then warn the user.
            if process == "Dock" {
                for _ in 0..<4 {
                    Thread.sleep(forTimeInterval: 0.3)
                    if (try? runner.run("/usr/bin/pgrep", ["-x", "Dock"]))?.status == 0 {
                        return nil
                    }
                }
                _ = try? runner.run("/usr/bin/open", ["-a", "Dock"])
                Thread.sleep(forTimeInterval: 0.4)
                if (try? runner.run("/usr/bin/pgrep", ["-x", "Dock"]))?.status == 0 {
                    return nil
                }
                return "The preference was saved, but Dock has not restarted. Try 'killall Dock' or restart Dock from Activity Monitor."
            }
            if result.status != 0 {
                return "\(process) did not restart. The preference was saved, but its visible effect may be delayed."
            }
        } catch {
            return "The preference was saved, but \(process) could not restart: \(error)"
        }
        return nil
    }

    private func validate(_ tweak: TweakDescriptor, value: NSNumber) throws -> NSNumber {
        switch tweak.kind {
        case .toggle:
            return NSNumber(value: value.boolValue)
        case let .slider(minimum, maximum, step):
            let bounded = min(max(value.doubleValue, minimum), maximum)
            return NSNumber(value: (bounded / step).rounded() * step)
        case let .selection(choices):
            guard choices.contains(where: { $0.value == value.intValue }) else {
                throw SetupError("Unsupported value for \(tweak.title).")
            }
            return NSNumber(value: value.intValue)
        }
    }

    @discardableResult
    public func apply(_ tweak: TweakDescriptor, value: NSNumber) throws -> TweakChangeResult {
        let prepared = try validate(tweak, value: value)
        let lock = try SetupLock(paths: paths)
        defer { withExtendedLifetime(lock) {} }
        let transaction = try journal.begin(tweak.id)
        let profileService = MacOSPreferenceService(paths: paths, journal: journal, runner: runner)
        do {
            let value: Any? = Self.usesSystemDefault(tweak, value: prepared) ? nil : prepared
            let profile = try profileService.profile().updating(domain: tweak.domain, key: tweak.key, value: value)
            let setting = profile.settings.first { $0.domain == tweak.domain && $0.key == tweak.key }!
            _ = try profileService.apply(profile, transaction: transaction, settingID: setting.id)
            try journal.finish(transaction)
        } catch {
            try journal.restore(transaction)
            throw error
        }
        return TweakChangeResult(transaction: transaction, refreshWarning: refreshed(tweak))
    }

    @discardableResult
    public func resetToSystemDefault(_ tweak: TweakDescriptor) throws -> TweakChangeResult {
        let lock = try SetupLock(paths: paths)
        defer { withExtendedLifetime(lock) {} }
        let transaction = try journal.begin(tweak.id + ".reset")
        let profileService = MacOSPreferenceService(paths: paths, journal: journal, runner: runner)
        do {
            let profile = try profileService.profile().updating(domain: tweak.domain, key: tweak.key, value: nil)
            let setting = profile.settings.first { $0.domain == tweak.domain && $0.key == tweak.key }!
            _ = try profileService.apply(profile, transaction: transaction, settingID: setting.id)
            try journal.finish(transaction)
        } catch {
            try journal.restore(transaction)
            throw error
        }
        return TweakChangeResult(transaction: transaction, refreshWarning: refreshed(tweak))
    }

    @discardableResult
    public func restore(_ transaction: String, tweak: TweakDescriptor) throws -> String? {
        let lock = try SetupLock(paths: paths)
        defer { withExtendedLifetime(lock) {} }
        try journal.restore(transaction)
        return refreshed(tweak)
    }

}
