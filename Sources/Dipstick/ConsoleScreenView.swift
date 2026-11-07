import AppKit
import SwiftUI

// The console's screen, and the keys typed at it. The window around it is
// ConsoleView.swift, and the session that runs the command is Console.swift.

/// The console's screen: the text the terminal holds, in a text view inside
/// the tube's clip, as MBM's log sits in its own. The saved lines come first,
/// then the terminal's rows, one line of text each: the text view is as wide
/// as the terminal's columns, so a row never wraps, and as tall as its rows.
struct ConsoleScreenView: NSViewRepresentable {
    let screen: TerminalScreen
    let style: PhosphorStyle
    /// The command is running, so keys go to it and the cursor shows.
    let accepting: Bool
    let onType: ([UInt8]) -> Void
    /// Told the screen's size in characters, whenever it changes.
    let onResize: (_ columns: Int, _ rows: Int) -> Void

    func makeNSView(context: Context) -> TubeClipView {
        let scrollView = ConsoleScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // The stock scroller is a bright grey strip, and on a dark tube that
        // is the first thing your eye finds. Someone who has asked macOS to
        // always show scrollbars means it, so the scroller is drawn to match
        // the phosphor instead.
        scrollView.verticalScroller = PhosphorScroller()

        let textView = ConsoleTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = PhosphorType.bodyFont
        textView.defaultParagraphStyle = ConsoleMetrics.paragraph
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        // A saved line from when the screen was wider wraps where a terminal
        // would, at the last column, not at a space.
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.textContainerInset = ConsoleMetrics.inset
        scrollView.documentView = textView

        let coordinator = context.coordinator
        scrollView.onTile = { [weak scrollView, weak textView] in
            // Not before the view is in a window: a screen made again lays
            // itself out at zero size first, and a resize to that would cut
            // every row on the screen and tell the program it has none.
            guard let scrollView, let textView, scrollView.window != nil else { return }
            let padding = textView.textContainer?.lineFragmentPadding ?? 0
            // A scroller that always shows takes its width whether or not it
            // shows yet, so the columns do not change when the output first
            // runs past the bottom.
            var room = scrollView.frame.size
            if scrollView.scrollerStyle == .legacy {
                room.width -= NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            }
            guard let size = ConsoleMetrics.cells(in: room, padding: padding),
                  size != coordinator.reportedSize else { return }
            coordinator.reportedSize = size
            // Not during AppKit's layout: the session's change updates
            // SwiftUI's views.
            DispatchQueue.main.async { coordinator.onResize?(size.columns, size.rows) }
        }

        let clip = TubeClipView()
        clip.addSubview(scrollView)
        // The frame is set in TubeClipView.layout(); autoresizing would fight it.
        scrollView.autoresizingMask = []
        return clip
    }

    /// What the text view holds, so an update can append only the lines
    /// saved since the last and replace only the rows.
    final class Coordinator {
        var revision = -1
        var style: PhosphorStyle?
        var alternate = false
        /// How many of the screen's saved lines the text view holds.
        var savedCount = 0
        /// Their length, in UTF-16 units: where the rows begin.
        var savedLength = 0
        /// Where the terminal's cursor is in the text, or nil when hidden.
        var cursorLocation: Int?
        var reportedSize: ConsoleMetrics.Size?
        var onResize: ((Int, Int) -> Void)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ clip: TubeClipView, context: Context) {
        guard let scrollView = clip.subviews.first as? NSScrollView,
              let textView = scrollView.documentView as? ConsoleTextView,
              let storage = textView.textStorage else { return }
        let drawn = context.coordinator
        drawn.onResize = onResize
        let styleChanged = drawn.style != style

        if styleChanged || drawn.revision != screen.revision {
            let wasAtBottom = Self.isNearBottom(scrollView)
            let painter = ConsolePainter(style: style)
            let display = screen.display
            let alternate = screen.usesAlternateScreen
            // A new style redraws everything, and so does a switch of screen:
            // the alternate screen shows its rows alone, as a terminal does.
            // Otherwise only the lines saved since the last update, and the
            // rows, which the program can have rewritten anywhere.
            let rebuild = styleChanged || alternate != drawn.alternate || screen.scrollback.count < drawn.savedCount
            let start = rebuild ? 0 : drawn.savedLength
            var savedCount = rebuild ? 0 : drawn.savedCount
            let tail = NSMutableAttributedString()
            if !alternate {
                for line in screen.scrollback[savedCount...] {
                    tail.append(painter.text(line))
                    tail.append(painter.newline)
                }
                savedCount = screen.scrollback.count
            }
            let savedLength = start + tail.length
            var rowStarts: [Int] = []
            rowStarts.reserveCapacity(display.rows.count)
            for (index, row) in display.rows.enumerated() {
                if index > 0 { tail.append(painter.newline) }
                rowStarts.append(start + tail.length)
                tail.append(painter.text(row))
            }

            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: start, length: storage.length - start), with: tail)
            storage.endEditing()
            drawn.savedCount = savedCount
            drawn.savedLength = savedLength
            drawn.alternate = alternate
            drawn.cursorLocation = display.cursor.map { rowStarts[$0.row] + $0.offset }
            drawn.revision = screen.revision

            if styleChanged {
                textView.selectedTextAttributes = painter.selection
                textView.cursorColor = painter.cursor
                if let scroller = scrollView.verticalScroller as? PhosphorScroller {
                    scroller.tint = style == .plain ? nil : NSColor(style.tint)
                    scroller.needsDisplay = true
                }
                drawn.style = style
            }
            textView.sizeToFit()
            if wasAtBottom || alternate { textView.scrollToEndOfDocument(nil) }
            clip.refreshEdgeFade()
        }

        textView.onType = accepting ? onType : nil
        textView.keyModes = ConsoleKeys.Modes(applicationCursor: screen.applicationCursorKeys,
                                              fullScreen: screen.usesAlternateScreen,
                                              bracketedPaste: screen.bracketedPaste)
        textView.cursorLocation = accepting ? drawn.cursorLocation : nil
    }

    private static func isNearBottom(_ scrollView: NSScrollView) -> Bool {
        let contentHeight = scrollView.documentView?.frame.height ?? 0
        return contentHeight - scrollView.contentView.bounds.maxY < 40
    }
}

/// The scroll view says when it has laid itself out, which is when the
/// screen's size in characters can have changed.
final class ConsoleScrollView: NSScrollView {
    var onTile: (() -> Void)?

    override func tile() {
        super.tile()
        onTile?()
    }
}

/// The console's character cell: SF Mono's advance, and a line height every
/// line keeps, whatever font a character falls back to. A row that a box
/// drawing or an emoji made taller would push the rows under it down, and
/// the bottom row off the screen.
enum ConsoleMetrics {
    struct Size: Equatable {
        var columns: Int
        var rows: Int
    }

    static let inset = NSSize(width: 10, height: 8)
    static let advance: CGFloat = ("M" as NSString).size(withAttributes: [.font: PhosphorType.bodyFont]).width
    static let lineHeight: CGFloat = NSLayoutManager().defaultLineHeight(for: PhosphorType.bodyFont)

    static let paragraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }()

    /// The characters that fit in a scroll view's content of `size`, inside
    /// the text view's inset and the line's own `padding` at each end; nil
    /// for a size that holds fewer than 2 × 2, which is a view not laid out
    /// yet, never a console: its window is at least 920 × 600.
    static func cells(in size: NSSize, padding: CGFloat = 5) -> Size? {
        let width = size.width - 2 * inset.width - 2 * padding
        let height = size.height - 2 * inset.height
        let columns = Int((width / advance).rounded(.down))
        let rows = Int((height / lineHeight).rounded(.down))
        guard columns >= 2, rows >= 2 else { return nil }
        return Size(columns: columns, rows: rows)
    }
}

/// The text attributes for each style a program sets, on one screen.
final class ConsolePainter {
    let style: PhosphorStyle
    private var cache: [TerminalScreen.Style: [NSAttributedString.Key: Any]] = [:]
    private var fallbacks: [Unicode.Scalar: Fallback?] = [:]

    init(style: PhosphorStyle) {
        self.style = style
    }

    var newline: NSAttributedString {
        NSAttributedString(string: "\n", attributes: attributes(TerminalScreen.Style()))
    }

    /// The colours the terminal reports when a program asks (OSC 10 and
    /// 11): the phosphor and its unlit glass, or the text and the page.
    var reportedColors: (foreground: TerminalScreen.RGB, background: TerminalScreen.RGB) {
        var colors = (foreground: TerminalScreen.RGB(red: 0xCC, green: 0xCC, blue: 0xCC),
                      background: TerminalScreen.RGB(red: 0, green: 0, blue: 0))
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            colors = (Self.rgb(NSColor(style.tint)), Self.rgb(NSColor(style.ground)))
        }
        return colors
    }

    private static func rgb(_ color: NSColor) -> TerminalScreen.RGB {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        func byte(_ value: CGFloat) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }
        return TerminalScreen.RGB(red: byte(srgb.redComponent), green: byte(srgb.greenComponent),
                                  blue: byte(srgb.blueComponent))
    }

    var selection: [NSAttributedString.Key: Any] {
        style == .plain ? [.backgroundColor: NSColor.selectedTextBackgroundColor]
            : [.backgroundColor: NSColor(style.tint).withAlphaComponent(0.28)]
    }

    var cursor: NSColor {
        style == .plain ? .textColor : NSColor(style.tint)
    }

    func text(_ runs: [TerminalScreen.Run]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for run in runs {
            let attributes = attributes(run.style)
            var plain = ""
            for scalar in run.text.unicodeScalars {
                guard let fallback = fallback(for: scalar) else {
                    plain.unicodeScalars.append(scalar)
                    continue
                }
                text.append(NSAttributedString(string: plain, attributes: attributes))
                plain = ""
                var marked = attributes
                marked[.font] = run.style.bold ? fallback.bold : fallback.regular
                let kern = run.style.bold ? fallback.boldKern : fallback.kern
                if abs(kern) > 0.01 { marked[.kern] = kern }
                text.append(NSAttributedString(string: String(scalar), attributes: marked))
            }
            text.append(NSAttributedString(string: plain, attributes: attributes))
        }
        return text
    }

    /// The font for a character SF Mono lacks, and the kern that makes it
    /// take its cells, so a row lines up with the rows under it. Menlo, when
    /// it has the character: mrk's ⚠, and ✔. TextKit's own fallback finds
    /// those in Apple Color Emoji, a picture no tint reaches, and a cascade
    /// list on the font does not change its mind (tried on 2026-10-22).
    /// Otherwise the font CoreText falls back to. Menlo is 9.03 pt wide to
    /// SF Mono's 9.27, so each ⚠ moved the rest of its row left until it was
    /// kerned (found on mrk-status's warning rows on 2026-11-06).
    private func fallback(for scalar: Unicode.Scalar) -> Fallback? {
        guard scalar.value > 0x7F else { return nil }
        if let known = fallbacks[scalar] { return known }
        let made = Self.makeFallback(scalar)
        fallbacks[scalar] = made
        return made
    }

    private struct Fallback {
        let regular: NSFont
        let bold: NSFont
        let kern: CGFloat
        let boldKern: CGFloat
    }

    private static func makeFallback(_ scalar: Unicode.Scalar) -> Fallback? {
        let string = String(scalar)
        let units = Array(string.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        if CTFontGetGlyphsForCharacters(PhosphorType.bodyFont, units, &glyphs, units.count) { return nil }
        // A combining mark has no cell of its own to fill.
        let cells = TerminalScreen.width(of: scalar)
        guard cells > 0 else { return nil }
        let regular: NSFont
        let bold: NSFont
        if let menlo = NSFont(name: "Menlo-Regular", size: PhosphorType.bodySize),
           CTFontGetGlyphsForCharacters(menlo, units, &glyphs, units.count) {
            regular = menlo
            bold = NSFont(name: "Menlo-Bold", size: PhosphorType.bodySize) ?? menlo
        } else {
            let cascade = CTFontCreateForString(PhosphorType.bodyFont, string as CFString,
                                                CFRange(location: 0, length: units.count)) as NSFont
            regular = cascade
            bold = cascade
        }
        let width = CGFloat(cells) * ConsoleMetrics.advance
        func advance(_ font: NSFont) -> CGFloat {
            (string as NSString).size(withAttributes: [.font: font]).width
        }
        return Fallback(regular: regular, bold: bold, kern: width - advance(regular), boldKern: width - advance(bold))
    }

    func attributes(_ s: TerminalScreen.Style) -> [NSAttributedString.Key: Any] {
        if let cached = cache[s] { return cached }
        let made = make(s)
        cache[s] = made
        return made
    }

    private func make(_ s: TerminalScreen.Style) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: s.bold ? PhosphorType.boldFont : PhosphorType.bodyFont,
            .paragraphStyle: ConsoleMetrics.paragraph,
        ]
        if s.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }

        guard style != .plain else {
            var color = s.color.map(Self.color) ?? .textColor
            if s.dim { color = color.withAlphaComponent(0.55) }
            let background = s.background.map(Self.color)
            if s.inverse {
                attributes[.foregroundColor] = background ?? .textBackgroundColor
                attributes[.backgroundColor] = color
            } else {
                attributes[.foregroundColor] = color
                if let background { attributes[.backgroundColor] = background }
            }
            return attributes
        }

        // A tube has one colour, so what a program prints in red or green
        // shows in the phosphor's own, and mrk's ✓, ⚠ and ✗ carry the
        // difference. What a tube can vary is brightness: bold glows harder
        // and dim glows less, and a colour past the sixteen glows as bright
        // as it is, so lipgloss's grey help text sits back as it does on a
        // colour screen. A background is a faint bar of the same light.
        let tint = NSColor(style.tint)
        if s.inverse {
            attributes[.foregroundColor] = NSColor(style.ground)
            attributes[.backgroundColor] = tint.withAlphaComponent(0.85)
            return attributes
        }
        let brightness = s.dim ? 0.5 : s.color.map(Self.brightness) ?? 1
        attributes[.foregroundColor] = tint.withAlphaComponent(brightness)
        if let background = s.background {
            attributes[.backgroundColor] = tint.withAlphaComponent(0.1 + 0.3 * Self.luminance(background))
        }
        // Set as a text attribute, not as a shadow on the view: that would
        // halo the whole rectangle instead of the glyphs. Zero offset, because
        // a phosphor dot blooms evenly.
        let glow = NSShadow()
        glow.shadowColor = tint.withAlphaComponent(s.bold ? 0.9 : 0.75 * brightness)
        glow.shadowBlurRadius = s.bold ? 6 : 4
        glow.shadowOffset = .zero
        attributes[.shadow] = glow
        return attributes
    }

    /// The sixteen ANSI colours as the Plain screen shows them, the system's
    /// own, and xterm's for the rest of the 256.
    static func color(_ index: UInt8) -> NSColor {
        guard index >= 16 else {
            switch index % 8 {
            case 0: return .secondaryLabelColor
            case 1: return .systemRed
            case 2: return .systemGreen
            case 3: return .systemYellow
            case 4: return .systemBlue
            case 5: return .systemPurple
            case 6: return .systemCyan
            default: return .textColor
            }
        }
        let rgb = TerminalScreen.rgb(of: index)
        return NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
                       blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }

    /// How bright a tube draws a colour: full for the sixteen, which mrk's
    /// scripts print, and by its luminance for the rest, down to a glow that
    /// still reads.
    static func brightness(_ index: UInt8) -> CGFloat {
        index < 16 ? 1 : 0.4 + 0.6 * min(1, luminance(index) * 1.25)
    }

    /// Relative luminance, 0 to 1.
    static func luminance(_ index: UInt8) -> CGFloat {
        let rgb = TerminalScreen.rgb(of: index)
        return (0.2126 * CGFloat(rgb.red) + 0.7152 * CGFloat(rgb.green) + 0.0722 * CGFloat(rgb.blue)) / 255
    }
}

/// The console's text: what the command printed, selectable as any text is,
/// and the keyboard of the terminal it runs on.
final class ConsoleTextView: NSTextView {
    /// Where typing goes while the command runs; nil once it has exited.
    var onType: (([UInt8]) -> Void)?
    /// What the program has asked the keys to send.
    var keyModes = ConsoleKeys.Modes()

    /// Where the terminal's cursor is, as an offset into the text; nil hides
    /// it.
    var cursorLocation: Int? {
        didSet {
            guard cursorLocation != oldValue else { return }
            cursorLit = true
            needsDisplay = true
            blink()
        }
    }

    var cursorColor = NSColor.textColor {
        didSet { needsDisplay = true }
    }

    private var cursorLit = true
    private var blinkTimer: Timer?
    /// About the rate a terminal's cursor blinked at.
    private static let blinkPeriod: TimeInterval = 0.53

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            blinkTimer?.invalidate()
            blinkTimer = nil
        } else {
            // So the first key pressed goes to the command.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
            blink()
        }
    }

    override func keyDown(with event: NSEvent) {
        if let onType, let bytes = ConsoleKeys.bytes(characters: event.characters, keyCode: event.keyCode,
                                                     modifiers: event.modifierFlags, modes: keyModes) {
            onType(bytes)
            scrollToEndOfDocument(nil)
            return
        }
        // Return and Escape belong to the console's buttons once the command
        // has exited.
        if onType == nil, [36, 53, 76].contains(event.keyCode) {
            nextResponder?.keyDown(with: event)
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        guard let onType, let text = NSPasteboard.general.string(forType: .string) else {
            return super.paste(sender)
        }
        onType(ConsoleKeys.paste(text, bracketed: keyModes.bracketedPaste))
        scrollToEndOfDocument(nil)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)) {
            return onType != nil && NSPasteboard.general.string(forType: .string) != nil
        }
        return super.validateUserInterfaceItem(item)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = cursorRect(), rect.insetBy(dx: -8, dy: -8).intersects(dirtyRect) else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // A block where typing goes, blinking; an outline when typing goes
        // elsewhere, as Terminal draws an inactive window's cursor.
        if window?.isKeyWindow == true && window?.firstResponder === self {
            guard cursorLit else { return }
            let glow = NSShadow()
            glow.shadowColor = cursorColor.withAlphaComponent(0.7)
            glow.shadowBlurRadius = 4
            glow.set()
            cursorColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 1), xRadius: 1, yRadius: 1).fill()
        } else {
            cursorColor.withAlphaComponent(0.6).setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1.5))
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    /// The cell the cursor sits on: the character at its location, or the
    /// place after the last one.
    private func cursorRect() -> NSRect? {
        guard let location = cursorLocation, let layoutManager, let textContainer else { return nil }
        let text = string as NSString
        let font = PhosphorType.bodyFont
        let width = ("M" as NSString).size(withAttributes: [.font: font]).width
        let height = layoutManager.defaultLineHeight(for: font)
        let origin: NSPoint
        if location < text.length {
            let glyph = layoutManager.glyphIndexForCharacter(at: location)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            origin = NSPoint(x: box.minX, y: line.minY)
        } else if text.length == 0 || text.character(at: text.length - 1) == 0x0A {
            layoutManager.ensureLayout(for: textContainer)
            let extra = layoutManager.extraLineFragmentRect
            origin = NSPoint(x: extra.minX + textContainer.lineFragmentPadding, y: extra.minY)
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: text.length - 1)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            origin = NSPoint(x: box.maxX, y: line.minY)
        }
        return NSRect(x: origin.x + textContainerOrigin.x, y: origin.y + textContainerOrigin.y,
                      width: width, height: height)
    }

    /// Blinks while the cursor shows, unless Reduce Motion is on.
    private func blink() {
        let wanted = cursorLocation != nil && window != nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !wanted {
            blinkTimer?.invalidate()
            blinkTimer = nil
            return
        }
        // Typing restarts the blink lit, so the cursor never hides what was
        // just typed.
        blinkTimer?.invalidate()
        let timer = Timer(timeInterval: Self.blinkPeriod, repeats: true) { [weak self] _ in
            guard let self, let rect = self.cursorRect() else { return }
            self.cursorLit.toggle()
            self.setNeedsDisplay(rect.insetBy(dx: -8, dy: -8))
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }
}

/// What a key pressed in the console types at the terminal: what xterm
/// sends, as TERM=xterm-256color promises.
enum ConsoleKeys {
    /// What the program has asked of the keys, as the screen keeps it.
    struct Modes: Equatable {
        /// DECCKM: the arrows send ESC O A and not ESC [ A.
        var applicationCursor = false
        /// The alternate screen shows, where a full-screen program pages
        /// with Page Up and Down, Home and End. On the primary screen those
        /// scroll the console, as they scroll Terminal's.
        var fullScreen = false
        /// Pasted text goes between ESC [ 200 ~ and ESC [ 201 ~.
        var bracketedPaste = false
    }

    /// The bytes for a key, or nil for a key the console leaves to the text
    /// view and the menus.
    static func bytes(characters: String?, keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                      modes: Modes = Modes()) -> [UInt8]? {
        // ⌘ belongs to the app: Copy, Select All, Stop.
        if modifiers.contains(.command) { return nil }
        // The keypad's Enter types U+0003, which a terminal reads as ⌃C.
        if keyCode == 76 { return [0x0D] }
        // Escape, which bubbletea reads to go back or quit.
        if keyCode == 53 { return [0x1B] }
        // ⇧Tab arrives as U+0019, which is also ⌃Y.
        if keyCode == 48, modifiers.contains(.shift) { return Array("\u{1B}[Z".utf8) }
        guard let characters, !characters.isEmpty else { return nil }
        let scalars = characters.unicodeScalars
        // The arrows, the page keys and the function keys arrive as AppKit's
        // private-use characters.
        if scalars.count == 1, let key = scalars.first, (0xF700...0xF8FF).contains(key.value) {
            return functionKey(key.value, modifiers: modifiers, modes: modes)
        }
        if scalars.contains(where: { (0xF700...0xF8FF).contains($0.value) }) { return nil }
        if scalars.count == 1, let c = scalars.first, c.value < 0x20 || c.value == 0x7F {
            switch c.value {
            case 0x0D, 0x09, 0x7F:
                // Return, Tab and Delete.
                return [UInt8(c.value)]
            case 0x19, 0x1A:
                // ⌃Y and ⌃Z suspend the program, and with no shell's job
                // control nothing could start it again.
                return nil
            default:
                // ⌃C, ⌃D, ⌃U and the rest when ⌃ is held.
                return modifiers.contains(.control) ? [UInt8(c.value)] : nil
            }
        }
        return Array(characters.utf8)
    }

    /// xterm's sequence for one of AppKit's function keys, with its
    /// modifiers as xterm numbers them: ESC [ 1 ; 2 A for ⇧↑.
    private static func functionKey(_ key: UInt32, modifiers: NSEvent.ModifierFlags, modes: Modes) -> [UInt8]? {
        let modifier = 1 + (modifiers.contains(.shift) ? 1 : 0) + (modifiers.contains(.option) ? 2 : 0)
            + (modifiers.contains(.control) ? 4 : 0)
        /// A key whose sequence ends in a letter: CSI or SS3, and the letter.
        func letter(_ final: String, ss3: Bool) -> [UInt8] {
            if modifier > 1 { return Array("\u{1B}[1;\(modifier)\(final)".utf8) }
            return Array(((ss3 ? "\u{1B}O" : "\u{1B}[") + final).utf8)
        }
        /// A key whose sequence is a number and a tilde.
        func tilde(_ number: Int) -> [UInt8] {
            Array((modifier > 1 ? "\u{1B}[\(number);\(modifier)~" : "\u{1B}[\(number)~").utf8)
        }
        switch key {
        case 0xF700: return letter("A", ss3: modes.applicationCursor)  // ↑
        case 0xF701: return letter("B", ss3: modes.applicationCursor)  // ↓
        case 0xF702: return letter("D", ss3: modes.applicationCursor)  // ←
        case 0xF703: return letter("C", ss3: modes.applicationCursor)  // →
        case 0xF704: return letter("P", ss3: true)  // F1
        case 0xF705: return letter("Q", ss3: true)  // F2
        case 0xF706: return letter("R", ss3: true)  // F3
        case 0xF707: return letter("S", ss3: true)  // F4
        case 0xF708...0xF70F:  // F5 to F12
            return tilde([15, 17, 18, 19, 20, 21, 23, 24][Int(key - 0xF708)])
        case 0xF727: return tilde(2)  // Insert
        case 0xF728: return tilde(3)  // forward Delete
        case 0xF729: return modes.fullScreen ? letter("H", ss3: modes.applicationCursor) : nil  // Home
        case 0xF72B: return modes.fullScreen ? letter("F", ss3: modes.applicationCursor) : nil  // End
        case 0xF72C: return modes.fullScreen ? tilde(5) : nil  // Page Up
        case 0xF72D: return modes.fullScreen ? tilde(6) : nil  // Page Down
        default: return nil
        }
    }

    /// Pasted text as a terminal types it: a newline is Return, and with
    /// bracketed paste on, the program is told where the paste starts and
    /// ends, so a picker's filter takes it as text and not as keys. An end
    /// marker inside the text is taken out, so it cannot end the paste early.
    static func paste(_ text: String, bracketed: Bool) -> [UInt8] {
        var typed = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        guard bracketed else { return Array(typed.utf8) }
        typed = typed.replacingOccurrences(of: "\u{1B}[201~", with: "")
        return Array("\u{1B}[200~\(typed)\u{1B}[201~".utf8)
    }
}
