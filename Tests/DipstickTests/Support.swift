import Foundation
import XCTest
@testable import Dipstick

/// Real output of mrk's scripts and the config/ files they read, from
/// Fixtures/, whose README says where each came from.
enum Fixture {
    static func text(_ path: String) throws -> String {
        let dir = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures")
        return try String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8)
    }
}

/// A stand-in mrk checkout and mrk-status in a temporary folder. No test runs
/// a real mrk command.
///
/// The checkout holds what a test writes into it, such as a Makefile with
/// stub targets, and stubs of the scripts mrk Settings runs: each records how
/// it was run in `calls.log`, then prints what its fixture files hold and
/// exits with the status they give. The mrk-status, found by
/// DIPSTICK_MRK_STATUS, records its arguments in the same log, waits as many
/// seconds as `delay` in the checkout says, and prints sampleReport.
final class StubMrk {
    let dir: URL
    let root: URL
    var checkout: MrkCheckout { MrkCheckout(root: root) }
    var log: URL { dir.appendingPathComponent("calls.log") }
    var mrkStatus: URL { dir.appendingPathComponent("mrk-status") }

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DipstickTests-\(UUID().uuidString)", isDirectory: true)
        root = dir.appendingPathComponent("my mrk", isDirectory: true)
        for sub in ["scripts", "config", "docs/defaults", "fixtures"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(sub),
                                                    withIntermediateDirectories: true)
        }
        for script in MrkCheckout.scripts { try stub(script) }
        for file in ["config/defaults.tsv", "docs/defaults/descriptions.tsv", "config/app-prefs.tsv",
                     "config/login-items.txt", "config/dock.txt"] {
            try write(file, "")
        }
        let report = dir.appendingPathComponent("report.json")
        try sampleReport.write(to: report, atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(log.path)'
        [ -f '\(root.path)/delay' ] && sleep "$(cat '\(root.path)/delay')"
        cat '\(report.path)'
        """.write(to: mrkStatus, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mrkStatus.path)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    /// The stub for SCRIPT. It logs one line — the script, each argument in
    /// brackets, the directory it ran in and whether stdin reached EOF at
    /// once — then prints fixtures/<name>.out to stdout and .err to stderr,
    /// and exits with fixtures/<name>.status (0 when absent). <name> is the
    /// script's file name, then each argument, joined by "_".
    private func stub(_ script: String) throws {
        let text = """
        #!/bin/bash
        name="${0##*/}"; for a in "$@"; do name+="_$a"; done
        name=${name// /-}
        if IFS= read -r _; then stdin=data; else stdin=eof; fi
        { printf '%s' "\(script)"; printf ' [%s]' "$@"; printf ' cwd=%s stdin=%s\\n' "$PWD" "$stdin"; } >> "\(log.path)"
        f="\(root.path)/fixtures/$name"
        [[ -f "$f.out" ]] && cat "$f.out"
        [[ -f "$f.err" ]] && cat "$f.err" >&2
        [[ -f "$f.status" ]] && exit "$(cat "$f.status")"
        exit 0
        """
        let url = root.appendingPathComponent(script)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func write(_ path: String, _ text: String) throws {
        try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Gives the checkout a scripts/mrk-contract that logs its run, as a
    /// script's stub does, and prints JSON, or exits with STATUS.
    func contract(_ json: String, status: Int32 = 0) throws {
        try write("fixtures/mrk-contract.json", json)
        let url = root.appendingPathComponent("scripts/mrk-contract")
        try """
        #!/bin/bash
        { printf 'scripts/mrk-contract'; printf ' [%s]' "$@"; printf ' cwd=%s\\n' "$PWD"; } >> "\(log.path)"
        cat "\(root.path)/fixtures/mrk-contract.json"
        exit \(status)
        """.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// The runs of scripts/mrk-contract in the log.
    var contractCalls: Int { calls.filter { $0.hasPrefix("scripts/mrk-contract") }.count }

    /// What a run of SCRIPT with ARGS prints and exits with.
    func answer(_ script: String, _ args: [String], out: String = "", err: String = "", status: Int32 = 0) throws {
        let name = ([(script as NSString).lastPathComponent] + args).joined(separator: "_")
            .replacingOccurrences(of: " ", with: "-")
        try write("fixtures/\(name).out", out)
        try write("fixtures/\(name).err", err)
        try write("fixtures/\(name).status", "\(status)")
    }

    /// The checkout's path with its links resolved, as `pwd -P` prints it.
    var realRoot: String {
        guard let resolved = realpath(root.path, nil) else { return root.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Each run of mrk-status, by its arguments, and of a script, by its line.
    var calls: [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    /// Each run of mrk-status: the log's lines that are not a script's.
    var statusCalls: [String] {
        calls.filter { !$0.hasPrefix("scripts/") }
    }

    func runner() -> MrkRunner {
        MrkRunner(environment: { ["PATH": "/usr/bin:/bin", "HOME": NSTemporaryDirectory()] })
    }

    /// A defaults suite of the test's own, named by a path in this folder,
    /// which goes when the folder does.
    func store() -> UserDefaults {
        UserDefaults(suiteName: dir.appendingPathComponent("defaults").path)!
    }

    /// A model over this checkout, with no window, no login shell asked, and
    /// mrk Settings' store in this folder.
    /// No Barkeep, unless the test gives one, so a test never opens the real
    /// one.
    @MainActor
    func model(findBarkeep: @escaping @MainActor () -> URL? = { nil },
               openInBarkeep: @escaping @MainActor (URL) -> Void = { _ in }) -> StatusModel {
        let env = ["PATH": "/usr/bin:/bin", "HOME": dir.path, "MRK_ROOT": root.path,
                   "DIPSTICK_MRK_STATUS": mrkStatus.path]
        return StatusModel(home: dir.path, opensWindows: false, environment: { env }, settingsStore: store(),
                           findBarkeep: findBarkeep, openInBarkeep: openInBarkeep)
    }
}
