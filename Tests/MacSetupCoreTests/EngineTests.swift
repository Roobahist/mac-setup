import XCTest
@testable import MacSetupCore

final class FakeRunner: CommandRunning {
    var preferences: [String: [String: Any]] = [:]
    var git: [String: [String]] = [:]
    var calls: [[String]] = []
    var failWrites = false
    var failWatcherStart = false
    var jobs = Set<String>()
    var disabledJobs = Set<String>()
    var managedPackages = Set<String>()
    var homebrewInstalled = false
    var simulatedInstalledApps = Set<String>()
    var loginItemPaths = Set<String>()

    func run(_ executable: String, _ args: [String], interactive: Bool, input: Data?) throws -> CommandResult {
        calls.append([executable] + args)
        if executable == "/usr/bin/curl" {
            try Data("#!/bin/bash\nexit 0\n".utf8).write(to: URL(fileURLWithPath: args.last!))
            return CommandResult(status: 0)
        }
        if executable == "/bin/bash" && args.first?.hasSuffix("install.sh") == true {
            XCTAssertTrue(interactive)
            homebrewInstalled = true
            return CommandResult(status: 0)
        }
        if executable == "/fake/brew" {
            if args.first == "list" {
                return CommandResult(status: managedPackages.contains(args.last!) ? 0 : 1,
                                     output: Data((managedPackages.contains(args.last!) ? "1.0" : "").utf8))
            }
            if ["install", "reinstall"].contains(args.first ?? ""), let name = args.last {
                managedPackages.insert(name)
            }
            return CommandResult(status: 0)
        }
        if executable == "/bin/launchctl" {
            let label = args[1].components(separatedBy: "/").last!
            switch args[0] {
            case "print": return CommandResult(status: jobs.contains(label) ? 0 : 113)
            case "bootout": jobs.remove(label)
            case "disable": disabledJobs.insert(label)
            case "enable": disabledJobs.remove(label)
            case "bootstrap":
                let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
                let values = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
                if failWatcherStart && values["Label"] as? String == WallpaperWatcher.replacementLabel {
                    return CommandResult(status: 1, output: Data("simulated bootstrap failure".utf8))
                }
                jobs.insert(values["Label"] as! String)
            default: XCTFail("Unexpected launchctl command")
            }
            return CommandResult(status: 0)
        }
        if executable == "/usr/bin/osascript" {
            guard args.count == 4, args[0] == "-e" else { return CommandResult(status: 1) }
            let operation = args[2], path = args[3]
            let exists = loginItemPaths.contains(path)
            switch operation {
            case "check": return CommandResult(status: 0, output: Data((exists ? "present" : "missing").utf8))
            case "add":
                loginItemPaths.insert(path)
                return CommandResult(status: 0, output: Data((exists ? "present" : "added").utf8))
            case "remove":
                loginItemPaths.remove(path)
                return CommandResult(status: 0, output: Data((exists ? "removed" : "missing").utf8))
            default: return CommandResult(status: 1)
            }
        }
        if executable == "/usr/bin/defaults" {
            let operation = args[0], domain = args[1]
            if operation == "export" {
                return CommandResult(status: 0, output: try PropertyListSerialization.data(fromPropertyList: preferences[domain] ?? [:], format: .xml, options: 0))
            }
            if failWrites { return CommandResult(status: 1, output: Data("simulated failure".utf8)) }
            let key = args[2]
            if operation == "delete" { preferences[domain]?[key] = nil; return CommandResult(status: 0) }
            let value: Any
            switch args[3] {
            case "-bool":
                let bool = args[4].lowercased()
                guard ["true", "false", "yes", "no"].contains(bool) else {
                    return CommandResult(status: 255, output: Data("Invalid -bool argument".utf8))
                }
                value = bool == "true" || bool == "yes"
            case "-int": value = Int(args[4])!
            case "-float": value = Double(args[4])!
            case "-string": value = args[4]
            default: value = try PropertyListSerialization.propertyList(from: Data(args[3].utf8), format: nil)
            }
            preferences[domain, default: [:]][key] = value
            return CommandResult(status: 0)
        }
        if executable.hasSuffix("/git"), args.first == "-C", args.count >= 5,
           args[2] == "remote", args[3] == "get-url", args[4] == "origin" {
            return CommandResult(status: 0, output: Data("https://github.com/Roobahist/dot-files.git".utf8))
        }
        if executable == "/usr/bin/git" {
            let operation = args[2], key = args[3]
            switch operation {
            case "--get-all":
                guard let values = git[key] else { return CommandResult(status: 1) }
                return CommandResult(status: 0, output: Data(values.joined(separator: "\n").utf8))
            case "--replace-all": git[key] = [args[4]]
            case "--unset-all": git[key] = nil
            case "--add": git[key, default: []].append(args[4])
            default: XCTFail("Unexpected Git command: \(args)")
            }
            return CommandResult(status: 0)
        }
        if executable == "/usr/bin/pgrep" { return CommandResult(status: 1) }
        return CommandResult(status: 0)
    }
}

func isolatedAppPath(_ name: String, _ home: URL) -> String? {
    let path = home.appendingPathComponent("Applications/\(name).app").path
    return FileManager.default.fileExists(atPath: path) ? path : nil
}

final class EngineTests: XCTestCase {
    var home: URL!
    var paths: Paths!
    var runner: FakeRunner!
    var engine: Engine!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("mac-setup-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        paths = Paths(home: home)
        runner = FakeRunner()
        engine = try Engine(paths: paths, runner: runner, appResolver: isolatedAppPath)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    func write(_ relative: String, _ text: String) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }


    func testEssentialLoginItemsAreAdditiveAndReversible() throws {
        for name in StartupLoginItems.appNames {
            _ = try write("Applications/\(name).app/Contents/Info.plist", "placeholder")
        }
        let additional = "/Applications/Existing Utility.app"
        runner.loginItemPaths.insert(additional)
        let aero = home.appendingPathComponent("Applications/AeroSpace.app").path
        runner.loginItemPaths.insert(aero)
        let task = try Catalog.task("startup-login")

        XCTAssertEqual(try engine.state(task), .ready)
        let transaction = try engine.apply(task)
        let expected = Set(StartupLoginItems.appNames.map {
            home.appendingPathComponent("Applications/\($0).app").path
        })
        XCTAssertTrue(expected.isSubset(of: runner.loginItemPaths))
        XCTAssertTrue(runner.loginItemPaths.contains(additional))
        XCTAssertEqual(try engine.state(task), .done)

        // Existing entries must not be removed when restoring the transaction.
        try engine.journal.restore(transaction)
        XCTAssertEqual(runner.loginItemPaths, [aero, additional])
    }

    func testKarabinerStartupGUIAndOnlyItsDockPinAreRemovedAndRestorable() throws {
        let gui = try write("Applications/Karabiner-Elements.app/Contents/Info.plist", "app").deletingLastPathComponent().deletingLastPathComponent().path
        _ = try write("Applications/Raycast.app/Contents/Info.plist", "app")
        runner.loginItemPaths = [gui, "/Applications/Other Utility.app"]
        let keep: [String: Any] = ["tile-data": ["bundle-identifier": "com.apple.finder"]]
        let remove: [String: Any] = ["tile-data": ["bundle-identifier": "org.pqrs.Karabiner-Elements.Settings"]]
        runner.preferences["com.apple.dock"] = ["persistent-apps": [keep, remove], "unrelated": true]
        let task = try Catalog.task("startup-login")
        let old = try engine.journal.begin(task.id)
        try engine.journal.registerLoginItem(gui, transaction: old)
        try engine.journal.registerLoginItem(home.appendingPathComponent("Applications/Raycast.app").path, transaction: old)
        try engine.journal.finish(old)
        // A completed older setup must still offer the GUI-startup migration.
        XCTAssertEqual(try engine.state(task), .ready)
        let record = try engine.apply(task)
        XCTAssertFalse(StartupLoginItems.appNames.contains("Karabiner-Elements"))
        XCTAssertFalse(runner.loginItemPaths.contains(gui))
        XCTAssertTrue(runner.loginItemPaths.contains("/Applications/Other Utility.app"))
        let pins = runner.preferences["com.apple.dock"]?["persistent-apps"] as? [[String: Any]]
        XCTAssertEqual(pins?.count, 1)
        XCTAssertTrue(equalPreference(pins?.first, keep))
        XCTAssertEqual(runner.preferences["com.apple.dock"]?["unrelated"] as? Bool, true)
        XCTAssertEqual(try engine.state(task), .done)
        XCTAssertFalse(runner.calls.contains { $0.contains("bootout") || $0.contains("killall") && $0.contains("karabiner_grabber") })
        try engine.journal.restore(record)
        XCTAssertTrue(runner.loginItemPaths.contains(gui))
        XCTAssertEqual((runner.preferences["com.apple.dock"]?["persistent-apps"] as? [Any])?.count, 2)
    }

    func testWidgetHideDefaultAndLiveToggleDoNotChangeStageManager() throws {
        let task = try Catalog.task("desktop-widgets")
        guard !task.guided else { return }
        runner.preferences["com.apple.WindowManager"] = ["StandardHideWidgets": false, "StageManagerHideWidgets": false]
        XCTAssertEqual(try engine.state(task), .ready)
        _ = try engine.apply(task)
        XCTAssertEqual(runner.preferences["com.apple.WindowManager"]?["StandardHideWidgets"] as? Bool, true)
        XCTAssertEqual(try engine.state(task), .done)
        runner.preferences["com.apple.WindowManager"]?["StandardHideWidgets"] = false
        XCTAssertEqual(try engine.state(task), .ready)
        let descriptor = try XCTUnwrap(TweakRegistry.all.first { $0.id == "desktop.widgets" })
        let service = TweakService(journal: engine.journal, runner: runner, paths: paths)
        XCTAssertFalse(try service.value(for: descriptor).boolValue)
        _ = try service.apply(descriptor, value: true)
        XCTAssertTrue(try service.value(for: descriptor).boolValue)
        _ = try service.apply(descriptor, value: false)
        XCTAssertFalse(try service.value(for: descriptor).boolValue)
        XCTAssertEqual(runner.preferences["com.apple.WindowManager"]?["StageManagerHideWidgets"] as? Bool, false)
    }

    func testRaycastProfileHidesOnlyMainMenuIconAndRestoresIt() throws {
        let key = "NSStatusItem VisibleCC raycastIcon"
        runner.preferences["com.raycast.macos"] = [key: true, "statusBarIsVisible": true, "extension-menu-bar": true]
        let task = try Catalog.task("raycast-profile")
        XCTAssertEqual(try engine.state(task), .ready)
        let record = try engine.apply(task)
        XCTAssertEqual(runner.preferences["com.raycast.macos"]?[key] as? Bool, false)
        XCTAssertEqual(runner.preferences["com.raycast.macos"]?["statusBarIsVisible"] as? Bool, false)
        XCTAssertEqual(runner.preferences["com.raycast.macos"]?["extension-menu-bar"] as? Bool, true)
        XCTAssertEqual(try engine.state(task), .done)
        runner.preferences["com.raycast.macos"]?[key] = true
        XCTAssertEqual(try engine.state(task), .ready)
        runner.preferences["com.raycast.macos"]?[key] = false
        try engine.journal.restore(record)
        XCTAssertEqual(runner.preferences["com.raycast.macos"]?[key] as? Bool, true)
        XCTAssertEqual(runner.preferences["com.raycast.macos"]?["statusBarIsVisible"] as? Bool, true)
    }

    func testStartupScriptCompilesOnMacOS() throws {
        let output = home.appendingPathComponent("startup-login.scpt")
        let result = try ProcessRunner().run("/usr/bin/osacompile",
            ["-e", StartupLoginItems.script, "-o", output.path])
        XCTAssertEqual(result.status, 0, result.text)
    }

    func testNoStartupAppCreatesSpuriousLoginItem() throws {
        let task = try Catalog.task("startup-login")
        let transaction = try engine.apply(task)
        XCTAssertTrue(runner.loginItemPaths.isEmpty)
        XCTAssertEqual(engine.journal.transactions.first(where: { $0.id == transaction })?.changes.count, 0)
    }

    func testInterruptedCaskIsReinstalledAndRerunIsIdempotent() throws {
        let task = try Catalog.task("karabiner")
        runner.managedPackages.insert("karabiner-elements")
        engine = try Engine(paths: paths, runner: runner, appResolver: isolatedAppPath, tools: { $0 == "brew" ? "/fake/brew" : nil })

        // Homebrew's cask registry can survive a failed privileged pkg installer.
        XCTAssertEqual(try engine.state(task), .ready)
        XCTAssertThrowsError(try engine.apply(task)) { error in
            XCTAssertTrue(String(describing: error).contains("Installation could not be verified"))
        }
        XCTAssertTrue(runner.calls.contains {
            $0 == ["/fake/brew", "reinstall", "--cask", "karabiner-elements"]
        })
        let reinstallCount = runner.calls.filter { $0.first == "/fake/brew" && $0.dropFirst().first == "reinstall" }.count
        XCTAssertEqual(reinstallCount, 1)

        _ = try write("Applications/Karabiner-Elements.app/Contents/Info.plist", "fake app")
        XCTAssertEqual(try engine.state(task), .done)
        _ = try engine.apply(task)
        XCTAssertEqual(runner.calls.filter {
            $0.first == "/fake/brew" && ["install", "reinstall"].contains($0.dropFirst().first ?? "")
        }.count, 1)
    }

    func testInstalledFormulaIsSkippedWhenReapplying() throws {
        let task = try Catalog.task("atuin")
        runner.managedPackages.insert("atuin")
        engine = try Engine(paths: paths, runner: runner, appResolver: isolatedAppPath, tools: { $0 == "brew" ? "/fake/brew" : nil })
        XCTAssertEqual(try engine.state(task), .done)
        _ = try engine.apply(task)
        XCTAssertFalse(runner.calls.contains {
            $0.first == "/fake/brew" && ["install", "reinstall"].contains($0.dropFirst().first ?? "")
        })
    }

    func testTomitoAppStoreTaskIsGuidedUntilInstalled() throws {
        let task = try Catalog.task("tomito")
        XCTAssertTrue(task.guided)
        XCTAssertEqual(try engine.state(task), .guided)
        let preview = try engine.preview(task).joined(separator: "\n")
        XCTAssertTrue(preview.contains("Mac App Store"))
        try engine.openGuide(task)
        XCTAssertTrue(runner.calls.contains {
            $0 == ["/usr/bin/open", "macappstore://itunes.apple.com/app/id1526042938"]
        })
        let url = try write("Applications/Tomito.app/Contents/Info.plist", "fake")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try engine.state(task), .done)
    }

    func testEditedProfileDetachesSymlinkAndRestoreReconnectsWithoutEditingSource() throws {
        let original = try write("private/aerospace.toml", "personal original\n")
        let extra = try write("private/local-note.txt", "keep this\n")
        try FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        let target = paths.config.appendingPathComponent("aerospace")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: original.deletingLastPathComponent())
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .ready)
        let transaction = try engine.apply(Catalog.task("aerospace-profile"))
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .done)
        XCTAssertFalse(engine.dotfiles.isSymlink(target))
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("local-note.txt")), "keep this\n")
        XCTAssertEqual(try String(contentsOf: original), "personal original\n")
        XCTAssertEqual(try String(contentsOf: extra), "keep this\n")
        try engine.journal.restore(transaction)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: target.path),
                       original.deletingLastPathComponent().path)
    }

    func testProfileDetachmentPreservesRelativeExtraLinks() throws {
        let source = try write("private/config/aerospace.toml", "personal\n").deletingLastPathComponent()
        let extra = try write("private/shared/note.txt", "linked extra\n")
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("note.txt").path,
                                                   withDestinationPath: "../shared/note.txt")
        try FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        let target = paths.config.appendingPathComponent("aerospace")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
        let transaction = try engine.apply(Catalog.task("aerospace-profile"))
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("note.txt")), "linked extra\n")
        XCTAssertEqual(try String(contentsOf: extra), "linked extra\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: source.appendingPathComponent("note.txt").path), "../shared/note.txt")
        try engine.journal.restore(transaction)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: target.path), source.path)
    }

    func testCoordinatedWorkspaceApplyRecoversLinkedConfigsAndCanRetry() throws {
        let source = try write("private/aerospace/aerospace.toml", "original source\n").deletingLastPathComponent()
        let legacy = try write(".aerospace.toml", "legacy source\n")
        try FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        let target = paths.config.appendingPathComponent("aerospace")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
        var layout = WorkspaceConfiguration.defaultLayout
        try layout.renameWorkspace("ai", to: "Research")
        let tasks = try Catalog.ordered(["aerospace-profile", "sketchybar-profile"], includingDependencies: false)
        // Failure after AeroSpace has detached its link must restore both locations.
        let failing = try Engine(paths: paths, runner: runner, displayHelper: nil, tools: { _ in nil })
        XCTAssertThrowsError(try failing.applyConfiguration(layout: layout, tasks: tasks)) { error in
            XCTAssertTrue(String(describing: error).contains("Previous files and saved settings were restored"))
            XCTAssertFalse(String(describing: error).contains("Run mac-setup restore"))
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: target.path), source.path)
        XCTAssertEqual(try String(contentsOf: legacy), "legacy source\n")
        XCTAssertFalse(Journal.exists(WorkspaceConfiguration.path(in: paths)))
        let helper = try write("helpers/display", "test helper")
        let retry = try Engine(paths: paths, runner: runner, displayHelper: helper, tools: { _ in nil })
        _ = try retry.applyConfiguration(layout: layout, tasks: tasks)
        XCTAssertFalse(retry.dotfiles.isSymlink(target))
        XCTAssertFalse(Journal.exists(legacy))
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("aerospace.toml")), "original source\n")
        XCTAssertEqual(try WorkspaceConfiguration.load(from: paths), layout)
        XCTAssertTrue(try String(contentsOf: target.appendingPathComponent("aerospace.toml")).contains("research"))
        XCTAssertEqual(try retry.state(Catalog.task("aerospace-profile")), .done)
        XCTAssertEqual(try retry.state(Catalog.task("sketchybar-profile")), .done)
    }

    func testLinkedDotfilesPreservesAndRestoresOldConfiguration() throws {
        let source = DotfilesSource(home: home, folders: ["aerospace", "alacritty"])
        let checkout = source.checkout
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)
        _ = try write("dot-files/aerospace/aerospace.toml", "portable settings")
        _ = try write("dot-files/alacritty/alacritty.toml", "portable settings")
        let old = try write(".config/aerospace/personal.toml", "old settings")
        engine = try Engine(paths: paths, runner: runner, appResolver: isolatedAppPath, dotfilesSource: source)
        XCTAssertEqual(try engine.state(Catalog.task("dotfiles-linked")), .done)

        _ = try engine.apply(Catalog.task("dotfiles-linked"))
        XCTAssertEqual(try engine.state(Catalog.task("dotfiles-linked")), .done)
        XCTAssertFalse(source.isLinked("aerospace", config: paths.config))
        XCTAssertFalse(source.isLinked("alacritty", config: paths.config))

        let first = try engine.apply(Catalog.task("aerospace-profile"))
        let second = try engine.apply(Catalog.task("alacritty-profile"))
        XCTAssertFalse(source.isLinked("aerospace", config: paths.config))
        XCTAssertTrue(source.isLinked("alacritty", config: paths.config))
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))

        try engine.journal.restore(second)
        try engine.journal.restore(first)
        XCTAssertEqual(try String(contentsOf: old), "old settings")
        XCTAssertFalse(source.isLinked("aerospace", config: paths.config))
        XCTAssertFalse(source.isLinked("alacritty", config: paths.config))
    }

    func testRestoreRefusesLaterEditsBeforeChangingOtherFiles() throws {
        let first = try write("first", "original")
        let second = try write("second", "original")
        let id = try engine.journal.begin("test")
        try engine.journal.write(first, data: Data("applied".utf8), transaction: id)
        try engine.journal.write(second, data: Data("applied".utf8), transaction: id)
        try Data("later edit".utf8).write(to: second)
        XCTAssertThrowsError(try engine.journal.restore(id))
        XCTAssertEqual(try String(contentsOf: first), "applied")
        XCTAssertEqual(try String(contentsOf: second), "later edit")
        try engine.journal.restore(id, force: true)
        XCTAssertEqual(try String(contentsOf: first), "original")
        XCTAssertEqual(try String(contentsOf: second), "original")
    }

    func testPreferencesRestoreMissingAndComplexValuesWithoutTouchingUnrelatedKeys() throws {
        runner.preferences["test"] = ["list": [["name": "keep", "nested": [1, 2]]], "unrelated": "untouched"]
        let id = try engine.journal.begin("test")
        try engine.journal.setPreference("test", "new", true, transaction: id)
        try engine.journal.setPreference("test", "list", [String](), transaction: id)
        try engine.journal.finish(id)
        try engine.journal.restore(id)
        XCTAssertNil(runner.preferences["test"]?["new"])
        XCTAssertTrue(equalPlist(runner.preferences["test"]?["list"], [["name": "keep", "nested": [1, 2]]]))
        XCTAssertEqual(runner.preferences["test"]?["unrelated"] as? String, "untouched")
    }

    func testBlueAccentClearsOverrideAndUndoRestoresPreviousColor() throws {
        runner.preferences["NSGlobalDomain"] = ["AppleAccentColor": 6]
        let accent = try XCTUnwrap(TweakRegistry.all.first { $0.id == "appearance.accent" })
        let service = TweakService(journal: engine.journal, runner: runner, paths: paths)
        let outcome = try service.apply(accent, value: NSNumber(value: 4))
        XCTAssertNil(runner.preferences["NSGlobalDomain"]?["AppleAccentColor"])
        XCTAssertNil(outcome.refreshWarning)
        try service.restore(outcome.transaction, tweak: accent)
        XCTAssertEqual((runner.preferences["NSGlobalDomain"]?["AppleAccentColor"] as? NSNumber)?.intValue, 6)
    }

    func testRecentAppsToggleLeavesDockVisibilityAndDelayUnchanged() throws {
        runner.preferences["com.apple.dock"] = [
            "autohide": true, "autohide-delay": 0.0, "show-recents": true
        ]
        let tweak = try XCTUnwrap(TweakRegistry.all.first { $0.id == "dock.recents" })
        let service = TweakService(journal: engine.journal, runner: runner, paths: paths)
        let outcome = try service.apply(tweak, value: NSNumber(value: false))
        XCTAssertEqual((runner.preferences["com.apple.dock"]?["show-recents"] as? NSNumber)?.boolValue, false)
        XCTAssertEqual((runner.preferences["com.apple.dock"]?["autohide"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((runner.preferences["com.apple.dock"]?["autohide-delay"] as? NSNumber)?.doubleValue, 0)
        try service.restore(outcome.transaction, tweak: tweak)
        XCTAssertEqual((runner.preferences["com.apple.dock"]?["show-recents"] as? NSNumber)?.boolValue, true)
    }

    func testMissionControlWritesValidBooleanArgumentsAndCanRestore() throws {
        // The real defaults CLI accepts true/false, not NSNumber.stringValue's 0/1.
        let task = try Catalog.task("mission-control")
        let service = engine.macOSPreferences
        let explicit = try service.profile()
            .updating(domain: "com.apple.dock", key: "mru-spaces", value: false)
            .updating(domain: "com.apple.spaces", key: "spans-displays", value: false)
        try FileManager.default.createDirectory(at: service.profileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try explicit.encoded().write(to: service.profileURL)
        let record = try engine.apply(task)
        let writes = runner.calls.filter {
            $0.first == "/usr/bin/defaults" && $0.count >= 6 &&
            $0[1] == "write" && $0[4] == "-bool"
        }
        XCTAssertTrue(writes.contains {
            $0[2] == "com.apple.dock" && $0[3] == "mru-spaces" && $0[5] == "false"
        })
        XCTAssertTrue(writes.contains {
            $0[2] == "com.apple.spaces" && $0[3] == "spans-displays" && $0[5] == "false"
        })
        XCTAssertEqual(try engine.state(task), .done)
        try engine.journal.restore(record)
        XCTAssertNil(runner.preferences["com.apple.dock"]?["mru-spaces"])
        XCTAssertNil(runner.preferences["com.apple.spaces"]?["spans-displays"])
    }

    func testBooleanPreferencesRoundTripWithActualMacOSDefaults() throws {
        // Use a disposable domain rather than editing system or app preferences.
        let domain = home.appendingPathComponent("boolean-preferences").path
        let realRunner = ProcessRunner()
        defer { _ = try? realRunner.run("/usr/bin/defaults", ["delete", domain]) }
        try realRunner.checked("/usr/bin/defaults", ["write", domain, "enabled", "-bool", "true"])
        let actualJournal = try Journal(paths: paths, runner: realRunner)
        let record = try actualJournal.begin("boolean-real-defaults")
        try actualJournal.setPreference(domain, "enabled", false, transaction: record)
        XCTAssertTrue(equalPlist(try actualJournal.preference(domain, "enabled"), false))
        try actualJournal.finish(record)
        try actualJournal.restore(record)
        XCTAssertTrue(equalPlist(try actualJournal.preference(domain, "enabled"), true))
    }

    func testFailedPreferenceWriteHasRecoverableRecord() throws {
        runner.failWrites = true
        XCTAssertThrowsError(try engine.apply(Catalog.task("dark-mode")))
        let record = try XCTUnwrap(engine.journal.transactions.last)
        XCTAssertFalse(record.complete)
        XCTAssertEqual(record.changes.filter { $0.kind == .preference }.count, 1)
        runner.failWrites = false
        try engine.journal.restore(record.id)
        XCTAssertNil(runner.preferences["NSGlobalDomain"]?["AppleInterfaceStyle"])
    }

    func testGitIgnorePreservesExistingRulesAndRestoresBothFileAndSetting() throws {
        let file = try write("custom-ignore", "# personal\nprivate-file\n.DS_Store\n")
        runner.git["core.excludesfile"] = [file.path]
        let id = try engine.apply(Catalog.task("git-ignore"))
        let updated = try String(contentsOf: file)
        XCTAssertTrue(updated.contains("private-file"))
        XCTAssertEqual(updated.components(separatedBy: ".DS_Store").count, 2)
        XCTAssertEqual(runner.git["core.excludesfile"], [file.path])
        XCTAssertEqual(try engine.state(Catalog.task("git-ignore")), .done)
        try engine.journal.restore(id)
        XCTAssertEqual(try String(contentsOf: file), "# personal\nprivate-file\n.DS_Store\n")
        XCTAssertEqual(runner.git["core.excludesfile"], [file.path])
    }

    func testGitIgnoreNewFileAndGitSettingAreRemovedOnRestore() throws {
        let id = try engine.apply(Catalog.task("git-ignore"))
        XCTAssertEqual(runner.git["core.excludesfile"], [home.appendingPathComponent(".gitignore_global").path])
        try engine.journal.restore(id)
        XCTAssertNil(runner.git["core.excludesfile"])
        XCTAssertFalse(Journal.exists(home.appendingPathComponent(".gitignore_global")))
    }

    func testAtuinInitializationIsNotDuplicatedAndExistingConfigSurvives() throws {
        let file = try write(".zshrc", "export EDITOR=vim\n")
        let first = try engine.apply(Catalog.task("atuin-shell"))
        _ = try engine.apply(Catalog.task("atuin-shell"))
        let result = try String(contentsOf: file)
        XCTAssertEqual(result.components(separatedBy: "atuin init zsh").count, 2)
        XCTAssertTrue(result.hasPrefix("export EDITOR=vim\n"))
        try engine.journal.restore(first)
        XCTAssertEqual(try String(contentsOf: file), "export EDITOR=vim\n")
    }

    func testParentSymlinkIsRejected() throws {
        let external = home.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: paths.config, withDestinationURL: external)
        XCTAssertThrowsError(try engine.apply(Catalog.task("atuin-profile")))
        XCTAssertFalse(Journal.exists(external.appendingPathComponent("atuin")))
    }

    func testCommentedAtuinInitializationDoesNotCountAsEnabled() throws {
        let file = try write(".zshrc", "# eval \"$(atuin init zsh)\"\n")
        XCTAssertEqual(try engine.state(Catalog.task("atuin-shell")), .ready)
        _ = try engine.apply(Catalog.task("atuin-shell"))
        XCTAssertTrue(try String(contentsOf: file).contains("# >>> mac-setup: atuin >>>"))
        XCTAssertEqual(try engine.state(Catalog.task("atuin-shell")), .done)
    }

    func testRelativeGlobalIgnorePathIsRejectedWithoutChangingFiles() throws {
        runner.git["core.excludesfile"] = ["relative-ignore"]
        XCTAssertThrowsError(try engine.apply(Catalog.task("git-ignore")))
        XCTAssertEqual(runner.git["core.excludesfile"], ["relative-ignore"])
        XCTAssertFalse(Journal.exists(home.appendingPathComponent(".gitignore_global")))
    }

    func testAeroSpaceLegacyConfigIsJournaledAndRestored() throws {
        let file = try write(".aerospace.toml", "personal")
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .ready)
        XCTAssertTrue(try engine.preview(Catalog.task("aerospace-profile")).joined().contains("legacy"))
        let transaction = try engine.apply(Catalog.task("aerospace-profile"))
        XCTAssertFalse(Journal.exists(file))
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .done)
        try engine.journal.restore(transaction)
        XCTAssertEqual(try String(contentsOf: file), "personal")
    }

    func testGuidedTasksAreNotAutomaticallyApplied() throws {
        XCTAssertThrowsError(try engine.apply(Catalog.task("finder-sidebar")))
        XCTAssertTrue(engine.journal.transactions.isEmpty)
        try engine.confirm(Catalog.task("finder-sidebar"))
        XCTAssertEqual(try engine.state(Catalog.task("finder-sidebar")), .confirmed)
    }

    func testDependenciesAreOrderedAndUnknownTasksRejected() throws {
        let ids = try Catalog.ordered(["sketchybar-start", "aerospace"]).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertLessThan(ids.firstIndex(of: "aerospace-profile")!, ids.firstIndex(of: "sketchybar-profile")!)
        XCTAssertThrowsError(try Catalog.ordered(["not-a-task"]))
    }

    func testVorssaintProfileDoesNotCopyPrivateContent() throws {
        let preferences = try engine.vorssaintPreferences()
        let keys = Set(preferences.map(\.key))
        XCTAssertTrue(keys.contains("autoQuitEnabled"))
        XCTAssertTrue(keys.contains("launchAtLoginWanted"))
        XCTAssertGreaterThan(keys.count, 700, "The full portable export should be imported.")
        XCTAssertTrue(equalPlist(preferences.first(where: { $0.key == "autoQuitEnabled" })?.value, true))
        for forbidden in ["shelfItems", "textSnippets", "commandBarUsage", "notchDownloadsFolderBookmark", "appVolumes", "NSOSPLastRootDirectory"] {
            XCTAssertFalse(keys.contains(forbidden))
        }
        runner.preferences["com.vorssaint.utils"] = ["textSnippets": Data("private".utf8)]
        let id = try engine.apply(Catalog.task("vorssaint-profile"))
        XCTAssertEqual(runner.preferences["com.vorssaint.utils"]?["textSnippets"] as? Data, Data("private".utf8))
        try engine.journal.restore(id)
        XCTAssertEqual(runner.preferences["com.vorssaint.utils"]?["textSnippets"] as? Data, Data("private".utf8))
    }

    func testReadOnlyPlanInputsDoNotCreateState() throws {
        _ = try Catalog.tasks.map { try engine.preview($0) }
        XCTAssertFalse(Journal.exists(paths.state))
        XCTAssertTrue(runner.calls.allSatisfy { $0.first == "/usr/bin/defaults" && $0[1] == "export" })
    }

    func testLockRefusesConcurrentMutation() throws {
        let first = try SetupLock(paths: paths)
        XCTAssertThrowsError(try SetupLock(paths: paths))
        withExtendedLifetime(first) {}
    }
    func existingWatcher() throws -> URL {
        let binary = try write("Applications/WallpaperAccentWatcher.app/Contents/MacOS/WallpaperAccentWatcher", "existing app")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        return binary
    }

    func legacyWatcherPlist(image: String? = nil) throws -> URL {
        let binary = try existingWatcher()
        var values: [String: Any] = ["Label": WallpaperWatcher.label,
                                    "ProgramArguments": [binary.path], "RunAtLoad": true]
        if let image { values["EnvironmentVariables"] = ["WALLPAPER_ACCENT_IMAGE": image] }
        let plist = home.appendingPathComponent("Library/LaunchAgents/\(WallpaperWatcher.label).plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: plist)
        return plist
    }

    func testRunningLegacyWatcherMigratesAndRestoresWithoutReplacingApp() throws {
        let legacy = try legacyWatcherPlist(image: "/tmp/pinned-wallpaper.jpg")
        let original = try Data(contentsOf: legacy)
        let helper = try bundledWatcher()
        runner.jobs.insert(WallpaperWatcher.label)
        let task = try Catalog.task("wallpaper-watcher")
        XCTAssertEqual(try engine.state(task), .ready)
        let id = try engine.apply(task)
        XCTAssertFalse(Journal.exists(legacy))
        XCTAssertEqual(runner.jobs, [WallpaperWatcher.replacementLabel])
        let plist = home.appendingPathComponent("Library/LaunchAgents/\(WallpaperWatcher.replacementLabel).plist")
        let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        XCTAssertEqual(values["ProgramArguments"] as? [String], [helper.path])
        XCTAssertEqual((values["EnvironmentVariables"] as? [String: String])?["WALLPAPER_ACCENT_IMAGE"], "/tmp/pinned-wallpaper.jpg")
        let stop = runner.calls.firstIndex { $0.dropFirst().first == "bootout" }!
        let start = runner.calls.firstIndex { $0.dropFirst().first == "bootstrap" }!
        XCTAssertLessThan(stop, start)
        XCTAssertEqual(try engine.state(task), .done)
        try engine.journal.restore(id)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        XCTAssertEqual(runner.jobs, [WallpaperWatcher.label])
        XCTAssertFalse(Journal.exists(plist))
        let binary = home.appendingPathComponent("Applications/WallpaperAccentWatcher.app/Contents/MacOS/WallpaperAccentWatcher")
        XCTAssertEqual(try String(contentsOf: binary), "existing app")
    }

    func testMigrationAddsCacheSupportWithoutReplacingPersonalPaletteAndRestoresIt() throws {
        let colors = try write("sketchybar-personal/colors.sh", "export BAR_COLOR=0xff123456\nexport HIGHLIGHT_COLOR=0xffABCDEF\n")
        let linked = paths.config.appendingPathComponent("sketchybar/plugins/colors.sh")
        try FileManager.default.createDirectory(at: linked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: colors)
        let before = try Data(contentsOf: colors)
        _ = try legacyWatcherPlist()
        _ = try bundledWatcher()
        let id = try engine.apply(Catalog.task("wallpaper-watcher"))
        let updated = try String(contentsOf: colors)
        XCTAssertTrue(updated.hasPrefix(String(decoding: before, as: UTF8.self)))
        XCTAssertTrue(updated.contains("sketchybar/highlight-color"))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.path), colors.path)
        _ = try engine.apply(Catalog.task("wallpaper-watcher"))
        XCTAssertEqual(try String(contentsOf: colors), updated)
        try engine.journal.restore(id)
        XCTAssertEqual(try Data(contentsOf: colors), before)
    }

    func testStoppedLegacyWatcherMigratesAndRestoreLeavesItStopped() throws {
        let legacy = try legacyWatcherPlist()
        _ = try bundledWatcher()
        let id = try engine.apply(Catalog.task("wallpaper-watcher"))
        XCTAssertFalse(Journal.exists(legacy))
        try engine.journal.restore(id)
        XCTAssertTrue(Journal.exists(legacy))
        XCTAssertTrue(runner.jobs.isEmpty)
    }

    func bundledWatcher() throws -> URL {
        let helper = try write("Applications/Mac Setup.app/Contents/Helpers/mac-setup-wallpaper-watcher", "bundled helper")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return helper
    }

    func testBundledWallpaperWatcherAutomaticallyRegistersAndRestores() throws {
        let helper = try bundledWatcher()
        let task = try Catalog.task("wallpaper-watcher")
        XCTAssertEqual(try engine.state(task), .ready)
        let recovery = try engine.apply(task)
        let label = WallpaperWatcher.replacementLabel
        let plist = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
        let values = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plist), format: nil) as! [String: Any]
        XCTAssertEqual(values["Label"] as? String, label)
        XCTAssertEqual(values["ProgramArguments"] as? [String], [helper.path])
        XCTAssertTrue(runner.jobs.contains(label))
        XCTAssertFalse(runner.jobs.contains(WallpaperWatcher.label))
        XCTAssertEqual(try engine.state(task), .done)

        try engine.journal.restore(recovery)
        XCTAssertFalse(runner.jobs.contains(label))
        XCTAssertFalse(Journal.exists(plist))
        XCTAssertTrue(Journal.exists(helper))
    }

    func testExistingAppNeverSelectsAnotherRuntime() throws {
        _ = try existingWatcher()
        let helper = try bundledWatcher()
        XCTAssertEqual(try WallpaperWatcher.source(paths: paths).executable, helper)
        _ = try engine.apply(Catalog.task("wallpaper-watcher"))
        XCTAssertEqual(runner.jobs, [WallpaperWatcher.replacementLabel])
    }

    func testMigrationWithoutLegacyPlistDoesNotStopUnrecoverableService() throws {
        _ = try bundledWatcher()
        runner.jobs.insert(WallpaperWatcher.label)
        XCTAssertThrowsError(try engine.apply(Catalog.task("wallpaper-watcher")))
        XCTAssertEqual(runner.jobs, [WallpaperWatcher.label])
        XCTAssertFalse(runner.calls.contains { $0.dropFirst().first == "bootout" })
    }

    func testBundledWatcherCanBeDisabledAndEnabled() throws {
        _ = try bundledWatcher()
        _ = try engine.apply(Catalog.task("wallpaper-watcher"))
        try WallpaperWatcher.setEnabled(false, engine: engine)
        XCTAssertTrue(runner.disabledJobs.contains(WallpaperWatcher.replacementLabel))
        XCTAssertFalse(runner.jobs.contains(WallpaperWatcher.replacementLabel))
        try WallpaperWatcher.setEnabled(true, engine: engine)
        XCTAssertTrue(runner.jobs.contains(WallpaperWatcher.replacementLabel))
    }

    func testMissingHelperNeverStopsWorkingLegacyWatcher() throws {
        let plist = try legacyWatcherPlist()
        let before = try Data(contentsOf: plist)
        runner.jobs.insert(WallpaperWatcher.label)
        XCTAssertEqual(try engine.state(Catalog.task("wallpaper-watcher")), .blocked)
        XCTAssertThrowsError(try engine.apply(Catalog.task("wallpaper-watcher")))
        XCTAssertEqual(try Data(contentsOf: plist), before)
        XCTAssertEqual(runner.jobs, [WallpaperWatcher.label])
        XCTAssertFalse(runner.calls.contains { $0.dropFirst().first == "bootout" })
    }

    func testFailedSharedStartupCanRestoreLegacyService() throws {
        let legacy = try legacyWatcherPlist()
        let original = try Data(contentsOf: legacy)
        _ = try bundledWatcher()
        runner.jobs.insert(WallpaperWatcher.label)
        runner.failWatcherStart = true
        XCTAssertThrowsError(try engine.apply(Catalog.task("wallpaper-watcher")))
        XCTAssertTrue(runner.jobs.isEmpty)
        let recovery = engine.journal.transactions.last!
        XCTAssertFalse(recovery.complete)
        try engine.journal.restore(recovery.id)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        XCTAssertEqual(runner.jobs, [WallpaperWatcher.label])
    }

    func testEnableMigratesAndRepeatedEnableRestartsSharedRuntime() throws {
        _ = try legacyWatcherPlist()
        _ = try bundledWatcher()
        runner.jobs.insert(WallpaperWatcher.label)
        try WallpaperWatcher.setEnabled(true, engine: engine)
        XCTAssertEqual(runner.jobs, [WallpaperWatcher.replacementLabel])
        runner.calls.removeAll()
        try WallpaperWatcher.setEnabled(true, engine: engine)
        XCTAssertEqual(runner.jobs, [WallpaperWatcher.replacementLabel])
        XCTAssertEqual(runner.calls.filter { $0.dropFirst().first == "bootout" }.count, 1)
        XCTAssertEqual(runner.calls.filter { $0.dropFirst().first == "bootstrap" }.count, 1)
    }

    func testReplacingHelperAtSamePathRequiresRefresh() throws {
        let helper = try bundledWatcher()
        let task = try Catalog.task("wallpaper-watcher")
        _ = try engine.apply(task)
        XCTAssertEqual(try engine.state(task), .done)
        try Data("updated helper".utf8).write(to: helper)
        XCTAssertEqual(try engine.state(task), .ready)
        try WallpaperWatcher.setEnabled(true, engine: engine)
        XCTAssertEqual(try engine.state(task), .done)
    }

    func testDisableStopsBothServicesDuringPartialMigration() throws {
        runner.jobs = [WallpaperWatcher.label, WallpaperWatcher.replacementLabel]
        try WallpaperWatcher.setEnabled(false, engine: engine)
        XCTAssertTrue(runner.jobs.isEmpty)
        XCTAssertEqual(runner.disabledJobs, [WallpaperWatcher.label, WallpaperWatcher.replacementLabel])
    }

    func testStaleLegacyEntryIsRemovedEvenWithSharedWatcherRunning() throws {
        let legacy = try legacyWatcherPlist()
        _ = try bundledWatcher()
        _ = try engine.apply(Catalog.task("wallpaper-watcher"))
        try Data("stale".utf8).write(to: legacy)
        XCTAssertEqual(try engine.state(Catalog.task("wallpaper-watcher")), .ready)
        _ = try engine.apply(Catalog.task("wallpaper-watcher"))
        XCTAssertFalse(Journal.exists(legacy))
        XCTAssertEqual(runner.jobs, [WallpaperWatcher.replacementLabel])
    }

    func testWatcherPermissionGuideOpensSettingsWithoutRandomFinderWindow() throws {
        _ = try existingWatcher()
        try engine.openGuide(Catalog.task("wallpaper-access"))
        XCTAssertFalse(runner.calls.contains { $0.first == "/usr/bin/open" && $0.contains("-R") })
        XCTAssertTrue(runner.calls.contains(["/usr/bin/open", "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]))
        XCTAssertFalse(runner.calls.contains { $0[0].contains("tcc") || $0[0] == "/bin/launchctl" })
    }
    func testHomebrewUpdateDoesNotUpgradeAllPackages() throws {
        engine = try Engine(paths: paths, runner: runner, appResolver: isolatedAppPath, tools: { $0 == "brew" ? "/fake/brew" : nil })
        _ = try engine.upgrade(Catalog.task("homebrew"))
        XCTAssertTrue(runner.calls.contains(["/fake/brew", "update"]))
        XCTAssertFalse(runner.calls.contains { $0.contains("upgrade") })
    }

    func testPackageUpdatesTargetOnlySelectedManagedPackages() throws {
        engine = try Engine(paths: paths, runner: runner, appResolver: isolatedAppPath, tools: { $0 == "brew" ? "/fake/brew" : nil })
        runner.managedPackages = ["atuin", "alacritty"]
        _ = try engine.upgrade(Catalog.task("atuin"))
        _ = try engine.upgrade(Catalog.task("alacritty"))
        XCTAssertEqual(runner.calls.filter { $0 == ["/fake/brew", "update"] }.count, 1)
        XCTAssertTrue(runner.calls.contains(["/fake/brew", "upgrade", "--formula", "atuin"]))
        XCTAssertTrue(runner.calls.contains(["/fake/brew", "upgrade", "--cask", "alacritty"]))
    }

    func testUnmanagedAppsAreNotTakenOverForUpdates() throws {
        engine = try Engine(paths: paths, runner: runner, appResolver: isolatedAppPath, tools: { $0 == "brew" ? "/fake/brew" : nil })
        XCTAssertThrowsError(try engine.upgrade(Catalog.task("raycast")))
        XCTAssertFalse(runner.calls.contains { $0.contains("update") || $0.contains("upgrade") })
    }

    func testHomebrewInstallsAndShellInitializationCanBeRestored() throws {
        engine = try Engine(paths: paths, runner: runner, appResolver: isolatedAppPath, tools: { [runner] name in name == "brew" && runner!.homebrewInstalled ? "/fake/brew" : nil })
        let profile = try write(".zprofile", "# existing config\n")
        let id = try engine.apply(Catalog.task("homebrew"))
        XCTAssertTrue(runner.homebrewInstalled)
        XCTAssertEqual(try engine.state(Catalog.task("homebrew")), .done)
        let text = try String(contentsOf: profile)
        XCTAssertTrue(text.contains("eval \"$('" + "/fake/brew' shellenv)\""))
        XCTAssertEqual(try ProcessRunner().run("/bin/bash", ["-n", profile.path]).status, 0)
        try engine.journal.restore(id)
        XCTAssertEqual(try String(contentsOf: profile), "# existing config\n")
        XCTAssertTrue(runner.homebrewInstalled)
    }

    func testExistingHomebrewIsNotDownloadedAgain() throws {
        engine = try Engine(paths: paths, runner: runner, appResolver: isolatedAppPath, tools: { $0 == "brew" ? "/fake/brew" : nil })
        _ = try engine.apply(Catalog.task("homebrew"))
        _ = try engine.apply(Catalog.task("homebrew"))
        XCTAssertFalse(runner.calls.contains { $0[0] == "/usr/bin/curl" || $0[0] == "/bin/bash" })
        let profile = try String(contentsOf: home.appendingPathComponent(".zprofile"))
        XCTAssertEqual(profile.components(separatedBy: "# >>> mac-setup: Homebrew >>>").count, 2)
    }

    func testFinderIconsPreserveLegacyAndModernViewOptionsAndRestore() throws {
        let original: [String: Any] = ["ListViewSettings": ["iconSize": 16, "textSize": 14], "ExtendedListViewSettingsV2": ["iconSize": 16, "sortColumn": "name", "columns": ["keep"]], "IconViewSettings": ["iconSize": 64]]
        runner.preferences["com.apple.finder"] = ["StandardViewSettings": original]
        let id = try engine.apply(Catalog.task("finder-icons"))
        XCTAssertEqual(try engine.state(Catalog.task("finder-icons")), .done)
        let views = runner.preferences["com.apple.finder"]!["StandardViewSettings"] as! [String: Any]
        XCTAssertTrue(equalPlist(views["IconViewSettings"], original["IconViewSettings"]))
        XCTAssertEqual((views["ExtendedListViewSettingsV2"] as! [String: Any])["sortColumn"] as? String, "dateModified")
        try engine.journal.restore(id)
        XCTAssertTrue(equalPlist(runner.preferences["com.apple.finder"]!["StandardViewSettings"], original))
    }

    func testAutomatedSettingsVerifyAndRestoreOnlyTheirOwnKeys() throws {
        for id in ["menu-bar", "trackpad", "desktop-widgets", "mission-control"] {
            let task = try Catalog.task(id)
            guard !task.guided else { continue }
            runner.preferences["com.apple.WindowManager"] = ["StageManagerHideWidgets": false]
            runner.preferences["com.apple.AppleMultitouchTrackpad"] = ["Clicking": true]
            let record = try engine.apply(task)
            XCTAssertEqual(try engine.state(task), .done)
            XCTAssertEqual(runner.preferences["com.apple.WindowManager"]?["StageManagerHideWidgets"] as? Bool, false)
            XCTAssertEqual(runner.preferences["com.apple.AppleMultitouchTrackpad"]?["Clicking"] as? Bool, true)
            try engine.journal.restore(record)
        }
        if case .guide = Catalog.desktopWidgetAction(macOSMajorVersion: 13) {} else { XCTFail("Unsupported desktop widgets must remain guided") }
    }

    func testReferenceFinderDefaultsMatchBothColumnLayouts() {
        let original: [String: Any] = ["ListViewSettings": ["columns": ["name": ["width": 320], "comments": ["width": 240, "visible": true]]], "ExtendedListViewSettingsV2": ["columns": [["identifier": "name", "width": 320], ["identifier": "dateModified", "width": 180], ["identifier": "comments", "visible": true]]]]
        let result = Engine.finderListDefaults(original)
        for key in ["ListViewSettings", "ExtendedListViewSettingsV2"] {
            let list = result[key] as! [String: Any]
            XCTAssertTrue(equalPlist(list["textSize"], 13))
            XCTAssertTrue(equalPlist(list["iconSize"], 32))
            XCTAssertTrue(equalPlist(list["calculateAllSizes"], false))
            XCTAssertTrue(equalPlist(list["useRelativeDates"], true))
            XCTAssertTrue(equalPlist(list["showIconPreview"], true))
        }
        let legacy = (result["ListViewSettings"] as! [String: Any])["columns"] as! [String: [String: Any]]
        XCTAssertEqual(legacy["name"]?["width"] as? Int, 320)
        XCTAssertEqual(Set(legacy.filter { equalPlist($0.value["visible"], true) }.keys), ["name", "dateModified", "size", "kind"])
        let modern = (result["ExtendedListViewSettingsV2"] as! [String: Any])["columns"] as! [[String: Any]]
        XCTAssertEqual(Set(modern.filter { equalPlist($0["visible"], true) }.compactMap { $0["identifier"] as? String }), ["name", "dateModified", "size", "kind"])
        XCTAssertTrue(equalPlist(result, Engine.finderListDefaults(result)))
    }

}
