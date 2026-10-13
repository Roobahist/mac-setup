import Foundation
import Darwin
import MacSetupCore

let help = """
mac-setup 0.2.0 | interactive setup for your Mac

Usage:
  mac-setup                     Open the interactive keyboard-driven checklist
  mac-setup list                List task IDs
  mac-setup status              Inspect the current setup (read-only)
  mac-setup plan [task IDs]      Preview tasks and prerequisites (read-only)
  mac-setup setup [task IDs]     Apply selected tasks with individual prompts
  mac-setup setup --all          Walk through all tasks (including unfinished)
  mac-setup setup --preset minimal    Run a curated selection
  mac-setup profiles             Show available selection presets
  mac-setup dotfiles status      Inspect local public dotfiles checkout
  mac-setup dotfiles update      Pull new dotfiles using Git fast-forward
  mac-setup update              Reapply previously installed bundled profiles
  mac-setup backups             List recovery records
  mac-setup restore [backup ID]  Restore one record (latest by default)

Options:
  --preset NAME                 complete, minimal, productivity, developer
  --dry-run                     Preview instead of making changes
  --yes                         Approve automatic tasks; guided tasks stay pending
  --image PATH                  Choose an image for wallpaper-colors
  --force                       With restore only: discard edits made after setup
  --help                        Show help
  --version                     Show version

Restore covers recorded config/preference changes, not installed apps or manual
Settings changes. Backups contain local data; do not publish them.
"""

struct Options {
    var command = "menu"
    var ids: [String] = []
    var all = false
    var preset: SetupPreset?
    var dryRun = false
    var yes = false
    var force = false
    var image: URL?

    init(_ arguments: [String]) throws {
        var args = arguments
        if args.contains("--help") || args.first == "help" { command = "help"; return }
        if args.contains("--version") { command = "version"; return }
        if let first = args.first, !first.hasPrefix("--") { command = args.removeFirst() }
        let commands = ["menu", "list", "status", "plan", "setup", "update", "backups", "restore", "profiles", "dotfiles"]
        guard commands.contains(command) else { throw SetupError("Unknown command '\(command)'. Run mac-setup --help.") }
        while !args.isEmpty {
            let value = args.removeFirst()
            switch value {
            case "--all": all = true
            case "--preset":
                guard !args.isEmpty, let parsed = SetupPreset(rawValue: args.removeFirst()) else {
                    throw SetupError("--preset requires complete, minimal, productivity, or developer.")
                }
                preset = parsed
            case "--dry-run": dryRun = true
            case "--yes": yes = true
            case "--force": force = true
            case "--image":
                guard !args.isEmpty, !args[0].hasPrefix("--") else { throw SetupError("--image requires an image path.") }
                image = URL(fileURLWithPath: (args.removeFirst() as NSString).expandingTildeInPath)
            default:
                guard !value.hasPrefix("--") else { throw SetupError("Unknown option '\(value)'.") }
                ids.append(value)
            }
        }
        if force && command != "restore" { throw SetupError("--force is only valid with restore.") }
        if all && !["setup", "plan"].contains(command) { throw SetupError("--all is only valid with setup or plan.") }
        if all && !ids.isEmpty { throw SetupError("Use --all or task IDs, not both.") }
        if preset != nil && (all || !ids.isEmpty) {
            throw SetupError("Use --preset on its own, not with --all or task IDs.")
        }
        if preset != nil && !["menu", "setup", "plan"].contains(command) {
            throw SetupError("--preset applies only to setup or plan.")
        }
        if image != nil && !["setup", "plan"].contains(command) { throw SetupError("--image is only valid with setup or plan.") }
        if ["status", "list", "backups", "menu", "profiles"].contains(command) && !ids.isEmpty { throw SetupError("\(command) takes no task IDs.") }
        if command == "restore" && ids.count > 1 { throw SetupError("Restore one backup at a time, newest first.") }
        if command == "update" && !ids.isEmpty { throw SetupError("update takes no IDs; use setup for selected profiles.") }
        if command == "dotfiles" && (ids.count > 1 || (ids.first != nil && !["status", "update"].contains(ids[0]))) {
            throw SetupError("Use mac-setup dotfiles status or mac-setup dotfiles update.")
        }
    }
}

func ask(_ prompt: String, defaultYes: Bool = false) -> Bool {
    print(prompt + (defaultYes ? " [Y/n] " : " [y/N] "), terminator: "")
    guard let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
    return answer == "y" || answer == "yes" || (answer.isEmpty && defaultYes)
}

func showList() {
    var category = ""
    for (index, task) in Catalog.tasks.enumerated() {
        if category != task.category { category = task.category; print("\n\(category)") }
        print("  \(index + 1). \(task.id) — \(task.title)\(task.guided ? " (guided)" : "")")
    }
}

func showPreview(_ task: SetupTask, engine: Engine) throws {
    print("\n\(task.title) [\(task.id)]")
    for line in try engine.preview(task) { print("  " + line) }
}

func selectedIDs(_ options: Options, engine: Engine) throws -> [String] {
    if options.all { return Catalog.tasks.map(\.id) }
    if let preset = options.preset {
        return TaskPickerState(preset: preset).orderedSelection
    }
    if !options.ids.isEmpty { return options.ids }
    if options.command == "plan" { return TaskPickerState().orderedSelection }
    var picker = TaskPickerUI(engine: engine)
    return try picker.run() ?? []
}

func setup(_ ids: [String], engine: Engine, options: Options) throws {
    let tasks = try Catalog.ordered(ids)
    if tasks.isEmpty { print("No tasks selected."); return }
    if options.dryRun || options.command == "plan" {
        print("Preview only. Prerequisites are included; no files, settings, apps or permissions will change.")
        for task in tasks { try showPreview(task, engine: engine) }
        return
    }
    guard options.yes || isatty(STDIN_FILENO) != 0 else { throw SetupError("Use an interactive terminal or --yes for automatic tasks.") }
    let lock = try SetupLock(paths: engine.paths)
    defer { withExtendedLifetime(lock) {} }
    var blocked = Set<String>()
    var failures = 0
    for task in tasks {
        if task.dependencies.contains(where: blocked.contains) {
            print("\nPending: \(task.title) (a prerequisite was skipped or failed).")
            blocked.insert(task.id); continue
        }
        do {
            let state = try engine.state(task)
            if state == .done || state == .confirmed {
                print("\n\(state.rawValue): \(task.title)")
                continue
            }
            try showPreview(task, engine: engine)
            if task.guided {
                if options.yes { print("  Guided task stays pending in --yes mode."); blocked.insert(task.id); continue }
                if ask("Open the app or settings now?") { try engine.openGuide(task) }
                if task.id == "homebrew" {
                    if try ask("Check whether the prerequisite is ready?") && engine.state(task) == .done {
                        print("Verified: \(task.title)"); continue
                    }
                    print("Still pending."); blocked.insert(task.id)
                } else if task.id == "wallpaper-watcher" || task.id == "dock-special-items" {
                    print("This task contains unimplemented items and remains pending.")
                    blocked.insert(task.id)
                } else if ask("Have you completed and tested these steps?") {
                    try engine.confirm(task); print("Recorded as user confirmed; not automatically verified.")
                } else { blocked.insert(task.id) }
            } else {
                if options.yes || ask("Apply this task?") {
                    let id = try engine.apply(task, image: options.image)
                    print("Applied. Recovery record: \(id)")
                } else { blocked.insert(task.id) }
            }
        } catch {
            failures += 1; blocked.insert(task.id)
            fputs("\nTask failed: \(task.id)\n\(error)\n", stderr)
        }
    }
    print("\nChecklist finished: \(blocked.count) pending or failed task(s).")
    if failures > 0 { throw SetupError("\(failures) task(s) failed. Review the recovery records before retrying.") }
}

do {
    var options = try Options(Array(CommandLine.arguments.dropFirst()))
    if options.command == "help" { print(help); exit(0) }
    if options.command == "version" { print("0.2.0"); exit(0) }
    guard getuid() != 0 else { throw SetupError("Run mac-setup as your normal user, not with sudo. Individual installers request privileges themselves.") }
    let engine = try Engine()
    switch options.command {
    case "list": showList()
    case "profiles":
        for preset in SetupPreset.allCases {
            let count = TaskPickerState(preset: preset).selectedCount
            print("  \(preset.rawValue): \(count) tasks. \(preset.summary)")
        }
    case "dotfiles":
        let action = options.ids.first ?? "status"
        print("Public dotfiles checkout: \(engine.dotfiles.source.checkout.path)")
        if action == "status" {
            print("Checkout: \(engine.dotfiles.status().rawValue)")
            let configurable = Set(Catalog.tasks.flatMap { task -> [String] in
                if case let .profile(directories) = task.action { return directories }
                return []
            })
            for name in engine.dotfiles.source.folders where configurable.contains(name) {
                let connected = engine.dotfiles.source.isLinked(name, config: engine.paths.config)
                print("  \(name): \(connected ? "linked" : "not linked")")
            }
        } else {
            guard options.yes || (isatty(STDIN_FILENO) != 0 &&
                ask("Pull the public dot-files checkout (fast-forward only)?")) else {
                print("Cancelled."); break
            }
            let lock = try SetupLock(paths: engine.paths)
            defer { withExtendedLifetime(lock) {} }
            try engine.dotfiles.update()
            print("Dotfiles updated. Linked application configurations use the new files.")
        }
    case "status":
        print("mac-setup — current state (read-only)")
        var failures = 0
        for task in Catalog.tasks {
            do { print("\(try engine.state(task).rawValue): \(task.id) — \(task.title)") }
            catch { failures += 1; print("Could not inspect: \(task.id) — \(error)") }
        }
        if failures > 0 { throw SetupError("\(failures) status check(s) could not be completed.") }
    case "backups":
        for transaction in engine.journal.transactions.reversed() {
            let state = transaction.changes.isEmpty ? "no reversible changes" : (transaction.changes.allSatisfy(\.restored) ? "restored" : (transaction.complete ? "applied" : "incomplete"))
            print("\(transaction.id)  \(transaction.task)  \(transaction.date.ISO8601Format())  \(state)")
        }
        if engine.journal.transactions.isEmpty { print("No recovery records yet.") }
    case "restore":
        let id = options.ids.first ?? engine.journal.transactions.last(where: { $0.changes.contains(where: { !$0.restored }) })?.id
        guard let id else { throw SetupError("No unrestored backup found.") }
        guard let record = engine.journal.transactions.first(where: { $0.id == id }) else { throw SetupError("Unknown backup: \(id)") }
        print("Restore \(record.task) from \(id):")
        for change in record.changes where !change.restored { print("  \(change.target) \(change.key ?? "")") }
        if options.force { print("--force will discard later edits to the recorded targets.") }
        if options.dryRun { print("Preview only; nothing restored."); break }
        guard options.yes || (isatty(STDIN_FILENO) != 0 && ask("Restore these recorded changes?")) else { print("Cancelled."); break }
        let lock = try SetupLock(paths: engine.paths)
        defer { withExtendedLifetime(lock) {} }
        if record.task == "vorssaint-profile", try engine.runner.run("/usr/bin/pgrep", ["-x", "Vorssaint"]).status == 0 { throw SetupError("Quit Vorssaint before restoring its preferences.") }
        try engine.journal.restore(id, force: options.force)
        print("Restored. Relaunch affected apps or log out to refresh preferences. Installed apps and guided Settings changes remain.")
    case "update":
        let ids = engine.updateTasks()
        print("Update uses the profiles bundled with this version of mac-setup. Install a newer CLI release to obtain newer profiles.")
        try setup(ids, engine: engine, options: options)
    case "plan", "setup": try setup(selectedIDs(options, engine: engine), engine: engine, options: options)
    default:
        guard isatty(STDIN_FILENO) != 0 else { print(help); exit(0) }
        print("mac-setup: choose your configuration. Changes are previewed before applying.")
        options.command = "setup"
        try setup(selectedIDs(options, engine: engine), engine: engine, options: options)
    }
} catch {
    fputs("mac-setup: \(error)\n", stderr)
    exit(1)
}
