import AppKit
import Observation

/// What the menu bar shows: the last report, the last failure, and when.
@Observable @MainActor
final class StatusModel {
    private(set) var report: StatusReport?
    /// Why the last refresh produced no report. The report before it, if any,
    /// stays on screen under the message.
    private(set) var error: StatusError?
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?
    /// A newer Dipstick, found by the quiet check. The footer offers it.
    private(set) var availableUpdate: AvailableUpdate?

    let home: String
    private var environment: [String: String]?
    private var started = false

    /// mrk-status costs about a second, and nothing it checks changes by the
    /// minute: a fetch, a push, a Time Machine backup.
    static let interval: Duration = .seconds(30 * 60)
    /// Opening the menu refreshes a report older than this.
    static let staleAfter: TimeInterval = 120
    /// The quiet update check runs at launch and then this often. A menu bar
    /// app runs from login to shutdown, so a check at launch alone could be
    /// weeks old.
    static let updateInterval: Duration = .seconds(24 * 60 * 60)

    init(home: String = NSHomeDirectory()) {
        self.home = home
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

        if environment == nil || reloadEnvironment {
            let own = ProcessInfo.processInfo.environment
            var env = await ShellEnvironment.capture()
                ?? ShellEnvironment.fallback(base: own, home: home)
            // Dipstick's own launch environment can name a test build.
            if let override = own["DIPSTICK_MRK_STATUS"] {
                env["DIPSTICK_MRK_STATUS"] = override
            }
            environment = env
        }

        switch await StatusRunner.fetch(environment: environment ?? [:], home: home) {
        case .success(let fresh):
            report = fresh
            error = nil
        case .failure(let failure):
            error = failure
        }
        lastRefreshed = Date()
    }

    /// Opens a terminal running `command` in the checkout. A fix asks first,
    /// as the TUI's `f` does.
    func runInTerminal(_ command: String, confirm: Bool = true) {
        NSApp.activate()
        if confirm {
            let alert = NSAlert()
            alert.messageText = "Run this in a terminal?"
            alert.informativeText = "\(command)\n\nin \(tilde(repoRoot))"
            alert.addButton(withTitle: "Run")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

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
