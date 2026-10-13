import XCTest
@testable import MacSetupCore

final class FakeRunner: CommandRunning {
    var preferences: [String: [String: Any]] = [:]
    var git: [String: [String]] = [:]
    var calls: [[String]] = []
    var failWrites = false
    var jobs = Set<String>()

    func run(_ executable: String, _ args: [String], interactive: Bool, input: Data?) throws -> CommandResult {
        calls.append([executable] + args)
        if args == ["list-workspaces", "--focused"] { return CommandResult(status: 0, output: Data("1\n".utf8)) }
        if args.first?.hasSuffix("get_wallpaper_accent.py") == true {
            XCTAssertNotNil(input)
            return CommandResult(status: 0, output: Data("#123ABC\n".utf8))
        }
        if executable == "/bin/launchctl" {
            let label = args[1].components(separatedBy: "/").last!
            switch args[0] {
            case "print": return CommandResult(status: jobs.contains(label) ? 0 : 113)
            case "bootout": jobs.remove(label)
            case "bootstrap":
                let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
                let values = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
                jobs.insert(values["Label"] as! String)
            default: XCTFail("Unexpected launchctl command")
            }
            return CommandResult(status: 0)
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
            case "-bool": value = args[4] == "1" || args[4] == "true" || args[4] == "YES"
            case "-int": value = Int(args[4])!
            case "-float": value = Double(args[4])!
            case "-string": value = args[4]
            default: value = try PropertyListSerialization.propertyList(from: Data(args[3].utf8), format: nil)
            }
            preferences[domain, default: [:]][key] = value
            return CommandResult(status: 0)
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
        engine = try Engine(paths: paths, runner: runner)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    func write(_ relative: String, _ text: String) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testProfileDetachesSymlinkWithoutEditingPersonalRepoAndRestoresIt() throws {
        let original = try write("private/aerospace.toml", "personal original\n")
        let extra = try write("private/local-note.txt", "keep this\n")
        try FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        let target = paths.config.appendingPathComponent("aerospace")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: original.deletingLastPathComponent())
        let id = try engine.apply(Catalog.task("aerospace-profile"))
        XCTAssertEqual(try String(contentsOf: original), "personal original\n")
        XCTAssertEqual(try String(contentsOf: extra), "keep this\n")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("local-note.txt")), "keep this\n")
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .done)
        try engine.journal.restore(id)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: target.path), original.deletingLastPathComponent().path)
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

    func testFailedPreferenceWriteHasRecoverableRecord() throws {
        runner.failWrites = true
        XCTAssertThrowsError(try engine.apply(Catalog.task("dark-mode")))
        let record = try XCTUnwrap(engine.journal.transactions.last)
        XCTAssertFalse(record.complete)
        XCTAssertEqual(record.changes.count, 1)
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

    func testAeroSpaceAlternativeConfigIsNotOverwritten() throws {
        let file = try write(".aerospace.toml", "personal")
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .blocked)
        XCTAssertThrowsError(try engine.apply(Catalog.task("aerospace-profile")))
        XCTAssertEqual(try String(contentsOf: file), "personal")
    }

    func testGuidedTasksAreNotAutomaticallyApplied() throws {
        XCTAssertThrowsError(try engine.apply(Catalog.task("trackpad")))
        XCTAssertTrue(engine.journal.transactions.isEmpty)
        try engine.confirm(Catalog.task("trackpad"))
        XCTAssertEqual(try engine.state(Catalog.task("trackpad")), .confirmed)
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
        XCTAssertTrue(equalPlist(preferences.first(where: { $0.key == "autoQuitEnabled" })?.value, true))
        for forbidden in ["shelfItems", "textSnippets", "commandBarUsage", "notchDownloadsFolderBookmark", "NSOSPLastRootDirectory", "audioPriorityDeviceNames", "recorderEditorPresets", "launchAtLoginWanted"] {
            XCTAssertFalse(keys.contains(forbidden))
        }
        runner.preferences["com.vorssaint.utils"] = ["textSnippets": Data("private".utf8)]
        let id = try engine.apply(Catalog.task("vorssaint-profile"))
        XCTAssertEqual(runner.preferences["com.vorssaint.utils"]?["textSnippets"] as? Data, Data("private".utf8))
        XCTAssertEqual(runner.preferences["com.vorssaint.utils"]?["autoQuitExceptions"] as? [String], ["com.apple.finder", "com.apple.mobilephone"])
        XCTAssertLessThan(runner.calls.filter { $0.count > 1 && $0[0] == "/usr/bin/defaults" && $0[1] == "export" }.count, 5)
        try engine.journal.restore(id)
        XCTAssertEqual(runner.preferences["com.vorssaint.utils"]?["textSnippets"] as? Data, Data("private".utf8))
    }

    func testReadOnlyPlanInputsDoNotCreateState() throws {
        _ = try Catalog.tasks.map { try engine.preview($0) }
        XCTAssertFalse(Journal.exists(paths.state))
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testLockRefusesConcurrentMutation() throws {
        let first = try SetupLock(paths: paths)
        XCTAssertThrowsError(try SetupLock(paths: paths))
        withExtendedLifetime(first) {}
    }

    func testWallpaperPolicyDebouncesAndRetriesFailures() throws {
        var policy = WallpaperPolicy()
        let now = Date()
        let first = WallpaperFingerprint(path: "first", size: 10, modified: now)
        let second = WallpaperFingerprint(path: "second", size: 20, modified: now)
        XCTAssertTrue(policy.shouldApply(first, now: now))
        policy.succeeded(first)
        XCTAssertFalse(policy.shouldApply(first, now: now))
        XCTAssertFalse(policy.shouldApply(second, now: now))
        XCTAssertTrue(policy.shouldApply(second, now: now.addingTimeInterval(2)))
        policy.failed(second, now: now)
        XCTAssertFalse(policy.shouldApply(second, now: now.addingTimeInterval(10)))
        XCTAssertTrue(policy.shouldApply(second, now: now.addingTimeInterval(16)))
        policy.succeeded(second)
        let overwritten = WallpaperFingerprint(path: "second", size: 21, modified: now.addingTimeInterval(30))
        XCTAssertFalse(policy.shouldApply(overwritten, now: now.addingTimeInterval(30)))
        XCTAssertTrue(policy.shouldApply(overwritten, now: now.addingTimeInterval(32)))
    }

    func watcherRuntime() throws -> URL {
        let source = home.appendingPathComponent("release")
        let binary = try write("release/mac-setup", "fake binary for tests")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        _ = try write("release/MacSetup_MacSetupCore.bundle/Profile/file", "resource")
        return source
    }

    func testWallpaperStartupInstallAndRestoreOnlyUseTheCurrentUser() throws {
        let source = try watcherRuntime()
        engine = try Engine(paths: paths, runner: runner, runtimeSource: source)
        let id = try engine.apply(Catalog.task("wallpaper-watcher"))
        XCTAssertTrue(runner.jobs.contains(WallpaperWatcher.label))
        XCTAssertEqual(try engine.state(Catalog.task("wallpaper-watcher")), .done)
        let plist = home.appendingPathComponent("Library/LaunchAgents/" + WallpaperWatcher.label + ".plist")
        let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        XCTAssertEqual(values["Label"] as? String, WallpaperWatcher.label)
        XCTAssertTrue((values["ProgramArguments"] as! [String])[0].hasPrefix(paths.state.path))
        try engine.journal.restore(id)
        XCTAssertFalse(runner.jobs.contains(WallpaperWatcher.label))
        XCTAssertFalse(Journal.exists(plist))
        XCTAssertFalse(Journal.exists(paths.state.appendingPathComponent("watcher-runtime")))
    }

    func testExistingWallpaperJobIsRestoredAfterUpdatingItsRuntime() throws {
        let source = try watcherRuntime()
        engine = try Engine(paths: paths, runner: runner, runtimeSource: source)
        _ = try engine.apply(Catalog.task("wallpaper-watcher"))
        let binary = source.appendingPathComponent("mac-setup")
        try Data("new test version".utf8).write(to: binary)
        XCTAssertEqual(try engine.state(Catalog.task("wallpaper-watcher")), .ready)
        let update = try engine.apply(Catalog.task("wallpaper-watcher"))
        try engine.journal.restore(update)
        XCTAssertTrue(runner.jobs.contains(WallpaperWatcher.label))
        XCTAssertEqual(try String(contentsOf: paths.state.appendingPathComponent("watcher-runtime/mac-setup")), "fake binary for tests")
    }

    func testLegacyWallpaperJobIsNotDisabled() throws {
        let source = try watcherRuntime()
        engine = try Engine(paths: paths, runner: runner, runtimeSource: source)
        runner.jobs.insert(WallpaperWatcher.legacyLabel)
        XCTAssertThrowsError(try engine.apply(Catalog.task("wallpaper-watcher")))
        XCTAssertTrue(runner.jobs.contains(WallpaperWatcher.legacyLabel))
        XCTAssertFalse(runner.jobs.contains(WallpaperWatcher.label))
    }

    func testBackgroundAccentOnlyChangesTheColorAndDoesNotGrowTheJournal() throws {
        let color = try write(".config/sketchybar/plugins/colors.sh", "export BAR_COLOR=0x35000000\nexport HIGHLIGHT_COLOR=0xff000000\n")
        let image = try write("wallpaper.png", "fake image bytes")
        engine = try Engine(paths: paths, runner: runner, tools: { "/usr/bin/" + $0 })
        try engine.refreshAccent(image: image)
        XCTAssertEqual(try String(contentsOf: color), "export BAR_COLOR=0x35000000\nexport HIGHLIGHT_COLOR=0xff123ABC\n")
        XCTAssertTrue(engine.journal.transactions.isEmpty)
        XCTAssertFalse(Journal.exists(paths.state))
    }

    func testBackgroundAccentRefusesAConfigSymlinkIntoAPrivateRepo() throws {
        let original = try write("private/plugins/colors.sh", "export HIGHLIGHT_COLOR=0xff000000\n")
        try FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: paths.config.appendingPathComponent("sketchybar"), withDestinationURL: original.deletingLastPathComponent().deletingLastPathComponent())
        let image = try write("wallpaper.png", "fake image bytes")
        engine = try Engine(paths: paths, runner: runner, tools: { "/usr/bin/" + $0 })
        XCTAssertThrowsError(try engine.refreshAccent(image: image))
        XCTAssertEqual(try String(contentsOf: original), "export HIGHLIGHT_COLOR=0xff000000\n")
    }

    func testFinderIconSizePreservesOtherViewOptionsAndRestoresThem() throws {
        let original: [String: Any] = ["ListViewSettings": ["iconSize": 16.0, "textSize": 14.0, "sortColumn": "name", "columns": ["name": ["width": 300]]], "IconViewSettings": ["iconSize": 64.0]]
        runner.preferences["com.apple.finder"] = ["StandardViewSettings": original]
        let id = try engine.apply(Catalog.task("finder-icons"))
        XCTAssertEqual(try engine.state(Catalog.task("finder-icons")), .done)
        let changed = runner.preferences["com.apple.finder"]?["StandardViewSettings"] as! [String: Any]
        let list = changed["ListViewSettings"] as! [String: Any]
        XCTAssertEqual(list["textSize"] as? Double, 14.0)
        XCTAssertEqual(list["sortColumn"] as? String, "name")
        XCTAssertTrue(equalPlist(changed["IconViewSettings"], original["IconViewSettings"]))
        try engine.journal.restore(id)
        XCTAssertTrue(equalPlist(runner.preferences["com.apple.finder"]?["StandardViewSettings"], original))
    }

    func testWatcherPermissionGuideRevealsTheExecutableWithoutGrantingAccess() throws {
        try engine.openGuide(Catalog.task("wallpaper-access"))
        XCTAssertTrue(runner.calls.contains(["/usr/bin/open", "-R", paths.state.appendingPathComponent("watcher-runtime/mac-setup").path]))
        XCTAssertTrue(runner.calls.contains(["/usr/bin/open", "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]))
        XCTAssertFalse(runner.calls.contains { $0[0] == "/usr/bin/defaults" || $0[0].contains("tcc") })
        XCTAssertFalse(Journal.exists(paths.state))
    }
}
