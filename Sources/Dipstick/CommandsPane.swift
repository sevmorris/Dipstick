import SwiftUI

/// mrk-menu's commands, in its groups, from `mrk-menu --json`. Each row runs
/// its command exactly as it shows it, in the checkout, as mrk-menu does: in
/// Dipstick's console, or in a terminal for the ones the list marks.
struct CommandsPane: View {
    @Bindable var model: SettingsModel

    private var commands: CommandsModel { model.commands }

    var body: some View {
        @Bindable var commands = model.commands
        VStack(spacing: 0) {
            PaneNote(text: "mrk-menu's commands, from mrk-menu --json. Each runs exactly as shown, in the mrk checkout, "
                     + "after it asks: in Dipstick's console, or in Terminal where it says so. "
                     + "Unlike a fix, a command here never opens a pane or Barkeep instead.")
            Divider()
            PhaseView(phase: commands.phase, retry: commands.load) {
                let shown = commands.shown
                if shown.isEmpty {
                    ContentUnavailableView.search(text: commands.search)
                } else {
                    List {
                        ForEach(shown) { category in
                            Section(category.name) {
                                ForEach(category.commands) { command in
                                    CommandRow(command: command, busy: model.isDeciding) {
                                        model.run(command)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $commands.search, placement: .toolbar, prompt: "Filter commands")
        .navigationTitle("Commands")
        .navigationSubtitle(commands.phase == .loaded ? commands.subtitle : "")
        .toolbar {
            ToolbarItemGroup {
                RefreshButton(action: commands.load, busy: commands.phase.isLoading)
            }
        }
        .task { if commands.phase == .idle { await commands.load() } }
    }
}

/// One command: its line, what it does, where it runs, and Run….
private struct CommandRow: View {
    let command: CommandCatalog.Command
    let busy: Bool
    let run: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(command.name)
                    .font(.body.monospaced())
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Text(command.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if !command.typeToConfirm.isEmpty {
                Badge(text: "asks for “\(command.typeToConfirm)”", color: .red)
                    .help("Runs only after you type \(command.typeToConfirm), as mrk-menu asks")
            }
            if command.terminal {
                Badge(text: "Terminal", color: .blue)
                    .help("Runs in a terminal of its own: it can show a picker the console cannot draw, "
                          + "or it must not run inside Dipstick")
            }
            Button("Run…", action: run)
                .disabled(busy)
                .help(command.terminal
                      ? "Run \(command.command) in Terminal, in the mrk checkout"
                      : "Run \(command.command) in Dipstick's console, in the mrk checkout")
        }
        .padding(.vertical, 2)
    }
}
