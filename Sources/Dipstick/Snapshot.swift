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

    /// The picture is of the menu bar window itself: the snapshot clicks the
    /// icon, as a person does, and draws the window that opens. A view hosted
    /// apart from it is laid out differently. v0.1's snapshots hosted
    /// StatusView in an NSHostingView sized by its fittingSize, and showed
    /// every panel, while the menu bar window gave the panels 0 pt.
    @MainActor
    static func write(model: StatusModel, to path: String) async -> Bool {
        await model.refresh()
        if let error = model.error {
            FileHandle.standardError.write(Data("dipstick: \(error.message)\n".utf8))
        }

        guard let window = await openMenuBarWindow(), let view = window.contentView else {
            FileHandle.standardError.write(Data("dipstick: the menu bar window did not open\n".utf8))
            return false
        }
        // SwiftUI sizes the list in a second pass, once it has measured what
        // the list holds, so wait until the window keeps one size for 0.3 s.
        var size = window.frame.size
        var steady = 0
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            steady = window.frame.size == size ? steady + 1 : 0
            size = window.frame.size
            if steady == 3 { break }
        }

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: path))) != nil else { return false }
        FileHandle.standardError.write(Data("dipstick: wrote \(path), \(Int(size.width))×\(Int(size.height)) pt\n".utf8))
        return true
    }

    /// Clicks Dipstick's menu bar icon and returns the window it opens.
    @MainActor
    private static func openMenuBarWindow() async -> NSWindow? {
        guard let button = NSApp.windows.lazy.compactMap({ statusButton(in: $0.contentView) }).first
        else { return nil }
        button.performClick(nil)
        for _ in 0..<30 {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0 !== button.window }) {
                return window
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    @MainActor
    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap { statusButton(in: $0) }.first
    }
}
