import Foundation

/// The fixes a pane of mrk Settings makes in their place: the fix's Run
/// button opens the pane, which shows what the fix would change and runs
/// nothing until asked.
///
/// Each is found by its Make target (`makeTarget`), so mrk-status needs no
/// word of its own for it.
///
/// - `make snapshot-prefs`: App Preferences shows the commit a snapshot would
///   make, and its Snapshot… button runs the same target in the console.
/// - `make sync-login-items ARGS=-c`: Login Items makes the same decisions
///   with sync-login-items' --add, --ignore and --remove, one item at a time,
///   where the fix asks with gum's picker. The pane never commits: the
///   Unrecorded panel then offers mrk-push.
/// - `make defaults` and `make trackpad`: macOS Defaults shows each key that
///   differs, and its Apply button runs the same target in the console.
/// - `make dock`: Dock shows each item, and its Apply button runs make dock.
struct FixRoute: Equatable, Sendable {
    let pane: Pane
    /// make trackpad's: the Defaults pane checks the trackpad's keys too.
    var withTrackpad = false

    static func route(for command: String) -> FixRoute? {
        switch makeTarget(of: command) {
        case "snapshot-prefs": return FixRoute(pane: .preferences)
        case "sync-login-items": return FixRoute(pane: .loginItems)
        case "defaults": return FixRoute(pane: .defaults)
        case "trackpad": return FixRoute(pane: .defaults, withTrackpad: true)
        case "dock": return FixRoute(pane: .dock)
        default: return nil
        }
    }

    /// The Make target `command` runs, or nil when it is not `make`. make's
    /// target is its first word that is neither an option nor a variable:
    /// `make sync ARGS=-c`.
    static func makeTarget(of command: String) -> String? {
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.first == "make" else { return nil }
        return words.dropFirst().first { !$0.hasPrefix("-") && !$0.contains("=") }
    }
}
