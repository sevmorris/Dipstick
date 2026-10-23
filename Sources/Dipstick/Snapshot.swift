import AppKit
import SwiftUI

/// `Dipstick --snapshot <file.png>`: one refresh, the window drawn into a PNG,
/// then the console drawn into a second PNG beside it, and quit. It runs the
/// path the menu bar runs — the shell's environment, mrk-status, the view — so
/// it checks the window without a click on the menu bar, and it makes the
/// README's picture.
enum Snapshot {
    static func path(in arguments: [String]) -> String? {
        guard let flag = arguments.firstIndex(of: "--snapshot"),
              flag + 1 < arguments.count else { return nil }
        return arguments[flag + 1]
    }

    /// Where the console's picture goes: beside the window's, with
    /// "-console" before the extension.
    static func consolePath(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        return url.deletingPathExtension().path + "-console" + (ext.isEmpty ? "" : "." + ext)
    }

    /// What the snapshot's console runs: mrk's list of its Make targets, which
    /// reads the Makefile and changes nothing.
    static let consoleCommand = "make help"

    /// The app's real domain as it was before the status item was made: nil
    /// when there was none. AppKit writes the menu bar icon's position into
    /// it, and snapshot-prefs exports every io.github.sevmorris.* domain. So
    /// the snapshot puts the domain back as it found it, as Gearbox's does.
    nonisolated(unsafe) private static var savedDomain: [String: Any]?
    nonisolated(unsafe) private static var savedDomainTaken = false

    static func saveDomain() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        savedDomain = UserDefaults.standard.persistentDomain(forName: id)
        savedDomainTaken = true
    }

    /// Key by key, through the app's own defaults: a key the run added goes,
    /// and one it changed gets its old value back. Gearbox found that
    /// setPersistentDomain and removePersistentDomain leave a window's keys in
    /// place.
    static func restoreDomain() {
        guard savedDomainTaken, let id = Bundle.main.bundleIdentifier else { return }
        let before = savedDomain ?? [:]
        let now = UserDefaults.standard.persistentDomain(forName: id) ?? [:]
        for key in now.keys where before[key] == nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, value) in before where !(now[key].map { ($0 as AnyObject).isEqual(value) } ?? false) {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.synchronize()
    }

    /// The picture is of the menu bar window itself: the snapshot clicks the
    /// icon, as a person does, and draws the window that opens. A view hosted
    /// apart from it is laid out differently. v0.1's snapshots hosted
    /// StatusView in an NSHostingView sized by its fittingSize, and showed
    /// every panel, while the menu bar window gave the panels 0 pt.
    @MainActor
    static func write(model: StatusModel, to path: String) async -> Bool {
        defer { restoreDomain() }
        await model.refresh()
        if let error = model.error {
            say(error.message)
        }

        guard let window = await openMenuBarWindow(), let view = window.contentView else {
            say("the menu bar window did not open")
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
        say("wrote \(path), \(Int(size.width))×\(Int(size.height)) pt")
        return await writeConsole(model: model, to: consolePath(for: path))
    }

    /// The console, after the menu bar window, running make help. Its window
    /// is drawn on its own, title bar and all.
    @MainActor
    private static func writeConsole(model: StatusModel, to path: String) async -> Bool {
        Task { await model.runInConsole(consoleCommand) }
        var shown: NSWindow?
        for _ in 0..<300 {
            if let window = model.consoleWindowForSnapshot, model.console?.isRunning == false {
                shown = window
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let window = shown else {
            say("the console did not finish \(consoleCommand) in 30 s")
            return false
        }
        await settle(window)
        let drawn = capture(window, to: URL(fileURLWithPath: path))
        say(drawn ? "wrote \(path), \(Int(window.frame.width))×\(Int(window.frame.height)) pt"
                  : "could not draw the console")
        model.closeConsole()
        return drawn
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

    /// Gearbox's: SwiftUI lays a window out over more than one pass, so wait
    /// until it has drawn and kept still for 0.5 s. The tube's refresh sweep
    /// never keeps still, so this can take its full 8 s.
    @MainActor
    private static func settle(_ window: NSWindow) async {
        try? await Task.sleep(for: .milliseconds(600))
        var last = render(window)?.tiffRepresentation
        var steady = 0
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(250))
            let now = render(window)?.tiffRepresentation
            steady = now == last ? steady + 1 : 0
            last = now
            if steady == 2 { return }
        }
    }

    /// The whole window, title bar included: the view that holds the content
    /// view and the title bar.
    @MainActor
    private static func render(_ window: NSWindow) -> NSBitmapImageRep? {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    @MainActor
    private static func capture(_ window: NSWindow, to url: URL) -> Bool {
        guard let rep = render(window), let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? png.write(to: url)) != nil
    }

    private static func say(_ text: String) {
        FileHandle.standardError.write(Data("dipstick: \(text)\n".utf8))
    }
}
