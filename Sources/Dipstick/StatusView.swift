import SwiftUI

/// The window under the menu bar icon: the verdict, the four panels, and a
/// Run button beside every fix.
struct StatusView: View {
    let model: StatusModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.error {
                ErrorBanner(error: error, model: model)
                Divider()
            }
            if let report = model.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if report.schema > StatusReport.supportedSchema {
                            Text("This mrk-status writes schema \(report.schema); Dipstick reads \(StatusReport.supportedSchema). Some lines may be missing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(report.panels) { panel in
                            PanelSection(panel: panel, model: model)
                        }
                    }
                    .padding(12)
                }
            } else if model.error == nil {
                ProgressView("Running mrk-status…")
                    .controlSize(.small)
                    .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 440)
        .frame(maxHeight: 600)
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
            Button("mrk-menu") { model.runInTerminal("mrk-menu", confirm: false) }
                .help("Open the mrk-menu launcher in a terminal")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

private struct PanelSection: View {
    let panel: Panel
    let model: StatusModel
    @State private var expanded: Bool

    init(panel: Panel, model: StatusModel) {
        self.panel = panel
        self.model = model
        // A panel with something to say opens by itself.
        _expanded = State(initialValue: panel.severity == .warn || panel.severity == .error)
    }

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
                Spacer()
                if !panel.fix.isEmpty {
                    FixButton(command: panel.fix, model: model)
                }
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

    var body: some View {
        Button {
            model.runInTerminal(command)
        } label: {
            Label(command, systemImage: "terminal")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .controlSize(.small)
        .frame(maxWidth: 170, alignment: .trailing)
        .help("Run \(command) in a terminal")
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
