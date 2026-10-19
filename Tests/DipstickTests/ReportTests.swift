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
}
