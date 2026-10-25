import AppKit
import SwiftUI

/// `Dipstick --snapshot <directory>`: one refresh, the menu bar window drawn
/// into a PNG, then each pane of mrk Settings, then the console, each into a
/// PNG of its own in the directory, and quit. It runs the path a click runs —
/// the shell's environment, mrk-status, each pane's real check against the
/// checkout — so it checks every window without a click, and it makes the
/// README's pictures.
enum Snapshot {
    static func directory(in arguments: [String]) -> String? {
        guard let flag = arguments.firstIndex(of: "--snapshot"),
              flag + 1 < arguments.count else { return nil }
        return arguments[flag + 1]
    }

    static let statusFileName = "1-status.png"

    static func fileName(_ pane: Pane) -> String {
        "\((Pane.allCases.firstIndex(of: pane) ?? 0) + 2)-\(pane.rawValue).png"
    }

    static var consoleFileName: String { "\(Pane.allCases.count + 2)-console.png" }

    /// What the snapshot's console runs: mrk's list of its Make targets, which
    /// reads the Makefile and changes nothing.
    static let consoleCommand = "make help"

    /// The app's real domain as it was before the status item was made: nil
    /// when there was none. AppKit writes the menu bar icon's position into
    /// it, and snapshot-prefs exports every io.github.sevmorris.* domain. So
    /// the snapshot puts the domain back as it found it.
    nonisolated(unsafe) private static var savedDomain: [String: Any]?
    nonisolated(unsafe) private static var savedDomainTaken = false

    static func saveDomain() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        savedDomain = UserDefaults.standard.persistentDomain(forName: id)
        savedDomainTaken = true
    }

    /// Key by key, through the app's own defaults: a key the run added goes,
    /// and one it changed gets its old value back. setPersistentDomain and
    /// removePersistentDomain leave a window's keys in place.
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
    static func write(model: StatusModel, to directory: String) async -> Bool {
        defer { restoreDomain() }
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(statusFileName).path
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
        window.close()
        let panes = await writeSettings(model: model, to: dir)
        let console = await writeConsole(model: model, to: dir.appendingPathComponent(consoleFileName).path)
        return panes && console
    }

    /// Each pane of mrk Settings in turn, loaded as the window loads it.
    @MainActor
    private static func writeSettings(model: StatusModel, to dir: URL) async -> Bool {
        model.openSettings(.preferences)
        var shown: NSWindow?
        for _ in 0..<50 {
            if let window = model.settingsWindowForSnapshot, window.isVisible {
                shown = window
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let window = shown, let settings = model.settings else {
            say("mrk Settings did not open")
            return false
        }
        clearAutosave(in: window.contentView)
        window.setContentSize(NSSize(width: 1120, height: 720))
        var ok = true
        for pane in Pane.allCases {
            settings.selection = pane
            await settings.load(pane)
            await settle(window)
            let url = dir.appendingPathComponent(fileName(pane))
            if capture(window, to: url) {
                say("wrote \(url.path), \(Int(window.frame.width))×\(Int(window.frame.height)) pt")
            } else {
                say("could not draw \(pane.title)")
                ok = false
            }
        }
        model.closeSettings()
        return ok
    }

    /// A split view with an autosave name keeps its widths in the app's real
    /// domain. The snapshot's sizes are not ones to remember.
    @MainActor
    private static func clearAutosave(in view: NSView?) {
        guard let view else { return }
        if let split = view as? NSSplitView { split.autosaveName = nil }
        view.subviews.forEach(clearAutosave)
    }

    /// The console, last, running make help. Its window is drawn on its own,
    /// title bar and all.
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

    /// SwiftUI lays a window out over more than one pass, so wait until it
    /// has drawn and kept still for 0.5 s. The tube's refresh sweep never
    /// keeps still, so the console's can take the full 8 s.
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
