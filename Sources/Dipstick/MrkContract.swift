import Foundation

/// What the scripts of an mrk checkout take from a program, as the checkout's
/// `scripts/mrk-contract` says it (BIN-1, mrk-contract). MrkRunner reads it
/// once for each checkout, and again when the file changes, and passes an
/// option only when the script takes it. So an exit 2 from a script means
/// only that mrk refuses the command line, and mrk's reason says why
/// (sevmorris/mrk audit 22, O-2). An mrk from before 2026-10-29 has no
/// mrk-contract; for it, MrkRunner reads an exit 2 by its stderr, as
/// `refusesAnOption` does.
///
/// Dipstick reads the options, and the Make targets that need a terminal. The
/// document also names each script's decisions, and the fields and words of
/// its --check lines, which the parsers read by the line contract instead.
struct MrkContract: Decodable, Equatable, Sendable {
    /// The version this build reads. mrk raises it when it deletes an option,
    /// a field or a key, moves a field, or gives a word or a key a new
    /// meaning. A new script, option, field, word, target or key keeps it.
    static let supportedVersion = 1
    /// The command, in the checkout.
    static let script = "scripts/mrk-contract"

    let contract: Int
    /// Each script, by its path in the checkout, such as scripts/sync.
    let scripts: [String: Script]
    /// The Make targets whose scripts can start gum, mrk-picker or mrk-menu,
    /// which draw a full screen (TerminalLauncher). nil when the contract has
    /// no list, as the first one, from sevmorris/mrk#140, has not.
    let terminal: [String]?

    struct Script: Decodable, Equatable, Sendable {
        /// Every option the script takes, each short form apart.
        let options: [String]
        /// The options that also take their value after an equals sign, as
        /// --add=NAME.
        let equals: [String]
    }

    static func decode(_ data: Data) throws -> MrkContract {
        try JSONDecoder().decode(MrkContract.self, from: data)
    }

    /// Whether this mrk is newer than the contract this build reads.
    var isNewer: Bool { contract > Self.supportedVersion }

    /// The options of COMMAND that its script does not take, as the pane
    /// shows them: --add=… for one given after an equals sign. Empty when the
    /// script takes them all, and nil when the contract does not name the
    /// script, so that it says nothing about it.
    func missing(_ command: MrkCommand) -> [String]? {
        guard let script = scripts[command.script] else { return nil }
        return command.options.compactMap { option in
            if option.equals {
                return script.equals.contains(option.name) ? nil : "\(option.name)=…"
            }
            return script.options.contains(option.name) ? nil : option.name
        }
    }
}
