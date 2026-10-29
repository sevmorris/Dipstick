import Foundation

// mrk Settings, Dipstick's window, is a window over mrk's own scripts. It
// reads the lists in config/ and asks the scripts' check modes what they
// find, and every decision goes back through a script's own flag:
// sync-login-items --add, --remove and --ignore, and defaults.sh --skip,
// --unskip, --key and --revert. The one file it writes itself is
// config/dock.txt, the plain list dock-setup reads, as Barkeep writes
// tools/picker/descriptions.tsv. What changes the Mac (make defaults, make
// dock) or commits and pushes (make snapshot-prefs) runs in Dipstick's
// console, on a terminal of its own, with its own prompts and output in view.
// Dipstick never commits by itself: mrk-push and pushall do that, with their
// secret scan and gates, and the Unrecorded panel shows what is waiting.
// This was Gearbox, a window app of its own, until Dipstick took it in.

/// An mrk checkout: ~/mrk, or the one MRK_ROOT names, as mrk-status reads it.
struct MrkCheckout: Equatable, Sendable {
    let root: URL

    static func resolve(environment: [String: String], home: String) -> MrkCheckout {
        if let root = environment["MRK_ROOT"], !root.isEmpty {
            return MrkCheckout(root: URL(fileURLWithPath: root, isDirectory: true))
        }
        return MrkCheckout(root: URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("mrk", isDirectory: true))
    }

    func file(_ path: String) -> URL { root.appendingPathComponent(path) }

    var defaultsTable: URL        { file("config/defaults.tsv") }
    var defaultsDescriptions: URL { file("docs/defaults/descriptions.tsv") }
    var defaultsSkip: URL         { file("config/defaults-skip.tsv") }
    var appPrefs: URL             { file("config/app-prefs.tsv") }
    var loginItems: URL           { file("config/login-items.txt") }
    var dockList: URL             { file("config/dock.txt") }

    /// The scripts the panes run. A checkout without them is too old for
    /// Dipstick, or no checkout at all.
    static let scripts = ["scripts/snapshot-prefs", "scripts/defaults.sh",
                          "scripts/sync-login-items", "scripts/dock-setup"]

    /// The first script the panes run and cannot find, or nil. A file a pane
    /// reads is that pane's concern: an mrk older than Dipstick lacks some,
    /// and the other panes still work.
    func missing(fileManager: FileManager = .default) -> String? {
        Self.scripts.first { !fileManager.isExecutableFile(atPath: file($0).path) }
    }
}

/// One run of one of mrk's scripts, in the checkout, that changes nothing but
/// what its flag asks for. Each is a check mode or a decision documented in
/// BIN-1 (docs/bin/mrk-usage.html).
enum MrkCommand: Equatable, Sendable {
    /// The commit a snapshot would make: FILE, KEY, added|deleted|changed.
    case prefsCheck
    /// Each key of config/defaults.tsv against this Mac.
    case defaultsCheck(withTrackpad: Bool)
    /// Turn keys off: list them in config/defaults-skip.tsv, so make defaults
    /// passes them over, and put back the value each had before mrk wrote it.
    case defaultsOff([DefaultsKey])
    /// Turn keys on: take them out of config/defaults-skip.tsv, and write
    /// mrk's value.
    case defaultsOn([DefaultsKey])
    /// Write mrk's value of keys that are on.
    case defaultsApply([DefaultsKey])
    /// The login items an interactive run would offer.
    case loginItemsCheck
    /// Track a login item in config/login-items.txt.
    case loginItemsAdd(String)
    /// Add a login item to ~/.mrk/login-items-ignore.
    case loginItemsIgnore(String)
    /// Stop tracking an app in config/login-items.txt.
    case loginItemsRemove(String)
    /// Each item of config/dock.txt: app or folder, line, path, state, and
    /// whether it is docked; then each unlisted item the Dock has.
    case dockCheck

    var script: String {
        switch self {
        case .prefsCheck: return "scripts/snapshot-prefs"
        case .defaultsCheck, .defaultsOff, .defaultsOn, .defaultsApply: return "scripts/defaults.sh"
        case .loginItemsCheck, .loginItemsAdd, .loginItemsIgnore, .loginItemsRemove:
            return "scripts/sync-login-items"
        case .dockCheck: return "scripts/dock-setup"
        }
    }

    var arguments: [String] {
        switch self {
        case .prefsCheck: return ["--check"]
        case .defaultsCheck(let trackpad): return trackpad ? ["--check", "--with-trackpad"] : ["--check"]
        case .defaultsOff(let keys): return keys.flatMap { ["--skip", $0.domain, $0.key, "--revert", $0.domain, $0.key] }
        case .defaultsOn(let keys): return keys.flatMap { ["--unskip", $0.domain, $0.key, "--key", $0.domain, $0.key] }
        case .defaultsApply(let keys): return keys.flatMap { ["--key", $0.domain, $0.key] }
        case .loginItemsCheck: return ["--check"]
        case .loginItemsAdd(let name): return Self.decision("--add", name)
        case .loginItemsIgnore(let name): return Self.decision("--ignore", name)
        case .loginItemsRemove(let name): return Self.decision("--remove", name)
        case .dockCheck: return ["--check"]
        }
    }

    /// A login item decision: the option and the name as two arguments, or as
    /// OPTION=NAME for a name that starts with a dash, which sync-login-items
    /// would otherwise take for an option. That form came with mrk from
    /// 2026-10-28 (sevmorris/mrk#135); an older mrk says it does not know it,
    /// and the pane says to run make pull.
    private static func decision(_ option: String, _ name: String) -> [String] {
        name.hasPrefix("-") ? ["\(option)=\(name)"] : [option, name]
    }

    /// The command as a pane shows it.
    var displayLine: String {
        "$ " + ([script] + arguments.map { $0.contains(" ") ? "\"\($0)\"" : $0 }).joined(separator: " ")
    }

    /// snapshot-prefs --check exports every app into a scratch clone, about
    /// 4 s on this Mac; the others answer in under a second.
    var timeout: Duration { self == .prefsCheck ? .seconds(180) : .seconds(60) }
}

/// What a pane runs in Dipstick's console, on a terminal: the commands that
/// change the Mac, or that commit and push, so their prompts and their output
/// stay in view. The console runs each as a fix from the menu bar runs,
/// `make <target>` under zsh in the checkout, with the login shell's
/// environment.
enum TerminalCommand: Equatable, Sendable {
    case snapshotPrefs
    case applyDefaults(withTrackpad: Bool)
    case applyDock

    var command: String {
        switch self {
        case .snapshotPrefs: return "make snapshot-prefs"
        case .applyDefaults(let trackpad): return trackpad ? "make trackpad" : "make defaults"
        case .applyDock: return "make dock"
        }
    }

    /// The pane that reads mrk again when the command has exited.
    var pane: Pane {
        switch self {
        case .snapshotPrefs: return .preferences
        case .applyDefaults: return .defaults
        case .applyDock: return .dock
        }
    }
}

enum MrkError: LocalizedError, Equatable {
    case failed(command: String, status: Int32, message: String)
    case timedOut(command: String)
    case notStarted(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case .failed(let command, let status, let message):
            return message.isEmpty ? "\(command) exited with status \(status)." : message
        case .timedOut(let command):
            return "\(command) did not finish, and Dipstick stopped it."
        case .notStarted(let command, let message):
            return "\(command) could not start: \(message)"
        }
    }

    var status: Int32? {
        if case .failed(_, let status, _) = self { return status }
        return nil
    }
}

/// Runs mrk's scripts with the environment of an interactive login zsh, asked
/// for once and kept, in the checkout. In the app the environment is
/// StatusModel's, the one mrk-status and the console run with.
actor MrkRunner {
    typealias EnvironmentProvider = @Sendable () async -> [String: String]

    private let environmentProvider: EnvironmentProvider
    private var environment: [String: String]?

    init(environment: @escaping EnvironmentProvider) {
        self.environmentProvider = environment
    }

    func resolvedEnvironment() async -> [String: String] {
        if let environment { return environment }
        let env = await environmentProvider()
        environment = env
        return env
    }

    /// Asks for the environment again at the next run: a fix can change
    /// PATH, and StatusModel asks the shell again after one.
    func forgetEnvironment() {
        environment = nil
    }

    /// Runs the command in the checkout and returns its stdout. Throws when
    /// it exits non-zero, with the last line it wrote to stderr — where mrk's
    /// scripts say why they refused.
    func run(_ command: MrkCommand, in checkout: MrkCheckout) async throws -> ProcessResult {
        let env = await resolvedEnvironment()
        let result: ProcessResult
        do {
            result = try await Subprocess.run(
                checkout.file(command.script),
                arguments: command.arguments,
                environment: env,
                currentDirectory: checkout.root,
                timeout: command.timeout)
        } catch {
            throw MrkError.notStarted(command: command.script, message: error.localizedDescription)
        }
        if result.timedOut { throw MrkError.timedOut(command: command.displayLine) }
        guard result.status == 0 else {
            // Each script exits 2 for a command line it refuses. When it names
            // an option it does not know, the mrk is from before that option,
            // since Dipstick passes only documented ones. Any other exit 2 is a
            // value mrk refuses, such as a login item's name, and mrk's own
            // reason says more than "run make pull" (sevmorris/mrk audit 22,
            // Z-3).
            let message = result.status == 2 && Self.refusesAnOption(result.stderrText)
                ? "\(command.script) does not take \(command.arguments.joined(separator: " ")): this mrk is older than Dipstick. Run make pull in \(checkout.root.path)."
                : Self.reason(in: result.stderrText)
            throw MrkError.failed(command: command.displayLine, status: result.status, message: message)
        }
        return result
    }

    /// Whether a script's stderr says it does not know an option: mrk's
    /// "unknown argument: X", and sync-login-items' "Unknown option: X".
    static func refusesAnOption(_ stderr: String) -> Bool {
        let text = stderr.lowercased()
        return text.contains("unknown argument") || text.contains("unknown option")
    }

    /// Why a script refused: the last line lib.sh's err marked ✗, which comes
    /// before the hints that info adds below it, or else the last line.
    static func reason(in stderr: String) -> String {
        let plain = stderr.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        if let marked = plain.split(separator: "\n").last(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("✗ ")
        }) {
            return lastLine(of: String(marked))
        }
        return lastLine(of: stderr)
    }

    /// The last line with text in it, with mrk's ✗/⚠ marks and colour codes
    /// taken off.
    static func lastLine(of text: String) -> String {
        let plain = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        let line = plain.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        for mark in ["✗ ", "⚠ ", "✓ ", "▸ ", "· "] where trimmed.hasPrefix(mark) {
            trimmed.removeFirst(mark.count)
        }
        return trimmed
    }
}
