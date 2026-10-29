import AppKit
import Observation

/// What the menu bar shows: the last report, the last failure, and when; the
/// command running in the console; and mrk Settings, the window over mrk's
/// lists, once it has been opened.
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
    /// The command in the console, running or exited, until its window closes.
    private(set) var console: ConsoleSession?
    /// mrk Settings' model: made the first time the window opens, and kept,
    /// so each pane keeps what it read.
    private(set) var settings: SettingsModel?
    /// The Make targets whose fixes run in a terminal, as the checkout's
    /// mrk-contract names them, read at each refresh (TerminalLauncher).
    private(set) var terminalTargets = TerminalLauncher.fullScreenTargets
    /// Runs mrk's scripts for mrk Settings, and keeps each checkout's
    /// contract, which the refresh reads too.
    @ObservationIgnored private(set) lazy var runner = MrkRunner(environment: { [weak self] in
        await self?.resolvedEnvironment() ?? [:]
    })

    let home: String
    private var environment: [String: String]?
    private let environmentProvider: EnvironmentProvider
    /// Whether a fix in the console gets a window. A test's model has none,
    /// and reads `console`.
    private let opensWindows: Bool
    @ObservationIgnored private var consoleWindow: ConsoleWindowController?
    @ObservationIgnored private var settingsWindow: SettingsWindowController?
    /// Where the settings window keeps what it stores: the app's own store,
    /// unless a test gives its own.
    private let settingsStore: UserDefaults
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
         environment: EnvironmentProvider? = nil, settingsStore: UserDefaults = .app) {
        self.home = home
        self.opensWindows = opensWindows
        self.settingsStore = settingsStore
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

    /// The checkout mrk-status reports on, where a fix runs, and the one mrk
    /// Settings reads: MRK_ROOT as the login shell sets it, or ~/mrk.
    var checkout: MrkCheckout { .resolve(environment: environment ?? [:], home: home) }

    var repoRoot: String { checkout.root.path }

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
                await runner.forgetEnvironment()
            }
            // Before the report, so its fix buttons show where they run. A
            // make pull that changes mrk-contract changes the targets.
            terminalTargets = TerminalLauncher.targets(in: await runner.contract(for: checkout))

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

    func resolvedEnvironment() async -> [String: String] {
        if let environment { return environment }
        let env = await environmentProvider()
        environment = env
        return env
    }

    /// Whether `command` draws a full screen, and so runs in a terminal and
    /// not in the console: TerminalLauncher.isNeeded, with the checkout's
    /// targets.
    func needsTerminal(_ command: String) -> Bool {
        TerminalLauncher.isNeeded(for: command, targets: terminalTargets)
    }

    /// Runs `command` in the checkout, as the TUI's `f` does: in Dipstick's
    /// console, or in a terminal for the few fixes that draw a full screen
    /// (`needsTerminal`). A fix asks first, as `f` does. A fix that a pane of
    /// mrk Settings makes instead (FixRoute) opens that pane: it shows what
    /// the fix would change, and runs nothing until asked.
    func run(_ command: String, confirm: Bool = true) {
        if let route = FixRoute.route(for: command) {
            openSettings(route.pane, withTrackpad: route.withTrackpad)
            return
        }
        let inTerminal = needsTerminal(command)
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

    /// Whether a command is running in the console. Dipstick does not quit
    /// then, and the fix buttons that would use the console wait, as do the
    /// panes of mrk Settings.
    var isConsoleRunning: Bool { console?.isRunning == true }

    /// Whether a fix that runs in the console must wait: one is running
    /// there, or a pane is running one of its decisions.
    var isBusy: Bool { isConsoleRunning || settings?.isDeciding == true }

    /// Runs a command in the console, in the checkout, and runs mrk-status
    /// again once it has exited, after reading `pane` again when a pane
    /// started it. One at a time: while one runs, this brings it to the front
    /// instead. One that has exited gives way.
    func runInConsole(_ command: String, pane: Pane? = nil) async {
        if isConsoleRunning {
            showConsole()
            return
        }
        closeConsole()
        let session = ConsoleSession(command: command, pane: pane)
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
            updateDockPresence()
        }
        let shell = await resolvedEnvironment()
        await session.run(environment: Self.consoleEnvironment(shell, root: repoRoot), directory: repoRoot)
        window?.commandChanged()
        guard case .exited = session.state else { return }
        // A command can change what any pane shows, so the pane on screen
        // reads mrk again too.
        if let settings, let shown = pane ?? (settingsWindow != nil ? settings.selection : nil) {
            await settings.load(shown)
        }
        await refreshAfterFix()
    }

    /// A pane changed mrk: a switch, a login item decision, or an edit of
    /// config/dock.txt. mrk-status reads it again.
    func mrkChanged() {
        Task { await refreshAfterFix() }
    }

    /// Brings the console's window to the front.
    func showConsole() {
        consoleWindow?.show()
    }

    /// Closes the console once its command has exited.
    func closeConsole() {
        guard let console, !console.isRunning else { return }
        let window = consoleWindow
        consoleWindow = nil
        self.console = nil
        window?.close()
        updateDockPresence()
    }

    /// The console's window, for `--snapshot` to draw.
    var consoleWindowForSnapshot: NSWindow? { consoleWindow?.window }

    /// The console's window has gone, by Done or by its close button.
    private func consoleDidClose(_ session: ConsoleSession) {
        guard console === session else { return }
        consoleWindow = nil
        console = nil
        updateDockPresence()
    }

    // MARK: - mrk Settings

    /// mrk Settings' model, made the first time it is asked for, over the
    /// checkout the login shell names. Its scripts run with this model's
    /// environment, and its console commands run in this model's console.
    func settingsModel() async -> SettingsModel {
        if let settings { return settings }
        _ = await resolvedEnvironment()
        // Asked again: another call can have made it while the shell answered.
        if let settings { return settings }
        let made = SettingsModel(checkout: checkout, runner: runner, store: settingsStore, home: home)
        made.host = self
        settings = made
        return made
    }

    /// Opens mrk Settings, at `pane` when given, and reads the pane it shows:
    /// what a pane read when it was last open can be old. `withTrackpad`
    /// turns the Defaults pane's trackpad keys on, for make trackpad's fix.
    /// The task ends once the pane has read mrk.
    @discardableResult
    func openSettings(_ pane: Pane? = nil, withTrackpad: Bool = false) -> Task<Void, Never> {
        Task {
            let settings = await settingsModel()
            if let pane { settings.selection = pane }
            if withTrackpad { settings.defaults.withTrackpad = true }
            if opensWindows { showSettingsWindow(settings) }
            await settings.load(settings.selection ?? .preferences)
        }
    }

    private func showSettingsWindow(_ settings: SettingsModel) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: settings, status: self,
                closed: { [weak self] in self?.settingsDidClose() })
        }
        settingsWindow?.show()
        updateDockPresence()
    }

    /// mrk Settings' window, for `--snapshot` to draw.
    var settingsWindowForSnapshot: NSWindow? { settingsWindow?.window }

    func closeSettings() {
        settingsWindow?.close()
    }

    private func settingsDidClose() {
        settingsWindow = nil
        updateDockPresence()
    }

    /// Refresh, from the menu bar's menu: mrk-status, and the pane mrk
    /// Settings shows.
    func refreshAll() async {
        if let settings, settingsWindow != nil {
            await settings.load(settings.selection ?? .preferences)
        }
        await refresh(reloadEnvironment: true)
    }

    /// Dipstick has a Dock icon while it has a window open, mrk Settings or
    /// the console, and none when only its menu bar icon is left. A window
    /// with no Dock icon is lost behind another app's, and the app menu, with
    /// Check for Updates… and Refresh, shows only for an app in the Dock.
    private func updateDockPresence() {
        guard opensWindows else { return }
        let policy: NSApplication.ActivationPolicy =
            settingsWindow != nil || consoleWindow != nil ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { NSApp.activate() }
    }

    /// The environment of a command in the console: the login shell's, as a
    /// terminal window has it, on a terminal that draws what TERM=dumb
    /// promises. The .command file exported MRK_ROOT, and so does this.
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
