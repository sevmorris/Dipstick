import XCTest
@testable import Dipstick

/// Which of mrk-status's fixes a pane of mrk Settings makes instead.
final class FixRouteTests: XCTestCase {
    /// Every fix mrk-status can offer, as TerminalLauncherTests lists them.
    func testTheFixesAPaneMakes() {
        XCTAssertEqual(FixRoute.route(for: "make snapshot-prefs"), FixRoute(pane: .preferences))
        XCTAssertEqual(FixRoute.route(for: "make sync-login-items ARGS=-c"), FixRoute(pane: .loginItems))
        XCTAssertEqual(FixRoute.route(for: "make defaults"), FixRoute(pane: .defaults))
        XCTAssertEqual(FixRoute.route(for: "make trackpad"), FixRoute(pane: .defaults, withTrackpad: true))
        XCTAssertEqual(FixRoute.route(for: "make dock"), FixRoute(pane: .dock))
        let others = [
            "mrk-menu", "make sync ARGS=-c", "make brew", "bin/mrk-push", "bin/pushall", "make pull",
            "make update", "make updates", "make build-tools", "make dotfiles", "make tools",
            "make fix-exec", "make harden", "chsh -s /opt/homebrew/bin/zsh",
            #"make setup ARGS="--only shell""#, "make doctor ARGS=--fix",
        ]
        for command in others {
            XCTAssertNil(FixRoute.route(for: command), command)
        }
    }

    func testTheTargetPastOptionsAndVariables() {
        XCTAssertEqual(TerminalLauncher.makeTarget(of: "make -s ARGS=-c sync-login-items"), "sync-login-items")
        XCTAssertNil(TerminalLauncher.makeTarget(of: "bin/make defaults"))
        XCTAssertNil(TerminalLauncher.makeTarget(of: "make"))
        XCTAssertNil(FixRoute.route(for: "make snapshot-prefs-check"))
    }
}

/// mrk Settings inside Dipstick: its model is the menu bar's, its commands
/// run in the menu bar's console, and what it changes, mrk-status reads.
@MainActor
final class SettingsHostTests: XCTestCase {
    /// The panes read the checkout the login shell names, and run the
    /// scripts with the menu bar's environment.
    func testTheSettingsModelIsMadeOnceOverTheShellsCheckout() async throws {
        let stub = try StubMrk()
        let model = stub.model()
        let settings = await model.settingsModel()
        XCTAssertEqual(settings.checkout.root.path, stub.root.path)
        XCTAssertTrue(settings.host === model)
        let again = await model.settingsModel()
        XCTAssertTrue(again === settings)
        let env = await settings.runner.resolvedEnvironment()
        XCTAssertEqual(env["MRK_ROOT"], stub.root.path)
    }

    /// A fix that a pane makes opens that pane, which reads mrk; nothing runs
    /// in the console.
    func testAFixAPaneMakesOpensThePane() async throws {
        let stub = try StubMrk()
        let model = stub.model()

        model.run("make sync-login-items ARGS=-c")
        while model.settings?.loginItems.phase != .loaded { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.settings?.selection, .loginItems)
        XCTAssertNil(model.console)
        XCTAssertTrue(stub.calls.contains { $0.hasPrefix("scripts/sync-login-items [--check]") }, "\(stub.calls)")
        XCTAssertFalse(stub.calls.contains { $0.contains("[-c]") }, "nothing commits: \(stub.calls)")
    }

    func testMakeTrackpadOpensTheDefaultsWithTheTrackpad() async throws {
        let stub = try StubMrk()
        let model = stub.model()

        model.run("make trackpad")
        while model.settings?.defaults.phase != .loaded { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.settings?.selection, .defaults)
        XCTAssertEqual(model.settings?.defaults.withTrackpad, true)
        XCTAssertTrue(stub.calls.contains { $0.hasPrefix("scripts/defaults.sh [--check] [--with-trackpad]") },
                      "\(stub.calls)")
    }

    /// make dock from the Dock pane runs in the menu bar's console, in the
    /// checkout with the login shell's environment and MRK_ROOT; then the
    /// Dock pane reads mrk again, and so does mrk-status.
    func testAPanesCommandRunsInTheConsoleThenReadsThePaneAndMrkStatus() async throws {
        let stub = try StubMrk()
        try stub.write("Makefile", "dock:\n\t@printf 'docked term=%s root=%s\\n' \"$$TERM\" \"$$MRK_ROOT\"\n")
        try stub.write("config/dock.txt", "/Applications/Safari.app\n")
        let model = stub.model()
        let settings = await model.settingsModel()

        await settings.runInConsole(.applyDock)

        let session = try XCTUnwrap(model.console)
        XCTAssertEqual(session.command, "make dock")
        XCTAssertEqual(session.pane, .dock)
        XCTAssertEqual(session.state, .exited(0))
        let text = session.screen.text
        XCTAssertTrue(text.hasPrefix("$ make dock\n"), text)
        XCTAssertTrue(text.contains("docked term=dumb root=\(stub.root.path)"), text)
        XCTAssertTrue(stub.calls.contains { $0.hasPrefix("scripts/dock-setup [--check]") }, "\(stub.calls)")
        XCTAssertEqual(settings.dock.phase, .loaded)
        XCTAssertEqual(stub.statusCalls, ["--json"])

        model.closeConsole()
        XCTAssertNil(model.console)
    }

    /// While a switch or a login item decision runs, a pane's console command
    /// does not start: make dock would restart the Dock beside the switch's
    /// own restart (sevmorris/mrk audit 22, Z-7).
    func testAPanesCommandWaitsForADecision() async throws {
        let stub = try StubMrk()
        try stub.write("Makefile", "dock:\n\t@echo docked\n")
        let model = stub.model()
        let settings = await model.settingsModel()

        settings.defaults.busy = "com.apple.dock tilesize"
        await settings.runInConsole(.applyDock)
        XCTAssertNil(model.console)
        settings.defaults.busy = nil
        await settings.runInConsole(.applyDock)
        XCTAssertEqual(model.console?.command, "make dock")
        model.closeConsole()
    }

    func testAFailureIsItsStatusAndThePaneStillReads() async throws {
        let stub = try StubMrk()
        try stub.write("Makefile", "snapshot-prefs:\n\t@echo refused >&2; exit 1\n")
        let model = stub.model()
        let settings = await model.settingsModel()

        await settings.runInConsole(.snapshotPrefs)

        let session = try XCTUnwrap(model.console)
        XCTAssertEqual(session.state, .exited(2))  // make's own status for a failed recipe
        XCTAssertTrue(session.screen.text.contains("refused"), session.screen.text)
        XCTAssertTrue(stub.calls.contains { $0.hasPrefix("scripts/snapshot-prefs [--check]") }, "\(stub.calls)")
        XCTAssertEqual(stub.statusCalls, ["--json"])
    }

    /// One console for the menu bar and the panes: a pane's command waits
    /// for the menu bar's fix, and the fixes wait for a pane's.
    func testOneCommandAtATimeAcrossTheMenuBarAndThePanes() async throws {
        let stub = try StubMrk()
        try stub.write("Makefile", "update:\n\t@sleep 30\ndock:\n\t@echo docked\n")
        let model = stub.model()
        let settings = await model.settingsModel()

        let first = Task { await model.runInConsole("make update") }
        while model.console?.state != .running { try await Task.sleep(for: .milliseconds(20)) }
        let session = try XCTUnwrap(model.console)
        XCTAssertTrue(model.isBusy)

        await settings.runInConsole(.applyDock)
        XCTAssertTrue(model.console === session, "the pane's command waits")

        session.stop()
        await first.value
        XCTAssertFalse(model.isBusy)

        await settings.runInConsole(.applyDock)
        let next = try XCTUnwrap(model.console)
        XCTAssertFalse(next === session)
        XCTAssertEqual(next.state, .exited(0))
        model.closeConsole()
    }

    /// A login item decision changes mrk: the Unrecorded panel's files, and
    /// the drift the panels count. mrk-status reads it again.
    func testADecisionRunsMrkStatusAgain() async throws {
        let stub = try StubMrk()
        try stub.answer("scripts/sync-login-items", ["--check"],
                        out: "add\tRaycast\t/Applications/Raycast.app\tnew\n")
        let model = stub.model()
        let settings = await model.settingsModel()
        await settings.loginItems.load()
        let row = try XCTUnwrap(settings.loginItems.rows.first { $0.name == "Raycast" })

        await settings.loginItems.decide(.add, row)

        XCTAssertTrue(stub.calls.contains { $0.hasPrefix("scripts/sync-login-items [--add] [Raycast]") },
                      "\(stub.calls)")
        while stub.statusCalls.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(stub.statusCalls, ["--json"])
    }

    /// The settings window's store is the one the model was given: a test's
    /// own, never the app's.
    func testThePaneIsRememberedInTheGivenStore() async throws {
        let stub = try StubMrk()
        let model = stub.model()
        await model.openSettings(.dock).value
        XCTAssertEqual(stub.store().string(forKey: "selectedPane"), "dock")
        XCTAssertNil(UserDefaults.app.string(forKey: "selectedPane"))
    }
}
