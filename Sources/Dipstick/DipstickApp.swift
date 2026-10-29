import SwiftUI
import AppKit

let appVersion = "0.6"

// MARK: - Launch

/// Decides, before anything else runs, whether this launch is the app or only
/// a host for tests, as the sibling apps' AppLauncher does.
///
/// `swift test` links this module into the test runner and never calls
/// main(), so today nothing launches the app under a test. The guard came with
/// the first setting Dipstick stores itself, the console's screen colour.
/// AppKit keeps the menu bar icon's position in the same domain,
/// io.github.sevmorris.Dipstick, which snapshot-prefs captures, and a test run
/// must never touch the developer's real ones.
#if !TESTING
@main
#endif
enum AppLauncher {
    static func main() {
        if isHostingTests {
            TestHostApp.main()
        } else {
            DipstickApp.main()
        }
    }

    /// XCTest is already loaded when main() runs in a test host, and is never
    /// linked into the app itself.
    static let isHostingTests =
        NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
}

/// A scene with no window: while the app hosts tests, nothing of the real app
/// is built.
private struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}

extension UserDefaults {
    /// Where Dipstick keeps what it stores in defaults: its own domain, except
    /// under tests and in a --snapshot run, where it is a scratch suite named
    /// by a path in the temporary folder. A path keeps the file out of
    /// ~/Library/Preferences, where snapshot-prefs exports every
    /// io.github.sevmorris.* domain. Nothing in the app names `.standard`; it
    /// goes through here. AppKit's own keys, such as the menu bar icon's
    /// position, go to the real domain whatever this says.
    static let app: UserDefaults = {
        let scratch: String?
        if AppLauncher.isHostingTests {
            scratch = "io.github.sevmorris.Dipstick.tests"
        } else if Snapshot.directory(in: CommandLine.arguments) != nil {
            scratch = "io.github.sevmorris.Dipstick.snapshot"
        } else {
            scratch = nil
        }
        guard let scratch else { return .standard }
        return UserDefaults(suiteName: FileManager.default.temporaryDirectory
            .appendingPathComponent(scratch).path)!
    }()
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The app's one model. It lives here so that Quit can ask it whether a
    /// command is running.
    let model = StatusModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A menu bar app: no Dock icon and no app menu until a window opens
        // (StatusModel.updateDockPresence). The built bundle says so with
        // LSUIElement; this covers `swift run`, which has no bundle.
        NSApp.setActivationPolicy(.accessory)
    }

    /// A command running in the console keeps Dipstick open: quitting would
    /// hang it up half way. The console comes forward to say why. A logout or
    /// a restart waits too.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isConsoleRunning else { return .terminateNow }
        model.showConsole()
        NSSound.beep()
        return .terminateCancel
    }

    /// A click on the Dock icon, which shows while a window is open: with
    /// each one minimized, it brings mrk Settings back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { model.openSettings() }
        return true
    }
}

// MARK: - App

struct DipstickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Before the status item is made, so the snapshot can put the domain
        // back.
        if Snapshot.directory(in: CommandLine.arguments) != nil { Snapshot.saveDomain() }
    }

    var body: some Scene {
        MenuBarExtra {
            StatusView(model: appDelegate.model)
        } label: {
            // The label is on screen from launch, so its task starts the
            // refresh loop before the menu is ever opened.
            Image(systemName: appDelegate.model.symbolName)
                .task {
                    if let dir = Snapshot.directory(in: CommandLine.arguments) {
                        let written = await Snapshot.write(model: appDelegate.model, to: dir)
                        exit(written ? 0 : 1)
                    }
                    appDelegate.model.start()
                }
        }
        .menuBarExtraStyle(.window)
        // The menu bar's menus, which show while a window gives Dipstick a
        // Dock icon.
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await appDelegate.model.checkForUpdates() }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("mrk Settings…") { appDelegate.model.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await appDelegate.model.refreshAll() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
