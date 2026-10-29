import AppKit

/// Runs a command in a terminal window, the way the mrk-status TUI runs a fix:
/// `cd <checkout> && <fix>`, with the terminal attached.
///
/// Dipstick 0.2 ran every fix this way. Now most run in Dipstick's console,
/// which answers prompts and sudo's password but is a dumb terminal: it cannot
/// draw a full screen. This is for the few that do (`isNeeded`). Dipstick
/// writes the command into a `.command` file and opens it, which starts it in
/// whichever terminal opens `.command` files — Terminal unless another app has
/// claimed them. That needs no Automation permission, as scripting Terminal
/// would.
enum TerminalLauncher {
    /// The programs that draw a full screen: they move the cursor about it and
    /// read the arrow keys, and the console does neither. mrk-menu is a
    /// bubbletea launcher, mrk-picker is mrk's package picker, and gum's
    /// `choose` is the list mrk's scripts pick from.
    static let fullScreenPrograms: Set<String> = ["mrk-menu", "mrk-picker", "gum"]

    /// The Make targets whose scripts start one of those programs, for an mrk
    /// whose scripts/mrk-contract does not list them (`targets(in:)`): one
    /// from before mrk-contract, or from before its `terminal` list. A later
    /// mrk names them itself, and its tests hold the list to the Makefile.
    static let fullScreenTargets: Set<String> = [
        // scripts/sync: mrk-picker for the packages the Brewfile lacks, and
        // gum choose for the entries nothing installs. `make sync ARGS=-c`.
        "sync",
        // scripts/sync-login-items: gum choose for the login items to add,
        // drop and settle. `make sync-login-items ARGS=-c`.
        "sync-login-items",
        // scripts/brew: gum choose, or mrk-picker, for what to install.
        "brew",
    ]

    /// The Make targets that need a terminal in a checkout whose contract is
    /// `contract`: its `terminal` list, or `fullScreenTargets` when there is
    /// no contract or it has no list (sevmorris/mrk audit 22, opportunity 5).
    static func targets(in contract: MrkContract?) -> Set<String> {
        contract?.terminal.map(Set.init) ?? fullScreenTargets
    }

    /// Whether `command`, a fix as mrk-status writes it, needs a terminal
    /// window of its own, where `targets` are the Make targets that do. Every
    /// other fix runs in Dipstick's console.
    static func isNeeded(for command: String, targets: Set<String> = fullScreenTargets) -> Bool {
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let program = words.first else { return false }
        if fullScreenPrograms.contains((program as NSString).lastPathComponent) { return true }
        return makeTarget(of: command).map(targets.contains) ?? false
    }

    /// The Make target `command` runs, or nil when it is not `make`. make's
    /// target is its first word that is neither an option nor a variable:
    /// `make sync ARGS=-c`.
    static func makeTarget(of command: String) -> String? {
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.first == "make" else { return nil }
        return words.dropFirst().first { !$0.hasPrefix("-") && !$0.contains("=") }
    }

    /// `s` in single quotes, for zsh.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// The `.command` file's text. It deletes itself first, since it is used
    /// once; the shell already has it open. `rc`, because `status` is read-only
    /// in zsh.
    ///
    /// `exports` carries what the terminal's own shell would not set for a
    /// script: PATH and MRK_ROOT come from .zshrc, which a script never reads.
    static func script(command: String, directory: String, exports: [String: String] = [:]) -> String {
        var lines = [
            "#!/bin/zsh",
            "# Written by Dipstick to run one command in a terminal. It deletes itself.",
            "rm -f -- \"$0\"",
        ]
        for name in exports.keys.sorted() {
            lines.append("export \(name)=\(shellQuote(exports[name]!))")
        }
        lines += [
            "cd -- \(shellQuote(directory)) || exit 1",
            "print -r -- \(shellQuote("$ " + command))",
            command,
            "rc=$?",
            "print",
            "print -r -- \"Dipstick: exited $rc. Refresh Dipstick to see the result.\"",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    static func run(command: String, directory: String, exports: [String: String] = [:]) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dipstick", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent("run-\(UUID().uuidString).command")
        try script(command: command, directory: directory, exports: exports)
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        guard NSWorkspace.shared.open(file) else {
            try? FileManager.default.removeItem(at: file)
            throw CocoaError(.fileReadUnknown, userInfo: [
                NSLocalizedDescriptionKey: "No app opened \(file.lastPathComponent).",
            ])
        }
    }
}
