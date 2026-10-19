import XCTest
@testable import Dipstick

final class StatusRunnerTests: XCTestCase {
    func testLooksInMrkRootThenBinThenTheDefaultCheckout() {
        XCTAssertEqual(
            StatusRunner.candidates(environment: ["MRK_ROOT": "/w/mrk-wt"], home: "/Users/x"),
            ["/w/mrk-wt/bin/mrk-status", "/Users/x/bin/mrk-status", "/Users/x/mrk/bin/mrk-status"])
        XCTAssertEqual(
            StatusRunner.candidates(environment: [:], home: "/Users/x"),
            ["/Users/x/bin/mrk-status", "/Users/x/mrk/bin/mrk-status"])
    }

    func testMrkRootAtTheDefaultCheckoutIsNotListedTwice() {
        XCTAssertEqual(
            StatusRunner.candidates(environment: ["MRK_ROOT": "/Users/x/mrk"], home: "/Users/x"),
            ["/Users/x/mrk/bin/mrk-status", "/Users/x/bin/mrk-status"])
    }

    func testTheOverrideIsTheOnlyCandidate() {
        XCTAssertEqual(
            StatusRunner.candidates(environment: ["DIPSTICK_MRK_STATUS": "/tmp/ms", "MRK_ROOT": "/w"],
                                    home: "/Users/x"),
            ["/tmp/ms"])
    }

    func testNothingExecutableIsNotFound() {
        let result = StatusRunner.locate(environment: [:], home: "/Users/x", isExecutable: { _ in false })
        guard case .failure(.notFound(let searched)) = result else {
            return XCTFail("expected notFound, got \(result)")
        }
        XCTAssertEqual(searched.count, 2)
        XCTAssertEqual(StatusError.notFound(searched: searched).fix, "make build-tools")
    }

    private func result(_ status: Int32, out: String = "", err: String = "", timedOut: Bool = false) -> ProcessResult {
        ProcessResult(status: status, stdout: Data(out.utf8), stderr: Data(err.utf8), timedOut: timedOut)
    }

    func testAnMrkStatusWithoutJSONIsTooOld() {
        // What mrk-status before --json prints: its usage, then the flag.
        let r = StatusRunner.interpret(
            result(2, err: "Usage: mrk-status [--plain]\n\nunknown argument: --json\n"), path: "/p")
        XCTAssertEqual(r.failure, .tooOld(path: "/p"))
        XCTAssertEqual(r.failure?.fix, "make pull")
    }

    func testAFailureKeepsTheLastLineOfStderr() {
        let r = StatusRunner.interpret(
            result(1, err: "starting\nmrk-status: cannot determine home directory: x\n"), path: "/p")
        XCTAssertEqual(r.failure, .failed(status: 1, message: "mrk-status: cannot determine home directory: x"))
    }

    func testATimeoutWinsOverTheExitStatus() {
        let r = StatusRunner.interpret(result(15, timedOut: true), path: "/p")
        XCTAssertEqual(r.failure, .timedOut(seconds: StatusRunner.timeoutSeconds))
    }

    func testOutputThatIsNotTheDocumentIsUnreadable() {
        let r = StatusRunner.interpret(result(0, out: "✓ all clear\n"), path: "/p")
        guard case .unreadable = r.failure else { return XCTFail("expected unreadable, got \(r)") }
    }

    func testTheDocumentIsAReport() {
        let r = StatusRunner.interpret(result(0, out: sampleReport), path: "/p")
        XCTAssertEqual(try r.get().summary, "1 error")
    }

    /// End to end: a stand-in mrk-status, found by the override, run with
    /// `--json` from the home directory it is given.
    func testFetchRunsTheProgramWithJSON() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DipstickTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fixture = dir.appendingPathComponent("report.json")
        try sampleReport.write(to: fixture, atomically: true, encoding: .utf8)
        let stub = dir.appendingPathComponent("mrk-status")
        try """
        #!/bin/sh
        [ "$1" = --json ] || { echo "unknown argument: $1" >&2; exit 2; }
        [ "$(pwd -P)" = "$(cd "$HOME" && pwd -P)" ] || { echo "ran in $(pwd)" >&2; exit 3; }
        cat '\(fixture.path)'
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        let report = try await StatusRunner.fetch(
            environment: ["DIPSTICK_MRK_STATUS": stub.path, "HOME": dir.path, "PATH": "/usr/bin:/bin"],
            home: dir.path
        ).get()
        XCTAssertEqual(report.panels.count, 4)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
