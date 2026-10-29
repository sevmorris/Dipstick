import AppKit

/// Barkeep's Untracked list, which makes the fix for a package that the
/// Brewfile lacks in a window: each package is added, adopted or ignored with
/// mrk's sync, and from Barkeep 1.16.0 committed and pushed. The fix itself,
/// `make sync ARGS=--push`, starts sync's full-screen picker in a terminal.
/// Barkeep 1.17.0 and later open the list from `barkeep://untracked`; with an
/// earlier Barkeep, or none, the fix runs in a terminal as before.
///
/// The link goes to the installed Barkeep by path, not to whichever app
/// LaunchServices picks: a build in Xcode's DerivedData declares the link too,
/// and on 2026-10-29 LaunchServices sent the link to one, which then wrote
/// its window's frames into the real defaults.
enum BarkeepLink {
    static let untracked = URL(string: "barkeep://untracked")!
    static let bundleIdentifier = "io.github.sevmorris.Barkeep"

    /// Whether Barkeep makes COMMAND's fix: `make sync`, by its Make target,
    /// as FixRoute finds the fixes a pane makes.
    static func makes(_ command: String) -> Bool {
        TerminalLauncher.makeTarget(of: command) == "sync"
    }

    /// The first of HANDLERS, the apps that open the link, that is Barkeep
    /// installed in /Applications or in HOME's Applications. Nil when none is.
    static func installedApp(among handlers: [URL], home: String) -> URL? {
        let folders = ["/Applications/", home + "/Applications/"]
        return handlers.first { app in
            let path = app.standardizedFileURL.path
            return folders.contains { path.hasPrefix($0) }
                && Bundle(url: app)?.bundleIdentifier == bundleIdentifier
        }
    }

    /// The installed Barkeep that opens the link, asked of LaunchServices.
    static func installedApp(home: String = NSHomeDirectory()) -> URL? {
        installedApp(among: NSWorkspace.shared.urlsForApplications(toOpen: untracked), home: home)
    }

    /// Opens the Untracked list in APP, Barkeep by its path.
    static func open(in app: URL) {
        NSWorkspace.shared.open([untracked], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
