import AppKit
import Foundation
import Observation

/// One run of a command in Dipstick's console, from its start to its exit:
/// the screen it prints to, and the keys typed at it. The command is a line
/// of shell: a fix as mrk-status writes it, a pane's TerminalCommand, or one
/// of mrk-menu's commands.
@Observable @MainActor
final class ConsoleSession: Identifiable {
    enum State: Equatable {
        case starting
        case running
        /// The exit status as a shell gives it.
        case exited(Int32)
        /// The command never started.
        case failed(String)
    }

    let id = UUID()
    let command: String
    /// The pane that reads mrk again when the command has exited, for a
    /// command a pane started.
    let pane: Pane?
    private(set) var screen = TerminalScreen()
    private(set) var state = State.starting
    /// How many times Stop was pressed. Each press sends a harder signal.
    private(set) var stops = 0
    /// The terminal's size in characters: as many as the console's screen
    /// holds (`resize`), or 80 × 24 until it says.
    private(set) var columns = 80
    private(set) var rows = 24
    @ObservationIgnored private var terminal: PseudoTerminal?

    init(command: String, pane: Pane? = nil) {
        self.command = command
        self.pane = pane
    }

    var isRunning: Bool { state == .starting || state == .running }

    /// Runs the command with zsh in `directory`, as the terminal window's
    /// shell ran it, and returns when it has exited.
    func run(environment: [String: String], directory: String) async {
        guard state == .starting else { return }
        screen.feed("\u{1B}[1m$ \(command)\u{1B}[0m\r\n")
        let events: AsyncStream<PseudoTerminal.Event>
        do {
            let started = try PseudoTerminal.start(
                "/bin/zsh", arguments: ["-c", command],
                environment: environment, directory: directory,
                columns: UInt16(columns), rows: UInt16(rows))
            terminal = started.0
            events = started.1
        } catch {
            state = .failed("\(command) could not start: \(error.localizedDescription)")
            return
        }
        state = .running
        for await event in events {
            switch event {
            case .output(let data):
                screen.feed(data)
                // What the program asked, answered as it waits: the colours
                // and the cursor's place, which termenv waits five seconds
                // for.
                let replies = screen.takeReplies()
                if !replies.isEmpty { terminal?.write(replies) }
            case .exit(let status):
                screen.programExited()
                if !screen.atLineStart { screen.feed("\r\n") }
                screen.feed("\u{1B}[2m[exited \(status)]\u{1B}[0m")
                state = .exited(status)
            }
        }
        terminal = nil
    }

    /// Types at the command's terminal.
    func type(_ bytes: [UInt8]) {
        guard state == .running, let terminal else { return }
        if !terminal.write(bytes) { NSSound.beep() }
    }

    /// The console's screen holds `columns` × `rows` characters now. The
    /// screen takes the size, and so does the terminal, which tells the
    /// program.
    func resize(columns: Int, rows: Int) {
        let columns = min(Int(UInt16.max), max(2, columns))
        let rows = min(Int(UInt16.max), max(2, rows))
        guard columns != self.columns || rows != self.rows else { return }
        self.columns = columns
        self.rows = rows
        screen.resize(columns: columns, rows: rows)
        terminal?.resize(columns: UInt16(columns), rows: UInt16(rows))
    }

    /// The colours the terminal says it draws in, when a program asks: the
    /// screen's look, so that lipgloss picks its dark colours for a tube.
    func reportColors(foreground: TerminalScreen.RGB, background: TerminalScreen.RGB) {
        guard screen.foregroundColor != foreground || screen.backgroundColor != background else { return }
        screen.foregroundColor = foreground
        screen.backgroundColor = background
    }

    /// SIGINT, as ⌃C sends; then SIGTERM; then SIGKILL. A script that traps
    /// ⌃C to tidy up, as mrk's do, gets its chance first, and one that
    /// ignores it still stops.
    func stop() {
        guard state == .running, let terminal else { return }
        let signals = [SIGINT, SIGTERM, SIGKILL]
        terminal.send(signal: signals[min(stops, signals.count - 1)])
        stops += 1
    }
}
