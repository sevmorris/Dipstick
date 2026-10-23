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
