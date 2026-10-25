import AppKit
import SwiftUI

/// The console's window, one for each command run in it.
///
/// It does not close while its command runs, and AppDelegate does not let
/// Dipstick quit then either, as AppKit keeps a window with a sheet open. So
/// nothing short of a force quit hangs a command up half way, between a
/// commit and its push.
///
/// The window remembers no frame. An autosave name would put it in Dipstick's
/// real defaults domain, which snapshot-prefs exports.
@MainActor
final class ConsoleWindowController: NSWindowController, NSWindowDelegate {
    let session: ConsoleSession
    private let closed: () -> Void

    /// `close` is what the console's Done button does. `closed` is told once
    /// the window has gone, by Done or by its close button.
    init(session: ConsoleSession, close: @escaping () -> Void, closed: @escaping () -> Void) {
        self.session = session
        self.closed = closed
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Dipstick"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentView = NSHostingView(rootView: ConsoleWindowView(session: session, close: close))
        window.contentMinSize = NSSize(width: 860, height: 460)
        super.init(window: window)
        window.delegate = self
        window.center()
        commandChanged()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// Brings the console to the front, where typing goes to it. The app
    /// comes forward with it.
    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// The close button works once the command has exited.
    func commandChanged() {
        window?.standardWindowButton(.closeButton)?.isEnabled = !session.isRunning
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard session.isRunning else { return true }
        NSSound.beep()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        closed()
    }
}

/// A word on a coloured capsule: the console's state beside its command, and
/// a key's state in the panes.
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}
