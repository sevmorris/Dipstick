import Foundation
import XCTest
@testable import Dipstick

/// A stand-in mrk checkout and mrk-status in a temporary folder, as Gearbox's
/// tests have one. The checkout holds what a test writes into it, a Makefile
/// with stub targets. The mrk-status, found by DIPSTICK_MRK_STATUS, records
/// how it was run in `calls.log`, waits as many seconds as `delay` in the
/// checkout says, and prints sampleReport. No test runs a real mrk command.
final class StubMrk {
    let dir: URL
    let root: URL
    var log: URL { dir.appendingPathComponent("calls.log") }
    var mrkStatus: URL { dir.appendingPathComponent("mrk-status") }

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DipstickTests-\(UUID().uuidString)", isDirectory: true)
        root = dir.appendingPathComponent("my mrk", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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

    func write(_ path: String, _ text: String) throws {
        try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    /// The checkout's path with its links resolved, as `pwd -P` prints it.
    var realRoot: String {
        guard let resolved = realpath(root.path, nil) else { return root.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Each run of mrk-status, by its arguments.
    var calls: [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    /// A model over this checkout, with no window and no login shell asked.
    @MainActor
    func model() -> StatusModel {
        let env = ["PATH": "/usr/bin:/bin", "HOME": dir.path, "MRK_ROOT": root.path,
                   "DIPSTICK_MRK_STATUS": mrkStatus.path]
        return StatusModel(home: dir.path, opensWindows: false, environment: { env })
    }
}
