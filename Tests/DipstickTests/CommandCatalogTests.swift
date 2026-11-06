import XCTest
@testable import Dipstick

/// The Commands pane's list, `mrk-menu --json` (BIN-1, mrk-menu), against
/// mrk-menu's real output (Fixtures/mrk-menu.json).
final class CommandCatalogTests: XCTestCase {
    private func realList() throws -> CommandCatalog {
        let text = try Fixture.text("mrk-menu.json")
        switch CommandCatalog.read(Data(text.utf8)) {
        case .success(let catalog): return catalog
        case .failure(let failure): throw failure
        }
    }

    private func command(_ name: String, in catalog: CommandCatalog) throws -> CommandCatalog.Command {
        try XCTUnwrap(catalog.categories.flatMap(\.commands).first { $0.name == name }, name)
    }

    func testTheRealListReads() throws {
        let catalog = try realList()
        XCTAssertEqual(catalog.schema, 1)
        XCTAssertEqual(catalog.categories.map(\.name),
                       ["Daily", "Brewfile", "Login items", "Preferences", "Diagnostics",
                        "Maintenance", "Setup", "Migration", "Nuclear options"])
        XCTAssertEqual(catalog.categories.flatMap(\.commands).count, 39)

        let push = try command("sync --push", in: catalog)
        XCTAssertEqual(push.command, "scripts/sync --push")
        XCTAssertTrue(push.terminal)
        XCTAssertEqual(push.typeToConfirm, "")
        XCTAssertFalse(push.description.isEmpty)

        XCTAssertEqual(try command("make doctor ARGS=--fix", in: catalog).command, "make doctor ARGS=--fix")
        XCTAssertEqual(try command("mrk-push", in: catalog).command, "bin/mrk-push")
        XCTAssertEqual(try command("nuke-mrk", in: catalog).typeToConfirm, "nuke")
    }

    /// The commands that must not run in the console: those that can start a
    /// picker, and update-full and nuke-mrk.
    func testTheRealListMarksTheTerminalCommands() throws {
        let terminal = try realList().categories.flatMap(\.commands).filter(\.terminal).map(\.name)
        XCTAssertEqual(terminal, ["sync --push", "sync-login-items -c", "sync", "sync --prune", "sync --dry-run",
                                  "sync-login-items", "update-full", "nuke-mrk"])
    }

    /// Each command's line names a tool of the checkout or make, as a fix's
    /// does, so the console runs it in the checkout as written.
    func testEachLineIsOneTheCheckoutRuns() throws {
        for command in try realList().categories.flatMap(\.commands) {
            let first = command.command.split(separator: " ").first.map(String.init) ?? ""
            XCTAssertTrue(first == "make" || first.hasPrefix("bin/") || first.hasPrefix("scripts/"), command.command)
        }
    }

    /// A new key keeps the schema, and a list with one still reads.
    func testANewKeyIsPassedOver() {
        let json = """
        {"schema": 1, "categories": [{"name": "Daily", "icon": "sun", "commands": [
          {"name": "mrk-push", "description": "commit", "command": "bin/mrk-push",
           "terminal": false, "type_to_confirm": "", "shortcut": "p"}]}]}
        """
        guard case .success(let catalog) = CommandCatalog.read(Data(json.utf8)) else {
            return XCTFail("a new key must not stop the list")
        }
        XCTAssertEqual(catalog.categories.first?.commands.first?.command, "bin/mrk-push")
    }

    /// A later schema is refused, whether or not it decodes: a key whose
    /// meaning changed could make a row run something other than it says.
    func testALaterSchemaIsNamedAndRefused() {
        let decodes = #"{"schema": 2, "categories": []}"#
        XCTAssertEqual(CommandCatalog.read(Data(decodes.utf8)), .failure(.newerSchema(2)))
        let renamed = #"{"schema": 2, "groups": []}"#
        XCTAssertEqual(CommandCatalog.read(Data(renamed.utf8)), .failure(.newerSchema(2)))
        XCTAssertTrue(CommandCatalog.Failure.newerSchema(2).localizedDescription.contains("Check for Updates"))
    }

    func testOutputThatIsNotTheListIsUnreadable() {
        guard case .failure(.unreadable) = CommandCatalog.read(Data("mrk-menu — interactive launcher".utf8)) else {
            return XCTFail("text is not a list")
        }
    }

    /// The search matches a name, a description or a category, as mrk-menu's
    /// `/` does, and keeps the menu's order.
    func testTheSearch() throws {
        let categories = try realList().categories
        XCTAssertEqual(CommandCatalog.filter(categories, ""), categories)
        XCTAssertEqual(CommandCatalog.filter(categories, "  "), categories)

        let prune = CommandCatalog.filter(categories, "PRUNE")
        XCTAssertEqual(prune.map(\.name), ["Brewfile", "Maintenance"])
        XCTAssertEqual(prune.flatMap(\.commands).map(\.name),
                       ["sync --prune", "make maintain", "tidy-projects --apply ff,refs,worktrees,branches",
                        "prune-deployments --dry-run", "prune-deployments"])

        let migration = CommandCatalog.filter(categories, "migration")
        XCTAssertEqual(migration.map(\.name), ["Migration"])
        XCTAssertEqual(migration.first?.commands.count, 5)

        XCTAssertEqual(CommandCatalog.filter(categories, "no such command"), [])
    }
}

/// The Commands pane: reading mrk-menu's list from the checkout, and running
/// a command as it is written.
@MainActor
final class CommandsPaneTests: XCTestCase {
    func testThePaneReadsMrkMenuInTheCheckout() async throws {
        let stub = try StubMrk()
        try stub.menu(try Fixture.text("mrk-menu.json"))
        let settings = await stub.model().settingsModel()

        await settings.load(.commands)

        XCTAssertEqual(settings.commands.phase, .loaded)
        XCTAssertEqual(settings.commands.count, 39)
        XCTAssertEqual(settings.commands.subtitle, "39 commands in 9 groups")
        XCTAssertEqual(stub.calls.filter { $0.hasPrefix("bin/mrk-menu") }, ["bin/mrk-menu [--json] cwd=\(stub.realRoot)"])
        settings.commands.search = "tidy"
        // In the menu's order: make tidy comes before tidy-projects in Maintenance.
        XCTAssertEqual(settings.commands.shown.flatMap(\.commands).map(\.name),
                       ["make tidy", "tidy-projects", "tidy-projects --apply ff,refs,worktrees,branches"])
    }

    /// make build-tools builds mrk-menu; a checkout that has not run it has
    /// none, and the pane says what to run.
    func testAnUnbuiltMrkMenuSaysToBuildIt() async throws {
        let stub = try StubMrk()
        let settings = await stub.model().settingsModel()

        await settings.load(.commands)

        guard case .failed(let message) = settings.commands.phase else { return XCTFail("\(settings.commands.phase)") }
        XCTAssertTrue(message.contains("make build-tools"), message)
        XCTAssertTrue(settings.commands.categories.isEmpty)
    }

    /// An mrk-menu from before --json refuses it, as it refuses any argument
    /// it does not know, and the pane says this mrk is older.
    func testAnMrkMenuWithoutJSONSaysToPull() async throws {
        let stub = try StubMrk()
        try stub.menu("", err: "mrk-menu — interactive launcher for mrk commands\n\nunknown argument: --json\n", status: 2)
        let settings = await stub.model().settingsModel()

        await settings.load(.commands)

        guard case .failed(let message) = settings.commands.phase else { return XCTFail("\(settings.commands.phase)") }
        XCTAssertTrue(message.contains("make pull"), message)
        XCTAssertTrue(message.contains("bin/mrk-menu does not take --json"), message)
    }

    private func entry(_ name: String, _ line: String, terminal: Bool = false, word: String = "") -> CommandCatalog.Command {
        CommandCatalog.Command(name: name, description: "what it does", command: line,
                               terminal: terminal, typeToConfirm: word)
    }

    /// A command runs as it is written, in the console: make defaults runs
    /// make defaults, where its fix would open the Defaults pane instead.
    func testACommandRunsAsWrittenNotThroughItsPane() async throws {
        let stub = try StubMrk()
        try stub.write("Makefile", "defaults:\n\t@echo applied\n")
        var asked: [String] = []
        let model = stub.model(confirmCommand: { command, directory in
            asked.append("\(command.command) in \(directory)")
            return ""
        })
        // The pane is in mrk Settings, which reads the login shell's
        // environment, and so the checkout, before it opens.
        _ = await model.settingsModel()

        await model.runCommand(entry("make defaults", "make defaults"))?.value

        XCTAssertEqual(asked, ["make defaults in ~/my mrk"])
        let session = try XCTUnwrap(model.console)
        XCTAssertEqual(session.command, "make defaults")
        XCTAssertEqual(session.state, .exited(0))
        XCTAssertTrue(session.screen.text.contains("applied"), session.screen.text)
        XCTAssertNotEqual(model.settings?.selection, .defaults, "the Defaults pane did not open")
        XCTAssertFalse(stub.calls.contains { $0.hasPrefix("scripts/defaults.sh") }, "\(stub.calls)")
        XCTAssertEqual(stub.statusCalls, ["--json"], "mrk-status ran again")
        model.closeConsole()
    }

    /// A command the list marks terminal opens a terminal, in the checkout,
    /// and never the console.
    func testATerminalCommandOpensATerminal() async throws {
        let stub = try StubMrk()
        var opened: [String] = []
        let model = stub.model(confirmCommand: { _, _ in "" },
                               launchTerminal: { command, directory, _ in opened.append("\(command) in \(directory)") })
        _ = await model.settingsModel()

        let task = model.runCommand(entry("sync --push", "scripts/sync --push", terminal: true))

        XCTAssertNil(task)
        XCTAssertEqual(opened, ["scripts/sync --push in \(stub.root.path)"])
        XCTAssertNil(model.console)
    }

    /// nuke-mrk runs only when its word is typed. Cancel runs nothing either.
    func testACommandWithAWordRunsOnlyWithThatWord() async throws {
        let stub = try StubMrk()
        var answer: String? = "nuk"
        var opened: [String] = []
        let model = stub.model(confirmCommand: { _, _ in answer },
                               launchTerminal: { command, _, _ in opened.append(command) })
        let nuke = entry("nuke-mrk", "bin/nuke-mrk", terminal: true, word: "nuke")

        model.runCommand(nuke)
        answer = "Nuke"
        model.runCommand(nuke)
        answer = nil
        model.runCommand(nuke)
        XCTAssertEqual(opened, [])

        answer = "nuke"
        model.runCommand(nuke)
        XCTAssertEqual(opened, ["bin/nuke-mrk"])
        XCTAssertNil(model.console)
    }

    /// Cancel runs nothing.
    func testCancelRunsNothing() async throws {
        let stub = try StubMrk()
        try stub.write("Makefile", "pull:\n\t@echo pulled\n")
        let model = stub.model()

        XCTAssertNil(model.runCommand(entry("make pull", "make pull")))
        XCTAssertNil(model.console)
        XCTAssertEqual(stub.statusCalls, [])
    }

    /// While a switch or a login item decision runs, the pane's commands
    /// wait, as its console commands do, and nothing is asked.
    func testACommandWaitsForADecision() async throws {
        let stub = try StubMrk()
        var asked = 0
        let model = stub.model(confirmCommand: { _, _ in asked += 1; return "" })
        let settings = await model.settingsModel()

        settings.loginItems.busy = "Rectangle"
        XCTAssertNil(settings.run(entry("make pull", "make pull")))
        XCTAssertEqual(asked, 0)
        XCTAssertNil(model.console)
    }
}
