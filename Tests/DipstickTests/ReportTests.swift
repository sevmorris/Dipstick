import XCTest
@testable import Dipstick

/// The shape `mrk-status --json` writes, schema 1, cut down from a real run.
let sampleReport = """
{
  "schema": 1,
  "severity": "error",
  "summary": "1 error",
  "panels": [
    {
      "name": "Unrecorded",
      "severity": "warn",
      "fix": "make sync ARGS=-c",
      "lines": [
        { "severity": "warn", "text": "2 packages installed, not in the Brewfile: jq, nasm", "fix": "make sync ARGS=-c" },
        { "severity": "ok", "text": "~/mrk: committed and pushed", "fix": "" }
      ]
    },
    {
      "name": "Upkeep",
      "severity": "ok",
      "fix": "",
      "lines": [
        { "severity": "ok", "text": "No macOS update for macOS 26", "fix": "" },
        { "severity": "info", "text": "  offered, and never installed by mrk, being a major upgrade: macOS 27.0.1", "fix": "" }
      ]
    },
    {
      "name": "Time Machine Backups",
      "severity": "error",
      "fix": "",
      "lines": [
        { "severity": "error", "text": "Last backup 9 days ago (2026-10-09 11:17), 1 destination", "fix": "" }
      ]
    },
    {
      "name": "Installation",
      "severity": "ok",
      "fix": "",
      "lines": []
    }
  ]
}
"""

final class ReportTests: XCTestCase {
    func testDecodesTheSchema1Document() throws {
        let report = try StatusReport.decode(Data(sampleReport.utf8))
        XCTAssertEqual(report.schema, 1)
        XCTAssertEqual(report.severity, .error)
        XCTAssertEqual(report.summary, "1 error")
        XCTAssertEqual(report.panels.map(\.name),
                       ["Unrecorded", "Upkeep", "Time Machine Backups", "Installation"])
        XCTAssertEqual(report.panels[0].fix, "make sync ARGS=-c")
        XCTAssertEqual(report.panels[0].lines[0].fix, "make sync ARGS=-c")
        XCTAssertEqual(report.panels[0].lines[1].fix, "")
        XCTAssertEqual(report.panels[3].lines, [])
    }

    func testAnUnknownSeverityReadsAsInfo() throws {
        let json = #"{"schema":1,"severity":"catastrophic","summary":"x","panels":[]}"#
        XCTAssertEqual(try StatusReport.decode(Data(json.utf8)).severity, .info)
    }

    func testAMissingFieldIsAnError() {
        // Schema 1 promises every field; a document without one is not it.
        let json = #"{"schema":1,"severity":"ok","panels":[]}"#
        XCTAssertThrowsError(try StatusReport.decode(Data(json.utf8)))
    }

    func testLeadingSpacesAreAnIndent() throws {
        let report = try StatusReport.decode(Data(sampleReport.utf8))
        let detail = report.panels[1].lines[1]
        XCTAssertEqual(detail.indent, 1)
        XCTAssertTrue(detail.trimmedText.hasPrefix("offered, and never installed"))
        XCTAssertEqual(report.panels[1].lines[0].indent, 0)
    }

    // MARK: - Problems

    func testProblemsAreTheLinesThatWarnOrErrInTheReportsOrder() throws {
        let report = try StatusReport.decode(Data(sampleReport.utf8))
        let problems = report.problems
        XCTAssertEqual(problems.map(\.name), ["Unrecorded", "Time Machine Backups"])
        XCTAssertEqual(problems[0].lines.map(\.text),
                       ["2 packages installed, not in the Brewfile: jq, nasm"])
        XCTAssertEqual(problems[0].lines[0].fix, "make sync ARGS=-c")
        XCTAssertEqual(problems[1].lines.map(\.severity), [.error])
        // Each panel keeps its name and severity, cut down to its problems.
        XCTAssertEqual(problems[0].severity, .warn)
        XCTAssertEqual(problems[1].severity, .error)
    }

    func testAnAllClearReportHasNoProblems() {
        let report = StatusReport(schema: 1, severity: .ok, summary: "all clear", panels: [
            Panel(name: "Upkeep", severity: .ok, fix: "", lines: [
                Line(severity: .ok, text: "No macOS update for macOS 26", fix: ""),
                Line(severity: .info, text: "  offered, and never installed by mrk, being a major upgrade: macOS 27.0.1", fix: ""),
            ]),
            Panel(name: "Installation", severity: .ok, fix: "", lines: []),
        ])
        XCTAssertEqual(report.problems, [])
    }

    func testAProblemKeepsTheDetailLinesUnderIt() {
        // As the Unrecorded and Installation panels write them: a line that
        // warns or errs, then its details, indented, whatever their severity.
        let report = StatusReport(schema: 1, severity: .error, summary: "1 error, 1 warning", panels: [
            Panel(name: "Unrecorded", severity: .warn, fix: "bin/pushall", lines: [
                Line(severity: .ok, text: "~/mrk: committed and pushed", fix: ""),
                Line(severity: .info, text: "  1 untracked file, which mrk-push never commits", fix: ""),
                Line(severity: .warn, text: "~/Projects: 1 repository with uncommitted changes: Dipstick", fix: "bin/pushall"),
                Line(severity: .info, text: "  no upstream, so pushall skips them: Dipstick", fix: ""),
                Line(severity: .ok, text: "The manifest records every repository in ~/Projects", fix: ""),
            ]),
            Panel(name: "Installation", severity: .error, fix: "make build-tools", lines: [
                Line(severity: .warn, text: "Tools — Not built: mrk-status", fix: "make build-tools"),
                Line(severity: .warn, text: "  Older than their source: picker", fix: ""),
                Line(severity: .info, text: "    rebuilt by make build-tools", fix: ""),
                Line(severity: .ok, text: "Dotfiles — all linked", fix: ""),
                Line(severity: .error, text: "Defaults — 1 key unreadable", fix: ""),
            ]),
        ])
        let problems = report.problems
        XCTAssertEqual(problems.map(\.name), ["Unrecorded", "Installation"])
        XCTAssertEqual(problems[0].lines.map(\.text), [
            "~/Projects: 1 repository with uncommitted changes: Dipstick",
            "  no upstream, so pushall skips them: Dipstick",
        ])
        XCTAssertEqual(problems[1].lines.map(\.text), [
            "Tools — Not built: mrk-status",
            "  Older than their source: picker",
            "    rebuilt by make build-tools",
            "Defaults — 1 key unreadable",
        ])
    }

    func testAnUnknownSeverityIsNotAProblem() throws {
        // It reads as .info, so a newer mrk-status's new word stays out of the
        // list instead of raising an alarm this build cannot explain.
        let json = #"{"schema":1,"severity":"warn","summary":"x","panels":[{"name":"P","severity":"warn","fix":"","lines":[{"severity":"catastrophic","text":"t","fix":""}]}]}"#
        XCTAssertEqual(try StatusReport.decode(Data(json.utf8)).problems, [])
    }
}
