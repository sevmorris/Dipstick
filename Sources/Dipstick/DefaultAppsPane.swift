import AppKit
import SwiftUI

/// config/default-apps.tsv, the app that opens each file type and URL scheme,
/// against this Mac, with default-apps' own Snapshot and Apply.
struct DefaultAppsPane: View {
    @Bindable var model: SettingsModel
    @State private var confirmApply = false
    @State private var confirmSnapshot = false

    private var apps: DefaultAppsModel { model.defaultApps }

    var body: some View {
        VStack(spacing: 0) {
            PaneNote(text: "The app that opens each file type and link, from config/default-apps.tsv, against this Mac, "
                     + "from default-apps --check. An app can take a type when you install it. Apply gives each type "
                     + "back to its listed app; Snapshot records a type you gave to another app with Get Info. Neither commits.")
            Divider()
            if let error = apps.decisionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
            } else if !apps.snapshotLog.isEmpty {
                Label(apps.snapshotLog, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
            }
            PhaseView(phase: apps.phase, retry: apps.load) {
                List {
                    ForEach(apps.groups) { group in
                        Section {
                            ForEach(group.checks) { check in row(check) }
                        } header: {
                            AppLabel(bundleID: group.app, size: 16)
                        }
                    }
                }
            }
        }
        .navigationTitle("Default Apps")
        .navigationSubtitle(apps.phase == .loaded ? apps.subtitle : "")
        .toolbar {
            ToolbarItemGroup {
                if apps.busy { ProgressView().controlSize(.small) }
                RefreshButton(action: apps.load, busy: apps.phase.isLoading || apps.busy)
                Button { confirmSnapshot = true } label: {
                    Label("Snapshot…", systemImage: "square.and.arrow.down")
                }
                .disabled(apps.phase != .loaded || model.isDeciding)
                .help("Record the types you gave to an app by hand: default-apps --snapshot")
                Button { confirmApply = true } label: {
                    Label("Apply…", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(apps.phase != .loaded || apps.counts.drift == 0 || model.isDeciding)
                .help("Run \(TerminalCommand.applyDefaultApps.command) in Dipstick's console")
            }
        }
        .confirmationDialog("Give each type back to its listed app?", isPresented: $confirmApply) {
            Button("Apply") { Task { await model.runInConsole(.applyDefaultApps) } }
        } message: {
            Text("\(TerminalCommand.applyDefaultApps.command) changes \(apps.counts.drift) type(s), one at a time. "
                 + "macOS asks you to confirm each one in a dialog: read the buttons before you click, because "
                 + "their order changes. A type you keep for the other app is asked about again next time. "
                 + "It runs in Dipstick's console.")
        }
        .confirmationDialog("Record the types you gave to an app by hand?", isPresented: $confirmSnapshot) {
            Button("Snapshot") { Task { await apps.snapshot() } }
        } message: {
            Text("default-apps --snapshot reads the choices you made with Get Info and Change All, and writes "
                 + "them into config/default-apps.tsv. It does not record a type an app took for itself, and it "
                 + "commits nothing: mrk-push does.")
        }
        .task { if apps.phase == .idle { await apps.load() } }
    }

    @ViewBuilder
    private func row(_ check: DefaultAppCheck) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(check.title)
                Text(check.type).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            switch check.state {
            case .set:
                Badge(text: "set", color: .green)
            case .differs:
                HStack(spacing: 4) {
                    Text("opens in").font(.caption).foregroundStyle(.secondary)
                    AppLabel(bundleID: check.current, size: 14)
                }
                Badge(text: "another app", color: .orange)
            case .none:
                Badge(text: "no app", color: .orange)
            case .noapp:
                Badge(text: "app not installed", color: .secondary)
            case .unknown:
                Badge(text: "no app declares it", color: .secondary)
            }
        }
        .padding(.vertical, 2)
        .help(help(for: check))
    }

    private func help(for check: DefaultAppCheck) -> String {
        switch check.state {
        case .set: return "\(check.type) opens in \(check.app), as the list says."
        case .differs: return "\(check.type) opens in \(check.current), and the list says \(check.app). Apply gives it back; "
            + "if you chose \(check.current) with Get Info, Snapshot records it."
        case .none: return "No app opens \(check.type). Apply gives it to \(check.app)."
        case .noapp: return "\(check.app) is not on this Mac, so Apply skips \(check.type)."
        case .unknown: return "No app on this Mac declares \(check.type), so Apply skips it."
        }
    }
}

/// An app by its bundle identifier: its icon and name when it is on this Mac,
/// and the identifier when it is not.
struct AppLabel: View {
    let bundleID: String
    let size: CGFloat

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 5) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: size, height: size)
                Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .frame(width: size, height: size)
                    .foregroundStyle(.secondary)
                Text(bundleID).font(.body.monospaced())
            }
        }
        .help(bundleID)
    }
}
