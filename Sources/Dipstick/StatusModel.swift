import AppKit
import Observation

/// What the menu bar shows: the last report, the last failure, and when; and
/// the fix running in the console.
@Observable @MainActor
final class StatusModel {
    typealias EnvironmentProvider = @Sendable () async -> [String: String]

    private(set) var report: StatusReport?
    /// Why the last refresh produced no report. The report before it, if any,
    /// stays on screen under the message.
    private(set) var error: StatusError?
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?
    /// A newer Dipstick, found by the quiet check. The footer offers it.
    private(set) var availableUpdate: AvailableUpdate?
    /// The fix in the console, running or exited, until its window closes.
    private(set) var console: ConsoleSession?

    let home: String
    private var environment: [String: String]?
    private let environmentProvider: EnvironmentProvider
    /// Whether a fix in the console gets a window. A test's model has none,
    /// and reads `console`.
    private let opensWindows: Bool
    @ObservationIgnored private var consoleWindow: ConsoleWindowController?
    /// Set when a fix ends while mrk-status runs. That run read mrk as it
    /// was, so it goes round again.
    @ObservationIgnored private var changedDuringRefresh = false
    private var started = false

    /// mrk-status costs about a second, and nothing it checks changes by the
    /// minute: a fetch, a push, a Time Machine backup. A fix run in the
    /// console runs it again as soon as the fix ends.
    static let interval: Duration = .seconds(30 * 60)
    /// Opening the menu refreshes a report older than this.
    static let staleAfter: TimeInterval = 120
    /// The quiet update check runs at launch and then this often. A menu bar
    /// app runs from login to shutdown, so a check at launch alone could be
    /// weeks old. The schedule lives in this process, and needs no throttle
    /// date in UserDefaults.
    static let updateInterval: Duration = .seconds(24 * 60 * 60)

    /// `environment` is what mrk-status and the console run with: the login
    /// shell's, unless a test gives its own.
    init(home: String = NSHomeDirectory(), opensWindows: Bool = true,
         environment: EnvironmentProvider? = nil) {
        self.home = home
        self.opensWindows = opensWindows
        self.environmentProvider = environment ?? { await Self.loginShellEnvironment(home: home) }
    }

    /// What a terminal window on this Mac has, or Dipstick's own environment
    /// with the usual PATH when the shell cannot be asked.
    nonisolated static func loginShellEnvironment(home: String) async -> [String: String] {
        let own = ProcessInfo.processInfo.environment
        var env = await ShellEnvironment.capture()
            ?? ShellEnvironment.fallback(base: own, home: home)
        // Dipstick's own launch environment can name a test build.
        if let override = own["DIPSTICK_MRK_STATUS"] {
            env["DIPSTICK_MRK_STATUS"] = override
        }
        return env
    }

    /// The checkout mrk-status reports on, and where a fix runs.
    var repoRoot: String {
        if let root = environment?["MRK_ROOT"], !root.isEmpty { return root }
        return home + "/mrk"
    }

    /// The menu bar icon. A report that could not be read is its own state,
    /// apart from a report that says something is wrong.
    var symbolName: String {
        if error != nil, report == nil { return "questionmark.circle" }
        switch report?.severity {
        case nil: return "gauge.with.dots.needle.bottom.50percent"
        case .ok, .info: return "checkmark.circle"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    func start() {
        guard !started else { return }
        started = true
        Task {
            while true {
                await refresh()
                try? await Task.sleep(for: Self.interval)
            }
        }
        Task {
            while true {
                await checkForUpdates(quietly: true)
                try? await Task.sleep(for: Self.updateInterval)
            }
        }
    }

    func refreshIfStale() {
        if let lastRefreshed, Date().timeIntervalSince(lastRefreshed) < Self.staleAfter { return }
        Task { await refresh() }
    }

    /// Runs mrk-status. `reloadEnvironment` asks the shell again, for after an
    /// edit to .zshrc or a fix that changed PATH.
    func refresh(reloadEnvironment: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var reload = reloadEnvironment
        repeat {
            changedDuringRefresh = false
            if environment == nil || reload {
                environment = await environmentProvider()
            }

            switch await StatusRunner.fetch(environment: environment ?? [:], home: home) {
            case .success(let fresh):
                report = fresh
                error = nil
            case .failure(let failure):
                error = failure
            }
            lastRefreshed = Date()
            reload = true
        } while changedDuringRefresh
    }

    /// Runs mrk-status again after a fix, which can change anything it reads,
    /// PATH included. A run already going started before the fix ended, so it
    /// goes round once more instead.
    func refreshAfterFix() async {
        if isRefreshing {
            changedDuringRefresh = true
        } else {
            await refresh(reloadEnvironment: true)
        }
    }

    private func resolvedEnvironment() async -> [String: String] {
        if let environment { return environment }
        let env = await environmentProvider()
        environment = env
        return env
    }

    /// Runs `command` in the checkout, as the TUI's `f` does: in Dipstick's
    /// console, or in a terminal for the few fixes that draw a full screen
    /// (TerminalLauncher.isNeeded). A fix asks first, as `f` does.
    func run(_ command: String, confirm: Bool = true) {
        let inTerminal = TerminalLauncher.isNeeded(for: command)
        NSApp.activate()
        if confirm {
            let alert = NSAlert()
            alert.messageText = inTerminal ? "Run this in a terminal?" : "Run this in Dipstick's console?"
            alert.informativeText = "\(command)\n\nin \(tilde(repoRoot))"
                + (inTerminal ? "\n\nIt draws a full-screen picker, which needs a terminal of its own." : "")
            alert.addButton(withTitle: "Run")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if inTerminal {
            runInTerminal(command)
        } else {
            Task { await runInConsole(command) }
        }
    }

    /// Whether a fix is running in the console. Dipstick does not quit then,
    /// and the fix buttons that would use the console wait.
    var isConsoleRunning: Bool { console?.isRunning == true }

    /// Runs a fix in the console, in the checkout, and runs mrk-status again
    /// once it has exited. One at a time: while one runs, this brings it to
    /// the front instead. One that has exited gives way.
    func runInConsole(_ command: String) async {
        if isConsoleRunning {
            showConsole()
            return
        }
        closeConsole()
        let session = ConsoleSession(command: command)
        console = session
        var window: ConsoleWindowController?
        if opensWindows {
            window = ConsoleWindowController(
                session: session,
                close: { [weak self] in self?.closeConsole() },
                closed: { [weak self, weak session] in
                    if let session { self?.consoleDidClose(session) }
                })
            consoleWindow = window
            window?.show()
        }
        let shell = await resolvedEnvironment()
        await session.run(environment: Self.consoleEnvironment(shell, root: repoRoot), directory: repoRoot)
        window?.commandChanged()
        if case .exited = session.state { await refreshAfterFix() }
    }

    /// Brings the console's window to the front.
    func showConsole() {
        consoleWindow?.show()
    }

    /// Closes the console once its fix has exited.
    func closeConsole() {
        guard let console, !console.isRunning else { return }
        let window = consoleWindow
        consoleWindow = nil
        self.console = nil
        window?.close()
    }

    /// The console's window, for `--snapshot` to draw.
    var consoleWindowForSnapshot: NSWindow? { consoleWindow?.window }

    /// The console's window has gone, by Done or by its close button.
    private func consoleDidClose(_ session: ConsoleSession) {
        guard console === session else { return }
        consoleWindow = nil
        console = nil
    }

    /// The environment of a fix in the console: the login shell's, as a
    /// terminal window has it, on a terminal that draws what TERM=dumb
    /// promises. The .command file exported MRK_ROOT, and so does this.
    /// Gearbox's, with the checkout as a path.
    static func consoleEnvironment(_ shell: [String: String], root: String) -> [String: String] {
        var env = shell
        env["MRK_ROOT"] = root
        env["TERM"] = "dumb"
        // A pager would wait for keys the console does not send.
        env["PAGER"] = "cat"
        env["GIT_PAGER"] = "cat"
        // The terminal's size is the terminal's to say.
        env["COLUMNS"] = nil
        env["LINES"] = nil
        return env
    }

    /// Opens a terminal running `command` in the checkout.
    private func runInTerminal(_ command: String) {
        var exports: [String: String] = [:]
        for name in ["PATH", "MRK_ROOT"] {
            if let value = environment?[name], !value.isEmpty { exports[name] = value }
        }
        do {
            try TerminalLauncher.run(command: command, directory: repoRoot, exports: exports)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    /// Asks GitHub for a newer Dipstick. Check for Updates… says what it found
    /// in an alert. The quiet check at launch and each day after says nothing:
    /// it only sets availableUpdate for the footer, since an alert from a menu
    /// bar app at login would land on top of whatever else was opening.
    func checkForUpdates(quietly: Bool = false) async {
        let result = await UpdateChecker.shared.check()

        switch result {
        case .available(let update):
            availableUpdate = update
        case .upToDate, .needsNewerMacOS:
            availableUpdate = nil
        case .error:
            // A failed check says nothing about what was found before.
            break
        }
        guard !quietly else { return }

        NSApp.activate()
        let alert = NSAlert()
        switch result {
        case .upToDate(let version):
            alert.messageText = "You're up to date"
            alert.informativeText = "Dipstick \(version) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case .available(let update):
            alert.messageText = "Update Available"
            alert.informativeText = "Dipstick \(update.version) is available. You have \(UpdateChecker.installedVersion)."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Release Notes")
            alert.addButton(withTitle: "Not Now")
            switch alert.runModal() {
            case .alertFirstButtonReturn: NSWorkspace.shared.open(update.downloadURL)
            case .alertSecondButtonReturn: NSWorkspace.shared.open(update.releaseURL)
            default: break
            }

        case .needsNewerMacOS(let version, let minimum, let installed):
            alert.messageText = "Dipstick \(version) needs macOS \(minimum)"
            alert.informativeText = "This Mac has macOS \(UpdateChecker.describe(ProcessInfo.processInfo.operatingSystemVersion)), "
                + "so Dipstick \(installed) is the newest version it can run."
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case .error(let message):
            alert.messageText = "Update Check Failed"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func tilde(_ path: String) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
