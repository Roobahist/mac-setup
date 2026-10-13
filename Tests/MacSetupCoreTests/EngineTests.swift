import XCTest
@testable import MacSetupCore

final class FakeRunner: CommandRunning {
    var preferences: [String: [String: Any]] = [:]
    var git: [String: [String]] = [:]
    var calls: [[String]] = []
    var failWrites = false

    func run(_ executable: String, _ args: [String], interactive: Bool, input: Data?) throws -> CommandResult {
        calls.append([executable] + args)
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

    func testProfilePreservesExistingSymlinkAndRefusesToOverwrite() throws {
        let original = try write("private/aerospace.toml", "personal original\n")
        let extra = try write("private/local-note.txt", "keep this\n")
        try FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        let target = paths.config.appendingPathComponent("aerospace")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: original.deletingLastPathComponent())
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .blocked)
        XCTAssertThrowsError(try engine.apply(Catalog.task("aerospace-profile")))
        XCTAssertEqual(try String(contentsOf: original), "personal original\n")
        XCTAssertEqual(try String(contentsOf: extra), "keep this\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: target.path),
                       original.deletingLastPathComponent().path)
    }

    func testLinkedDotfilesPreservesAndRestoresOldConfiguration() throws {
        let source = DotfilesSource(home: home, folders: ["aerospace", "alacritty"])
        let checkout = source.checkout
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)
        _ = try write("dot-files/aerospace/aerospace.toml", "portable settings")
        _ = try write("dot-files/alacritty/alacritty.toml", "portable settings")
        let old = try write(".config/aerospace/personal.toml", "old settings")
        engine = try Engine(paths: paths, runner: runner, dotfilesSource: source)
        XCTAssertEqual(try engine.state(Catalog.task("dotfiles-linked")), .ready)

        let transaction = try engine.apply(Catalog.task("dotfiles-linked"))
        XCTAssertTrue(source.isLinked("aerospace", config: paths.config))
        XCTAssertTrue(source.isLinked("alacritty", config: paths.config))
        XCTAssertEqual(try engine.state(Catalog.task("dotfiles-linked")), .done)
        XCTAssertEqual(try engine.state(Catalog.task("aerospace-profile")), .done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))

        try engine.journal.restore(transaction)
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
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testLockRefusesConcurrentMutation() throws {
        let first = try SetupLock(paths: paths)
        XCTAssertThrowsError(try SetupLock(paths: paths))
        withExtendedLifetime(first) {}
    }
}
