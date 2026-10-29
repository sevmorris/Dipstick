import XCTest
@testable import Dipstick

/// mrk's scripts/mrk-contract, and how MrkRunner uses it: an option the
/// checkout's scripts do not take is refused before any run, and an exit 2 is
/// then mrk refusing the command line (sevmorris/mrk audit 22, O-2).
final class ContractTests: XCTestCase {
    /// Every command line Dipstick builds, a dash name and the trackpad keys
    /// included.
    static let everyCommand: [MrkCommand] = [
        .prefsCheck, .defaultsCheck(withTrackpad: false), .defaultsCheck(withTrackpad: true),
        .defaultsOff([DefaultsKey(domain: "a", key: "b")]), .defaultsOn([DefaultsKey(domain: "a", key: "b")]),
        .defaultsApply([DefaultsKey(domain: "a", key: "b")]), .loginItemsCheck,
        .loginItemsAdd("A"), .loginItemsIgnore("A"), .loginItemsRemove("A"),
        .loginItemsAdd("-A"), .loginItemsIgnore("-A"), .loginItemsRemove("-A"), .dockCheck,
    ]

    /// A contract with each script Dipstick runs, and the options given, and
    /// the terminal targets when given.
    static func contract(version: Int = 1, defaults: [String] = ["--check", "--with-trackpad", "--skip", "--unskip", "--key", "--revert"],
                         loginItems: [String] = ["--check", "--add", "--ignore", "--remove"],
                         equals: [String] = ["--add", "--ignore", "--remove"],
                         terminal: [String]? = nil) -> String {
        func list(_ words: [String]) -> String { "[" + words.map { "\"\($0)\"" }.joined(separator: ", ") + "]" }
        return """
        {"contract": \(version), "about": "", "later": {"a key": "a later mrk adds"}, "scripts": {
          "scripts/defaults.sh": {"options": \(list(defaults)), "equals": [], "decisions": [], "check": null},
          "scripts/sync-login-items": {"options": \(list(loginItems)), "equals": \(list(equals)), "decisions": [], "check": null},
          "scripts/snapshot-prefs": {"options": ["--check"], "equals": [], "decisions": [], "check": null},
          "scripts/dock-setup": {"options": ["--check"], "equals": [], "decisions": [], "check": null}
        }\(terminal.map { #", "terminal": "# + list($0) } ?? "")}
        """
    }

    /// The contract of the mrk Dipstick is built against takes every option
    /// of every command Dipstick runs. Fixtures/README.md says whence.
    func testTheRealContractTakesEveryCommand() throws {
        let contract = try MrkContract.decode(Data(try Fixture.text("mrk-contract.json").utf8))
        XCTAssertEqual(contract.contract, MrkContract.supportedVersion)
        XCTAssertFalse(contract.isNewer)
        for command in Self.everyCommand {
            XCTAssertEqual(contract.missing(command), [], "\(command)")
        }
    }

    /// Each option a command lists is one of its arguments, by name or as
    /// NAME=VALUE.
    func testTheOptionsAreTheArgumentsGiven() {
        for command in Self.everyCommand {
            for option in command.options {
                XCTAssertTrue(command.arguments.contains {
                    option.equals ? $0.hasPrefix(option.name + "=") : $0 == option.name
                }, "\(command): \(option)")
            }
            let given = command.arguments.filter { $0.hasPrefix("--") }
                .map { $0.split(separator: "=", maxSplits: 1).first.map(String.init) ?? $0 }
            XCTAssertEqual(Set(given), Set(command.options.map(\.name)), "\(command)")
        }
    }

    func testWhatAContractDoesNotTake() throws {
        let old = try MrkContract.decode(Data(Self.contract(defaults: ["--check"], equals: []).utf8))
        XCTAssertEqual(old.missing(.defaultsCheck(withTrackpad: true)), ["--with-trackpad"])
        XCTAssertEqual(old.missing(.defaultsOff([DefaultsKey(domain: "a", key: "b")])), ["--skip", "--revert"])
        XCTAssertEqual(old.missing(.loginItemsAdd("A")), [])
        XCTAssertEqual(old.missing(.loginItemsAdd("-A")), ["--add=…"])
        let none = try MrkContract.decode(Data(#"{"contract": 1, "scripts": {}}"#.utf8))
        XCTAssertNil(none.missing(.dockCheck), "a contract that does not name the script says nothing about it")
        XCTAssertTrue(try MrkContract.decode(Data(Self.contract(version: 2).utf8)).isNewer)
    }

    /// An option the contract does not list: refused before the script runs,
    /// with make pull, and the contract read once for the two commands.
    func testAnOptionTheContractLacksIsAnOlderMrk() async throws {
        let stub = try StubMrk()
        try stub.contract(Self.contract(defaults: ["--check"]))
        let runner = stub.runner()
        do {
            _ = try await runner.run(.defaultsCheck(withTrackpad: true), in: stub.checkout)
            XCTFail("expected a refusal")
        } catch let error as MrkError {
            guard case .notTaken = error else { return XCTFail("\(error)") }
            XCTAssertEqual(error.errorDescription,
                           "scripts/defaults.sh does not take --with-trackpad: this mrk is older than Dipstick. Run make pull in \(stub.root.path).")
            XCTAssertNil(error.status)
        }
        _ = try await runner.run(.defaultsCheck(withTrackpad: false), in: stub.checkout)
        XCTAssertEqual(stub.calls.filter { $0.hasPrefix("scripts/defaults.sh") }.count, 1, "\(stub.calls)")
        XCTAssertEqual(stub.contractCalls, 1)
    }

    /// With the contract listing the option, an exit 2 that names an option
    /// as unknown is still mrk's reason, not "run make pull".
    func testWithAContractExitTwoIsMrksReason() async throws {
        let stub = try StubMrk()
        try stub.contract(Self.contract())
        try stub.answer("sync-login-items", ["--add=-x"],
                        err: "  ✗ Unknown option: --add=-x\n    Run sync-login-items --help for the options.\n", status: 2)
        do {
            _ = try await stub.runner().run(.loginItemsAdd("-x"), in: stub.checkout)
            XCTFail("expected a refusal")
        } catch let error as MrkError {
            XCTAssertEqual(error.status, 2)
            XCTAssertEqual(error.errorDescription, "Unknown option: --add=-x")
        }
    }

    /// A contract of a later version that lacks an option: this Dipstick is
    /// the older side.
    func testANewerContractThatLacksAnOptionIsAnOlderDipstick() async throws {
        let stub = try StubMrk()
        try stub.contract(Self.contract(version: 2, loginItems: ["--check", "--add", "--ignore"]))
        do {
            _ = try await stub.runner().run(.loginItemsRemove("A"), in: stub.checkout)
            XCTFail("expected a refusal")
        } catch let error as MrkError {
            XCTAssertTrue(error.errorDescription!.hasPrefix("scripts/sync-login-items does not take --remove: this Dipstick is older than mrk."),
                          error.errorDescription!)
            XCTAssertTrue(error.errorDescription!.contains("Check for Updates"))
        }
        XCTAssertFalse(stub.calls.contains { $0.hasPrefix("scripts/sync-login-items") })
    }

    /// make pull changes scripts/mrk-contract, and the next run reads it again.
    func testTheContractIsReadAgainWhenTheFileChanges() async throws {
        let stub = try StubMrk()
        try stub.contract(Self.contract(defaults: ["--check"]))
        let runner = stub.runner()
        let trackpad = MrkCommand.defaultsCheck(withTrackpad: true)
        await XCTAssertThrowsErrorAsync(try await runner.run(trackpad, in: stub.checkout))
        try stub.contract(Self.contract())
        let url = stub.root.appendingPathComponent("scripts/mrk-contract")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        _ = try await runner.run(trackpad, in: stub.checkout)
        XCTAssertEqual(stub.contractCalls, 2)
    }

    /// No mrk-contract, one that fails, and one that prints something else:
    /// the run goes ahead, and an exit 2 is read by its stderr, as before the
    /// contract.
    func testWithNoContractExitTwoIsReadByItsStderr() async throws {
        for setup in ["none", "fails", "not JSON"] {
            let stub = try StubMrk()
            switch setup {
            case "fails": try stub.contract(Self.contract(), status: 1)
            case "not JSON": try stub.contract("usage: mrk-contract\n")
            default: break
            }
            try stub.answer("dock-setup", ["--check"], err: "unknown argument: --check\n", status: 2)
            do {
                _ = try await stub.runner().run(.dockCheck, in: stub.checkout)
                XCTFail("\(setup): expected a refusal")
            } catch let error as MrkError {
                XCTAssertTrue(error.errorDescription!.contains("this mrk is older than Dipstick. Run make pull"),
                              "\(setup): \(error.errorDescription!)")
            }
        }
    }
}

/// XCTAssertThrowsError for an async expression.
func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {}
}
