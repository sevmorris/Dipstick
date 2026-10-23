import SwiftUI

/// The window under the menu bar icon: the verdict, the fix in the console,
/// each warning and error, the four panels, and a Run button beside every fix.
struct StatusView: View {
    let model: StatusModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let console = model.console {
                ConsoleBanner(session: console, model: model)
                Divider()
            }
            if let error = model.error {
                ErrorBanner(error: error, model: model)
                Divider()
            }
            if let report = model.report {
                ReportList(report: report, model: model)
            } else if model.error == nil {
                ProgressView("Running mrk-status…")
                    .controlSize(.small)
                    .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 440)
        .onAppear { model.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.symbolName)
                .font(.title2)
                .foregroundStyle(model.report.map { $0.severity.color } ?? .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.report?.summary.capitalizedFirst ?? "mrk")
                    .font(.headline)
                Text(model.tilde(model.repoRoot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.refresh(reloadEnvironment: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Run mrk-status again")
            }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if let date = model.lastRefreshed {
                Text("Checked \(Text(date, style: .relative)) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let update = model.availableUpdate {
                Button {
                    Task { await model.checkForUpdates() }
                } label: {
                    Label("Dipstick \(update.version)", systemImage: "arrow.down.circle.fill")
                }
                .help("A newer Dipstick is out: download it or read its release notes")
            } else {
                Button("Check for Updates…") { Task { await model.checkForUpdates() } }
                    .help("Ask GitHub for a Dipstick newer than \(UpdateChecker.installedVersion)")
            }
            Button("mrk-menu") { model.run("mrk-menu", confirm: false) }
                .help("Open the mrk-menu launcher in a terminal")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// The fix in the console, which has a window of its own: a window that
/// slips behind another app's has no Dock icon to bring it back.
private struct ConsoleBanner: View {
    let session: ConsoleSession
    let model: StatusModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(session.command)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Text(state)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Show") { model.showConsole() }
                .controlSize(.small)
                .help("Bring the console to the front")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var state: String {
        switch session.state {
        case .starting, .running: return "is running"
        case .exited(0): return "finished"
        case .exited(let status) where status > 128: return "was stopped"
        case .exited(let status): return "exited \(status)"
        case .failed: return "did not start"
        }
    }
}

private struct ErrorBanner: View {
    let error: StatusError
    let model: StatusModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.bubble")
                .foregroundStyle(.orange)
            Text(error.message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let fix = error.fix {
                FixButton(command: fix, model: model)
            }
        }
        .padding(12)
    }
}

/// The report: what is wrong first, then the four panels. One list that is as
/// tall as what it holds, up to maxHeight, and scrolls past that.
private struct ReportList: View {
    let report: StatusReport
    let model: StatusModel
    /// The height of the list's content, as last laid out.
    @State private var contentHeight: CGFloat = 0

    /// Room for a day's few problems and the four panels, closed. A longer
    /// list scrolls, and the window stays well clear of the bottom of a
    /// laptop's screen.
    static let maxHeight: CGFloat = 520

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if report.schema > StatusReport.supportedSchema {
                    Text("This mrk-status writes schema \(report.schema); Dipstick reads \(StatusReport.supportedSchema). Some lines may be missing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let problems = report.problems
                if !problems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(problems) { panel in
                            ProblemGroup(panel: panel, model: model)
                        }
                    }
                    Divider()
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.panels) { panel in
                        PanelSection(panel: panel, model: model)
                    }
                }
            }
            .padding(12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        // The menu bar window is as tall as its content asks to be, and a
        // ScrollView asks for no height at all: alone, it gets 0 pt, which
        // is how v0.1 showed the verdict and none of the panels. So the list
        // asks for the height of what it holds, up to the cap.
        .frame(height: min(contentHeight.rounded(.up), Self.maxHeight))
    }
}

/// One panel's warnings and errors, under the panel's name.
private struct ProblemGroup: View {
    let panel: Panel
    let model: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(panel.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(panel.lines.enumerated()), id: \.offset) { _, line in
                LineRow(line: line, model: model)
            }
        }
    }
}

/// A panel and all its lines, closed until clicked: its warnings and errors
/// are already listed above it, fix and all.
private struct PanelSection: View {
    let panel: Panel
    let model: StatusModel
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(panel.lines.enumerated()), id: \.offset) { _, line in
                    LineRow(line: line, model: model)
                }
            }
            .padding(.top, 4)
            // Under the panel's name, past its severity icon.
            .padding(.leading, 22)
        } label: {
            HStack(spacing: 6) {
                SeverityIcon(severity: panel.severity)
                Text(panel.name).fontWeight(.semibold)
            }
        }
    }
}

private struct LineRow: View {
    let line: Line
    let model: StatusModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            SeverityIcon(severity: line.severity)
                .font(.caption)
            Text(line.trimmedText)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if !line.fix.isEmpty {
                FixButton(command: line.fix, model: model)
            }
        }
        .padding(.leading, CGFloat(line.indent) * 14)
    }
}

/// The fix's own command is the label, so what a click runs is never a guess.
private struct FixButton: View {
    let command: String
    let model: StatusModel

    private var inTerminal: Bool { TerminalLauncher.isNeeded(for: command) }
    /// The console takes one fix at a time.
    private var waiting: Bool { !inTerminal && model.isConsoleRunning }

    var body: some View {
        Button {
            model.run(command)
        } label: {
            Label(command, systemImage: "terminal")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .controlSize(.small)
        .frame(maxWidth: 170, alignment: .trailing)
        .disabled(waiting)
        .help(waiting ? "Another fix is running in the console"
              : inTerminal ? "Run \(command) in a terminal: it draws a full-screen picker"
              : "Run \(command) in Dipstick's console")
    }
}

private struct SeverityIcon: View {
    let severity: Severity

    var body: some View {
        Image(systemName: severity.symbolName)
            .foregroundStyle(severity.color)
    }
}

extension Severity {
    var symbolName: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok: return .green
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }
}

private extension String {
    /// "1 warning" → "1 warning", "all clear" → "All clear".
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
