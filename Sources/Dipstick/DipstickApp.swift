import SwiftUI
import AppKit

let appVersion = "0.2"

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // A menu bar app: no Dock icon and no app menu. The built bundle says
        // so with LSUIElement; this covers `swift run`, which has no bundle.
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - App

/// Dipstick stores no settings of its own, but AppKit keeps the menu bar
/// icon's position in its defaults domain: `NSStatusItem Preferred Position
/// Item-0` in io.github.sevmorris.Dipstick, which snapshot-prefs captures.
/// `swift test` never launches the app or creates the status item, so no test
/// touches that domain, and the sibling apps' AppLauncher guard has nothing to
/// guard here yet. Add it, with their `UserDefaults.app` isolation, alongside
/// the first setting Dipstick stores itself.
#if !TESTING
@main
#endif
struct DipstickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var model = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            StatusView(model: model)
        } label: {
            // The label is on screen from launch, so its task starts the
            // refresh loop before the menu is ever opened.
            Image(systemName: model.symbolName)
                .task {
                    if let path = Snapshot.path(in: CommandLine.arguments) {
                        let written = await Snapshot.write(model: model, to: path)
                        exit(written ? 0 : 1)
                    }
                    model.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
