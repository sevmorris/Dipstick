import AppKit
import SwiftUI

/// `Dipstick --snapshot <file.png>`: one refresh, the window drawn into a PNG,
/// and quit. It runs the path the menu bar runs — the shell's environment,
/// mrk-status, the view — so it checks the window without a click on the menu
/// bar, and it makes the README's picture.
enum Snapshot {
    static func path(in arguments: [String]) -> String? {
        guard let flag = arguments.firstIndex(of: "--snapshot"),
              flag + 1 < arguments.count else { return nil }
        return arguments[flag + 1]
    }

    /// The window's content is drawn by AppKit controls (buttons, disclosure
    /// triangles), which ImageRenderer leaves as placeholders, so the view is
    /// hosted in an off-screen window and cached from there.
    @MainActor
    static func write(model: StatusModel, to path: String) async -> Bool {
        await model.refresh()
        if let error = model.error {
            FileHandle.standardError.write(Data("dipstick: \(error.message)\n".utf8))
        }

        let host = NSHostingView(rootView: StatusView(model: model)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // One pass of the run loop, for SwiftUI to finish its first layout.
        try? await Task.sleep(for: .milliseconds(300))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
