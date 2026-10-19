import Foundation

/// A panel's or a line's severity, by the word `mrk-status --json` uses.
///
/// A word this build does not know reads as `.info`, so a newer mrk-status
/// that adds one shows the line neutrally instead of failing the whole report.
enum Severity: String, Decodable, Sendable {
    case ok, info, warn, error

    init(from decoder: Decoder) throws {
        let word = try decoder.singleValueContainer().decode(String.self)
        self = Severity(rawValue: word) ?? .info
    }

    /// A warning or an error: a line the window lists under the verdict.
    var isProblem: Bool { self == .warn || self == .error }
}

/// The `mrk-status --json` document: the dashboard's panels, as mrk-status
/// collects them. Every field is always present in schema 1, and a fix that
/// does not exist is "" (tools/mrk-status/json.go in mrk).
struct StatusReport: Decodable, Sendable, Equatable {
    /// The schema this build reads. mrk-status raises it when a field changes
    /// meaning or goes away; a new field alone does not raise it.
    static let supportedSchema = 1

    let schema: Int
    /// The header's verdict: the worst severity in any panel.
    let severity: Severity
    /// The header's words for it, such as "1 warning" or "all clear".
    let summary: String
    let panels: [Panel]

    static func decode(_ data: Data) throws -> StatusReport {
        try JSONDecoder().decode(StatusReport.self, from: data)
    }

    /// What is wrong, for the window to list under the verdict: each panel
    /// cut down to its lines that warn or err, each with the detail lines
    /// under it, in the report's order. A panel with no such line is left
    /// out, so a report that is all clear has no problems.
    var problems: [Panel] {
        panels.compactMap { panel in
            var kept: [Line] = []
            // The indent of the last line kept. A line indented past it is
            // that line's detail, and goes with it whatever its severity.
            var head: Int?
            for line in panel.lines {
                if let head, line.indent > head {
                    kept.append(line)
                    continue
                }
                head = nil
                if line.severity.isProblem {
                    kept.append(line)
                    head = line.indent
                }
            }
            return kept.isEmpty ? nil
                : Panel(name: panel.name, severity: panel.severity, fix: panel.fix, lines: kept)
        }
    }
}

struct Panel: Decodable, Sendable, Equatable, Identifiable {
    let name: String
    let severity: Severity
    /// The command the TUI's `f` key runs for this panel, or "".
    let fix: String
    let lines: [Line]

    var id: String { name }
}

struct Line: Decodable, Sendable, Equatable {
    let severity: Severity
    /// The line's text. Leading spaces mark a detail line under the one above.
    let text: String
    /// This line's own fix, shown beside it, or "".
    let fix: String

    /// How many levels the text is indented, at two spaces a level.
    var indent: Int {
        text.prefix(while: { $0 == " " }).count / 2
    }

    var trimmedText: String {
        String(text.drop(while: { $0 == " " }))
    }
}
