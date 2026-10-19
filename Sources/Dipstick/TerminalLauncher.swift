import AppKit

/// Runs a command in a terminal window, the way the mrk-status TUI runs a fix:
/// `cd <checkout> && <fix>`, with the terminal attached.
///
/// Most fixes need one. `make sync ARGS=-c` opens the picker, pushall and
/// nuke-mrk ask questions, and sudo asks for a password, so a fix cannot run
/// hidden behind the menu bar. Dipstick writes the command into a `.command`
/// file and opens it, which starts it in whichever terminal opens `.command`
/// files — Terminal unless another app has claimed them. That needs no
/// Automation permission, as scripting Terminal would.
enum TerminalLauncher {
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
