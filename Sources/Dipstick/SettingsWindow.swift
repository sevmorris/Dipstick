import AppKit
import SwiftUI

/// mrk Settings' window: the four panes over mrk's lists in config/, which
/// were Gearbox's window before Dipstick took them in.
///
/// An AppKit window, as the console's is, rather than a SwiftUI Window
/// scene: a scene's window and its split view write their frames into the
/// app's real defaults domain as the window opens, and snapshot-prefs
/// exports that domain. This one remembers no frame, and opens centred.
/// The hosting controller hands the panes' titles, toolbars and search field
/// to the window, as a scene would. StatusModel gives Dipstick a Dock icon
/// while it is open.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let closed: () -> Void

    /// `closed` is told once the window has gone.
    init(settings: SettingsModel, status: StatusModel, closed: @escaping () -> Void) {
        self.closed = closed
        let host = NSHostingController(rootView: SettingsView(model: settings, status: status)
            .frame(minWidth: 900, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity))
        host.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "mrk Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.contentMinSize = NSSize(width: 900, height: 560)
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        closed()
    }
}
