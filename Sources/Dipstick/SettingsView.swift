import AppKit
import SwiftUI

/// mrk Settings: Dipstick's window over mrk's lists in config/, one pane for
/// each. What a pane runs in the console runs in Dipstick's console window,
/// and while it runs the panes wait, as the menu bar's fixes do.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    let status: StatusModel

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $model.selection) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let update = status.availableUpdate {
                        Button {
                            Task { await status.checkForUpdates() }
                        } label: {
                            Label("Dipstick \(update.version) is available", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.link)
                        .padding(.bottom, 4)
                        .help("A newer Dipstick is out: download it or read its release notes")
                    }
                    Text(model.checkout.root.path)
                        .font(.caption.monospaced())
                        .lineLimit(1).truncationMode(.middle)
                    Text("Dipstick \(appVersion) never commits. mrk-push does.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        } detail: {
            VStack(spacing: 0) {
                if let console = status.console, console.isRunning {
                    ConsoleBusyBanner(session: console, status: status)
                    Divider()
                }
                Group {
                    if let problem = model.checkoutProblem {
                        ContentUnavailableView("No mrk checkout", systemImage: "folder.badge.questionmark",
                                               description: Text(problem))
                    } else {
                        switch model.selection ?? .preferences {
                        case .preferences: PrefsPane(model: model)
                        case .defaults: DefaultsPane(model: model)
                        case .loginItems: LoginItemsPane(model: model)
                        case .dock: DockPane(model: model)
                        }
                    }
                }
                // A pane's switches and buttons run mrk's scripts, and the
                // command in the console may be changing what they read.
                .disabled(status.isConsoleRunning)
            }
        }
    }
}

/// Over the pane while the console runs a command: what it is, and a way
/// back to it.
private struct ConsoleBusyBanner: View {
    let session: ConsoleSession
    let status: StatusModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(session.command)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Text("is running in the console. The panes wait for it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Show Console") { status.showConsole() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Shared pieces

/// The pane's loading and failure states over its content.
struct PhaseView<Content: View>: View {
    let phase: LoadPhase
    let retry: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            states
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var states: some View {
        switch phase {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView {
                Label("mrk refused", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message).textSelection(.enabled)
            } actions: {
                Button("Try Again") { Task { await retry() } }
            }
        case .loaded:
            content()
        }
    }
}

/// A line under the pane's title that says what the pane shows and where it
/// comes from.
struct PaneNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct RefreshButton: View {
    let action: () async -> Void
    let busy: Bool
    var body: some View {
        Button { Task { await action() } } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(busy)
        .help("Run the check again")
    }
}

extension LoadPhase {
    var isLoading: Bool { self == .loading }
}
