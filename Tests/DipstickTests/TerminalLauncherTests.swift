import XCTest
@testable import Dipstick

final class TerminalLauncherTests: XCTestCase {
    /// Every fix mrk-status can offer, from tools/mrk-status in mrk at
    /// da7192c (2026-10-22): dailyFixes in daily.go, the installation checks'
    /// fixes in main.go, and Dipstick's own two, StatusError.fix. The ones
    /// that draw a full screen open a terminal; the rest run in the console.
    func testOnlyTheFullScreenFixesOpenATerminal() {
        let terminal = ["mrk-menu", "make sync ARGS=-c", "make sync-login-items ARGS=-c", "make brew"]
        let console = [
            "bin/mrk-push", "bin/pushall", "make snapshot-prefs", "make pull", "make update",
            "make updates", "make build-tools",
            "make dotfiles", "make tools", "make fix-exec", "make defaults", "make trackpad",
            "make harden", "chsh -s /opt/homebrew/bin/zsh", #"make setup ARGS="--only shell""#,
            "make doctor ARGS=--fix",
        ]
        for command in terminal {
            XCTAssertTrue(TerminalLauncher.isNeeded(for: command), command)
        }
        for command in console {
            XCTAssertFalse(TerminalLauncher.isNeeded(for: command), command)
        }
    }

    /// The real contract sends the same fixes to a terminal as the targets
    /// Dipstick keeps for an older mrk, and names each of those targets. Its
    /// fourth, `all`, is no fix: it makes `brew`.
    func testTheRealContractNamesTheTargetsDipstickKeeps() throws {
        let contract = try MrkContract.decode(Data(try Fixture.text("mrk-contract.json").utf8))
        let targets = TerminalLauncher.targets(in: contract)
        XCTAssertEqual(targets, ["all", "brew", "sync", "sync-login-items"])
        XCTAssertTrue(TerminalLauncher.fullScreenTargets.isSubset(of: targets))
        for command in ["mrk-menu", "make sync ARGS=-c", "make sync-login-items ARGS=-c", "make brew",
                        "make snapshot-prefs", "make update", "make defaults", "make doctor ARGS=--fix"] {
            XCTAssertEqual(TerminalLauncher.isNeeded(for: command, targets: targets),
                           TerminalLauncher.isNeeded(for: command), command)
        }
    }

    /// A contract's list is the targets, whatever Dipstick keeps: one that
    /// lists a new target sends it to a terminal, and one that leaves a target
    /// out runs it in the console. No contract, or one from before the list,
    /// keeps Dipstick's own.
    func testTheTargetsAreTheContractsOrElseDipsticks() throws {
        let listed = try MrkContract.decode(Data(ContractTests.contract(terminal: ["pick", "sync"]).utf8))
        let targets = TerminalLauncher.targets(in: listed)
        XCTAssertEqual(targets, ["pick", "sync"])
        XCTAssertTrue(TerminalLauncher.isNeeded(for: "make pick ARGS=-n", targets: targets))
        XCTAssertFalse(TerminalLauncher.isNeeded(for: "make brew", targets: targets))
        XCTAssertTrue(TerminalLauncher.isNeeded(for: "gum choose a b", targets: targets), "a program by its name still")

        let none = try MrkContract.decode(Data(ContractTests.contract(terminal: []).utf8))
        XCTAssertEqual(TerminalLauncher.targets(in: none), [])

        let before = try MrkContract.decode(Data(try Fixture.text("mrk-140/mrk-contract.json").utf8))
        XCTAssertNil(before.terminal)
        XCTAssertEqual(TerminalLauncher.targets(in: before), TerminalLauncher.fullScreenTargets)
        XCTAssertEqual(TerminalLauncher.targets(in: nil), TerminalLauncher.fullScreenTargets)
    }

    /// The program by any path, and make's target past its options and
    /// variables.
    func testTheRuleReadsTheProgramAndTheTarget() {
        XCTAssertTrue(TerminalLauncher.isNeeded(for: "bin/mrk-picker"))
        XCTAssertTrue(TerminalLauncher.isNeeded(for: "/Users/x/bin/mrk-menu --plain"))
        XCTAssertTrue(TerminalLauncher.isNeeded(for: "gum choose a b"))
        XCTAssertTrue(TerminalLauncher.isNeeded(for: "make -s ARGS=-c sync"))
        XCTAssertFalse(TerminalLauncher.isNeeded(for: "make synced"))
        XCTAssertFalse(TerminalLauncher.isNeeded(for: "make"))
        XCTAssertFalse(TerminalLauncher.isNeeded(for: ""))
    }

    func testQuotingSurvivesSingleQuotesAndSpaces() {
        XCTAssertEqual(TerminalLauncher.shellQuote("it's here"), #"'it'"'"'s here'"#)
        XCTAssertEqual(TerminalLauncher.shellQuote("/Users/x/my mrk"), "'/Users/x/my mrk'")
    }

    func testTheScriptRunsTheFixInTheCheckout() {
        let script = TerminalLauncher.script(
            command: #"make setup ARGS="--only shell""#,
            directory: "/Users/x/mrk",
            exports: ["PATH": "/Users/x/bin:/usr/bin", "MRK_ROOT": "/Users/x/mrk"])
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertEqual(lines.first, "#!/bin/zsh")
        XCTAssertTrue(lines.contains(#"rm -f -- "$0""#))
        // Sorted, so the file is the same for the same inputs.
        XCTAssertEqual(lines.filter { $0.hasPrefix("export ") },
                       ["export MRK_ROOT='/Users/x/mrk'", "export PATH='/Users/x/bin:/usr/bin'"])
        XCTAssertTrue(lines.contains("cd -- '/Users/x/mrk' || exit 1"))
        // The fix itself goes in as written: it is shell, as the TUI runs it.
        XCTAssertTrue(lines.contains(#"make setup ARGS="--only shell""#))
        // `status` is read-only in zsh; assigning it would end the script.
        XCTAssertTrue(lines.contains("rc=$?"))
        XCTAssertFalse(script.contains("status=$?"))
    }

    /// The script, run by zsh with `cd` pointed at a scratch folder: it runs
    /// the command there, reports the exit, and deletes itself.
    func testTheScriptRunsAndDeletesItself() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DipstickTests-\(UUID().uuidString)", isDirectory: true)
        let work = dir.appendingPathComponent("my 'checkout'", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("run.command")
        try TerminalLauncher.script(command: "pwd -P; exit_code_is() { return 3 }; exit_code_is",
                                    directory: work.path,
                                    exports: ["PATH": "/usr/bin:/bin"])
            .write(to: file, atomically: true, encoding: .utf8)

        let result = try await Subprocess.run(
            URL(fileURLWithPath: "/bin/zsh"), arguments: ["-f", file.path], timeout: .seconds(10))
        let out = String(decoding: result.stdout, as: UTF8.self)

        XCTAssertTrue(out.contains(work.resolvingSymlinksInPath().path), out)
        XCTAssertTrue(out.contains("Dipstick: exited 3."), out)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}

/// The menu bar's fixes go to a terminal by the targets of the checkout's
/// mrk-contract, read at each refresh.
@MainActor
final class TerminalTargetsTests: XCTestCase {
    /// With no mrk-contract the targets are Dipstick's own. Once the checkout
    /// has one with a list, the next refresh reads it, and a change to the
    /// file is read at the refresh after it.
    func testTheRefreshReadsTheCheckoutsTargets() async throws {
        let stub = try StubMrk()
        let model = stub.model()
        await model.refresh()
        XCTAssertEqual(model.terminalTargets, TerminalLauncher.fullScreenTargets)
        XCTAssertTrue(model.needsTerminal("make brew"))
        XCTAssertEqual(stub.contractCalls, 0)

        try stub.contract(ContractTests.contract(terminal: ["sync", "update"]))
        await model.refresh()
        XCTAssertTrue(model.needsTerminal("make update"))
        XCTAssertTrue(model.needsTerminal("make sync ARGS=-c"))
        XCTAssertFalse(model.needsTerminal("make brew"))
        XCTAssertTrue(model.needsTerminal("mrk-menu"))

        await model.refresh()
        XCTAssertEqual(stub.contractCalls, 1, "read once while the file is the same")

        try stub.contract(ContractTests.contract())
        let url = stub.root.appendingPathComponent("scripts/mrk-contract")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        await model.refresh()
        XCTAssertEqual(model.terminalTargets, TerminalLauncher.fullScreenTargets, "a contract with no list")
        XCTAssertEqual(stub.contractCalls, 2)
    }

    /// mrk Settings runs its scripts with the same runner, so the panes and
    /// the refresh read the contract once between them.
    func testThePanesAndTheRefreshShareTheContract() async throws {
        let stub = try StubMrk()
        try stub.contract(ContractTests.contract(terminal: ["sync"]))
        let model = stub.model()
        await model.refresh()
        let settings = await model.settingsModel()
        XCTAssertTrue(settings.runner === model.runner)
        _ = try await settings.runner.run(.dockCheck, in: stub.checkout)
        XCTAssertEqual(stub.contractCalls, 1, "\(stub.calls)")
    }
}
