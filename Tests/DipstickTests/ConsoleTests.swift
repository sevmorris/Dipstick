import AppKit
import XCTest
@testable import Dipstick

final class PseudoTerminalTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DipstickTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("my 'checkout'", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent())
    }

    private func zsh(_ script: String, grace: Duration = .seconds(2),
                     typing: [UInt8]? = nil, after: Duration = .milliseconds(300),
                     signal: Int32? = nil) async throws -> (output: String, status: Int32?) {
        let (terminal, events) = try PseudoTerminal.start(
            "/bin/zsh", arguments: ["-f", "-c", script],
            environment: ["PATH": "/usr/bin:/bin", "TERM": "dumb", "DIPSTICK_PROBE": "it's set"],
            directory: scratch.path, drainGrace: grace)
        if typing != nil || signal != nil {
            Task {
                try? await Task.sleep(for: after)
                if let typing { terminal.write(typing) }
                if let signal { terminal.send(signal: signal) }
            }
        }
        var output = Data()
        var status: Int32?
        for await event in events {
            switch event {
            case .output(let data): output.append(data)
            case .exit(let code): status = code
            }
        }
        return (String(decoding: output, as: UTF8.self), status)
    }

    /// What mrk-push's commit message and the secret scan need: stdin is a
    /// terminal, and /dev/tty is the program's own, so `read </dev/tty` takes
    /// what is typed.
    func testTheProgramHasATerminalAndCanAskThroughIt() async throws {
        let (output, status) = try await zsh(
            #"[[ -t 0 && -t 2 ]] && print isatty; print -rn -- "Push/commit anyway? "; read -r ans </dev/tty; print -r -- "got [$ans]"; exit 3"#,
            typing: Array("yes\r".utf8))
        XCTAssertTrue(output.contains("isatty"), output)
        // The terminal echoes what was typed, and the program reads the line.
        XCTAssertTrue(output.contains("Push/commit anyway? yes\r\n"), output)
        XCTAssertTrue(output.contains("got [yes]"), output)
        XCTAssertEqual(status, 3)
    }

    func testItRunsInTheDirectoryWithTheEnvironment() async throws {
        let (output, status) = try await zsh(#"pwd -P; print -r -- "$DIPSTICK_PROBE $TERM"; stty size"#)
        XCTAssertTrue(output.contains(scratch.resolvingSymlinksInPath().path), output)
        XCTAssertTrue(output.contains("it's set dumb"), output)
        XCTAssertTrue(output.contains("24 80"), output)
        XCTAssertEqual(status, 0)
    }

    /// macOS drops what nobody has read when the program closes the terminal,
    /// so the last of a lot of output is the test.
    func testOutputUpToTheExitArrives() async throws {
        let (output, status) = try await zsh("for i in {1..20000}; do print line $i; done; exit 4")
        XCTAssertTrue(output.hasSuffix("line 20000\r\n"), String(output.suffix(80)))
        XCTAssertEqual(status, 4)
    }

    func testInterruptStopsItAsCtrlCDoes() async throws {
        let start = Date()
        let (_, status) = try await zsh("sleep 30", signal: SIGINT)
        XCTAssertEqual(status, 128 + SIGINT)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    /// ⌃C typed at the terminal reaches the program through the terminal.
    func testCtrlCTypedStopsIt() async throws {
        let (_, status) = try await zsh("sleep 30", typing: [0x03])
        XCTAssertEqual(status, 128 + SIGINT)
    }

    /// Something the program left in the background holds the terminal open;
    /// the run still ends, after the grace.
    func testABackgroundChildDoesNotHoldTheEndUp() async throws {
        let start = Date()
        let (output, status) = try await zsh("(sleep 20 &); print -r -- left", grace: .milliseconds(300))
        XCTAssertTrue(output.contains("left"), output)
        XCTAssertEqual(status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testAMissingDirectoryIsSaid() async throws {
        let (terminal, events) = try PseudoTerminal.start(
            "/bin/zsh", arguments: ["-c", "true"], environment: [:],
            directory: scratch.appendingPathComponent("gone").path)
        _ = terminal
        var output = ""
        var status: Int32?
        for await event in events {
            switch event {
            case .output(let data): output += String(decoding: data, as: UTF8.self)
            case .exit(let code): status = code
            }
        }
        // Named as the process is, which here is the test runner, not Dipstick.
        let name = ProcessInfo.processInfo.processName.lowercased()
        XCTAssertTrue(output.contains("\(name): cannot enter \(scratch.path)/gone"), output)
        XCTAssertEqual(status, 126)
    }

    func testShellStatus() {
        XCTAssertEqual(PseudoTerminal.shellStatus(3 << 8), 3)
        XCTAssertEqual(PseudoTerminal.shellStatus(SIGINT), 130)
        XCTAssertEqual(PseudoTerminal.shellStatus(SIGKILL), 137)
    }
}

@MainActor
final class ConsoleModelTests: XCTestCase {
    /// A fix in the console runs in the checkout with the login shell's
    /// environment and MRK_ROOT, on an xterm-256color, and then mrk-status
    /// runs again.
    func testTheConsoleRunsTheFixThenMrkStatusAgain() async throws {
        let stub = try StubMrk()
        try stub.write("Makefile", "pull:\n\t@printf 'pulled term=%s root=%s\\n' \"$$TERM\" \"$$MRK_ROOT\"; pwd -P\n")
        let model = stub.model()

        await model.runInConsole("make pull")

        let session = try XCTUnwrap(model.console)
        XCTAssertEqual(session.state, .exited(0))
        let text = session.screen.text
        XCTAssertTrue(text.hasPrefix("$ make pull\n"), text)
        XCTAssertTrue(text.contains("pulled term=xterm-256color root=\(stub.root.path)\n\(stub.realRoot)\n"), text)
        XCTAssertTrue(text.hasSuffix("[exited 0]"), text)
        XCTAssertEqual(stub.calls, ["--json"])
        XCTAssertEqual(model.report?.summary, "1 error")

        model.closeConsole()
        XCTAssertNil(model.console)
    }

    func testAFailureIsItsStatusAndMrkStatusStillRuns() async throws {
        let stub = try StubMrk()
        try stub.write("Makefile", "snapshot-prefs:\n\t@echo refused >&2; exit 1\n")
        let model = stub.model()

        await model.runInConsole("make snapshot-prefs")

        let session = try XCTUnwrap(model.console)
        XCTAssertEqual(session.state, .exited(2))  // make's own status for a failed recipe
        XCTAssertTrue(session.screen.text.contains("refused"), session.screen.text)
        XCTAssertEqual(stub.calls, ["--json"])
    }

    /// The console takes one fix at a time, and closes only once it has
    /// exited. One that has exited gives way to the next.
    func testOneFixAtATime() async throws {
        let stub = try StubMrk()
        try stub.write("Makefile", "update:\n\t@sleep 30\npull:\n\t@echo pulled\n")
        let model = stub.model()

        let first = Task { await model.runInConsole("make update") }
        while model.console?.state != .running { try await Task.sleep(for: .milliseconds(20)) }
        let session = try XCTUnwrap(model.console)
        XCTAssertTrue(model.isConsoleRunning)

        await model.runInConsole("make pull")
        XCTAssertTrue(model.console === session)
        model.closeConsole()
        XCTAssertTrue(model.console === session)

        session.stop()
        await first.value
        // make deletes what it was making, then dies of the SIGINT itself.
        XCTAssertEqual(session.state, .exited(128 + SIGINT))
        XCTAssertEqual(session.stops, 1)
        XCTAssertFalse(model.isConsoleRunning)
        XCTAssertTrue(model.console === session)

        await model.runInConsole("make pull")
        let next = try XCTUnwrap(model.console)
        XCTAssertFalse(next === session)
        XCTAssertEqual(next.state, .exited(0))
        model.closeConsole()
        XCTAssertNil(model.console)
    }

    /// A refresh that was running when the fix ended read mrk as it was
    /// before, so it goes round again rather than leave that report up.
    func testAFixEndingDuringARefreshRunsMrkStatusAgain() async throws {
        let stub = try StubMrk()
        try stub.write("delay", "1")
        let model = stub.model()

        let refresh = Task { await model.refresh() }
        while !model.isRefreshing { try await Task.sleep(for: .milliseconds(20)) }
        await model.refreshAfterFix()
        await refresh.value
        XCTAssertEqual(stub.calls, ["--json", "--json"])

        await model.refreshAfterFix()
        XCTAssertEqual(stub.calls.count, 3)
    }

    func testTheConsoleEnvironment() {
        let env = StatusModel.consoleEnvironment(
            ["PATH": "/opt/homebrew/bin:/usr/bin", "TERM": "xterm-256color", "COLUMNS": "200", "HOME": "/Users/x"],
            root: "/Users/x/mrk")
        XCTAssertEqual(env["PATH"], "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(env["HOME"], "/Users/x")
        XCTAssertEqual(env["MRK_ROOT"], "/Users/x/mrk")
        XCTAssertEqual(env["TERM"], "xterm-256color")
        XCTAssertEqual(env["PAGER"], "cat")
        XCTAssertEqual(env["GIT_PAGER"], "cat")
        XCTAssertNil(env["COLUMNS"])
        let fromTerminal = StatusModel.consoleEnvironment(
            ["TERM_PROGRAM": "Apple_Terminal", "TERM_PROGRAM_VERSION": "466", "TERM_SESSION_ID": "x", "COLORTERM": "truecolor"],
            root: "/Users/x/mrk")
        XCTAssertNil(fromTerminal["TERM_PROGRAM"], "the console is not the terminal the shell was asked from")
        XCTAssertNil(fromTerminal["TERM_PROGRAM_VERSION"])
        XCTAssertNil(fromTerminal["TERM_SESSION_ID"])
        XCTAssertNil(fromTerminal["COLORTERM"])
    }
}

/// The console as a terminal: what it answers, its size, and a real picker.
@MainActor
final class ConsoleTerminalTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DipstickTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private var environment: [String: String] {
        ["PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "HOME": scratch.path]
    }

    private func wait(for condition: () -> Bool, _ what: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return XCTFail("waited 10 s for \(what)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// A program that asks where the cursor is gets the answer from the
    /// console, typed at its terminal, as termenv asks before it draws.
    func testTheConsoleAnswersWhatTheProgramAsks() async throws {
        try """
        stty -icanon -echo min 1
        printf '\\033[6n'
        IFS= read -r -d R reply
        stty sane
        print -r -- "reply=${reply#?}"
        """.write(to: scratch.appendingPathComponent("probe.zsh"), atomically: true, encoding: .utf8)
        let session = ConsoleSession(command: "zsh -f ./probe.zsh")

        await session.run(environment: environment, directory: scratch.path)

        XCTAssertEqual(session.state, .exited(0))
        // The command's own line is row 1, so the cursor was on row 2.
        XCTAssertTrue(session.screen.text.contains("reply=[2;1\n"), session.screen.text)
    }

    /// The terminal is as big as the console's screen when the command
    /// starts, and a change while it runs reaches it as SIGWINCH.
    func testTheTerminalIsTheScreensSizeAndHearsAChange() async throws {
        let session = ConsoleSession(
            command: #"stty size; trap 'stty size; exit 0' WINCH; print ready; while :; do sleep 0.05; done"#)
        session.resize(columns: 100, rows: 30)
        XCTAssertEqual(session.screen.columns, 100)

        let run = Task { await session.run(environment: environment, directory: scratch.path) }
        // At the start of a line: the command's own line has "print ready".
        try await wait(for: { session.screen.text.contains("\nready") }, "ready")
        session.resize(columns: 120, rows: 40)
        let deadline = Task {
            try await Task.sleep(for: .seconds(10))
            XCTFail("no SIGWINCH in 10 s")
            for _ in 0..<3 { session.stop() }
        }
        await run.value
        deadline.cancel()

        let text = session.screen.text
        XCTAssertTrue(text.contains("30 100\nready\n40 120\n"), text)
        XCTAssertEqual(session.state, .exited(0))
    }

    /// gum choose, as sync and sync-login-items start it: bubbletea's inline
    /// picker draws, the arrow keys move it, Return picks, and the picker
    /// goes, leaving what was picked.
    func testGumChooseDrawsAndTakesTheArrows() async throws {
        let gum = "/opt/homebrew/bin/gum"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: gum), "gum is not installed")
        let session = ConsoleSession(command: "\(gum) choose one two three")
        let run = Task { await session.run(environment: environment, directory: scratch.path) }

        try await wait(for: { session.screen.text.contains("> one") }, "gum to draw")
        let down = try XCTUnwrap(ConsoleKeys.bytes(characters: "\u{F701}", keyCode: 125, modifiers: [],
                                                   modes: .init(applicationCursor: session.screen.applicationCursorKeys)))
        session.type(down)
        try await wait(for: { session.screen.text.contains("> two") }, "the cursor to move")
        session.type([0x0D])
        await run.value

        XCTAssertEqual(session.state, .exited(0))
        let text = session.screen.text
        XCTAssertFalse(text.contains("Choose"), "the picker is gone: \(text)")
        XCTAssertTrue(text.hasSuffix("three\ntwo\n[exited 0]"), text)
    }
}
