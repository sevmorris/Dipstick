import AppKit
import XCTest
@testable import Dipstick

final class TerminalScreenTests: XCTestCase {
    private func screen(_ bytes: String, columns: Int = 80, rows: Int = 24) -> TerminalScreen {
        var screen = TerminalScreen(columns: columns, rows: rows)
        screen.feed(bytes)
        return screen
    }

    private func rowTexts(_ screen: TerminalScreen) -> [String] {
        screen.display.rows.map { $0.map(\.text).joined() }
    }

    // MARK: - Lines, as a script prints them

    func testRowsEndAtANewlineAndTheCursorIsOnTheLast() {
        let s = screen("one\r\ntwo\r\nthr")
        XCTAssertEqual(rowTexts(s), ["one", "two", "thr"])
        XCTAssertEqual(s.text, "one\ntwo\nthr")
        XCTAssertEqual(s.display.cursor, .init(row: 2, offset: 3))
        XCTAssertFalse(s.atLineStart)
        XCTAssertTrue(screen("done\r\n").atLineStart)
        XCTAssertEqual(screen("done\r\n").text, "done\n")
    }

    /// The primary screen shows the rows down to the cursor, not a page.
    func testAShortRunIsLinesNotAPage() {
        XCTAssertEqual(screen("").display.rows.count, 1)
        XCTAssertEqual(screen("a\r\nb\r\n").display.rows.count, 3)
    }

    /// A line feed alone goes down and keeps the column: the terminal adds
    /// the carriage return to a program's "\n" only while its output
    /// processing is on, and bubbletea turns that off.
    func testALineFeedKeepsTheColumn() {
        XCTAssertEqual(screen("ab\ncd").text, "ab\n  cd")
    }

    /// git's progress: each count writes over the last.
    func testACarriageReturnWritesOverTheLine() {
        XCTAssertEqual(screen("Counting:  10%\rCounting: 100%, done.\r\n").text, "Counting: 100%, done.\n")
        XCTAssertEqual(screen("abcdef\rXY").text, "XYcdef")
        XCTAssertEqual(screen("abcdef\rXY").display.cursor?.offset, 2)
    }

    /// The terminal echoes Delete as "\b \b".
    func testTheEchoOfDeleteTakesTheCharacterOff() {
        let s = screen("Push/commit anyway? yx\u{8} \u{8}")
        XCTAssertEqual(s.text, "Push/commit anyway? y")
        XCTAssertEqual(s.display.cursor?.offset, "Push/commit anyway? y".utf16.count)
    }

    func testEraseInLine() {
        XCTAssertEqual(screen("abcdef\r\u{1B}[K").text, "")
        XCTAssertEqual(screen("abcdef\u{1B}[3D\u{1B}[0K").text, "abc")
        XCTAssertEqual(screen("abcdef\u{1B}[3D\u{1B}[1K").text, "    ef")
        XCTAssertEqual(screen("abcdef\u{1B}[2Kxy").text, "      xy")
    }

    func testATabGoesToTheNextStop() {
        XCTAssertEqual(screen("ab\tc").text, "ab      c")
        let t = screen("ab\t")
        XCTAssertEqual(t.display.cursor?.offset, 8)
        XCTAssertEqual(t.text, "ab      ")
        XCTAssertEqual(screen("abcdefghij\u{1B}[Zx").text, "abcdefghxj", "back a stop")
    }

    // MARK: - Styles

    func testMrksColoursAreStylesAndNotText() {
        // lib.sh's ok and warn, and section's bold blue.
        let s = screen("\u{1B}[32m  ✓\u{1B}[0m Saved\r\n\u{1B}[1m\u{1B}[34m══ Dock setup\u{1B}[0m\r\n")
        XCTAssertEqual(s.text, "  ✓ Saved\n══ Dock setup\n")
        XCTAssertEqual(s.display.rows[0], [
            TerminalScreen.Run(text: "  ✓", style: .init(color: 2)),
            TerminalScreen.Run(text: " Saved", style: .init()),
        ])
        XCTAssertEqual(s.display.rows[1], [TerminalScreen.Run(text: "══ Dock setup", style: .init(bold: true, color: 4))])
    }

    func testSGRCodes() {
        let s = screen("\u{1B}[2md\u{1B}[22;4mu\u{1B}[24;7mi\u{1B}[0;91mb\u{1B}[39;44mg\u{1B}[49mn\u{1B}[mx")
        XCTAssertEqual(s.display.rows[0], [
            TerminalScreen.Run(text: "d", style: .init(dim: true)),
            TerminalScreen.Run(text: "u", style: .init(underline: true)),
            TerminalScreen.Run(text: "i", style: .init(inverse: true)),
            TerminalScreen.Run(text: "b", style: .init(color: 9)),
            TerminalScreen.Run(text: "g", style: .init(background: 4)),
            TerminalScreen.Run(text: "nx", style: .init()),
        ])
    }

    /// 256 colours are kept, a 24-bit one is the nearest of them, and an
    /// extended colour's arguments are never codes of their own: 38;5;1 is
    /// colour 1, not bold.
    func testExtendedColours() {
        XCTAssertEqual(screen("\u{1B}[38;5;1mx").display.rows[0].first?.style, .init(color: 1))
        XCTAssertEqual(screen("\u{1B}[38;5;200mx").display.rows[0].first?.style, .init(color: 200))
        XCTAssertEqual(screen("\u{1B}[48;5;236mx").display.rows[0].first?.style, .init(background: 236))
        // mrk's ColHighlight, #ff87af, and a near black.
        XCTAssertEqual(screen("\u{1B}[38;2;255;135;175mx").display.rows[0].first?.style, .init(color: 211))
        XCTAssertEqual(screen("\u{1B}[38;2;1;2;4mx").display.rows[0].first?.style, .init(color: 16))
        XCTAssertEqual(screen("\u{1B}[38:5:117mx").display.rows[0].first?.style, .init(color: 117))
        XCTAssertEqual(screen("\u{1B}[38:2::255:135:175mx").display.rows[0].first?.style, .init(color: 211))
        XCTAssertEqual(screen("\u{1B}[58;5;1;1mx").display.rows[0].first?.style, .init(bold: true),
                       "the underline's colour is skipped")
        XCTAssertEqual(TerminalScreen.rgb(of: 117), .init(red: 135, green: 215, blue: 255))
        XCTAssertEqual(TerminalScreen.rgb(of: 244), .init(red: 128, green: 128, blue: 128))
        XCTAssertEqual(TerminalScreen.nearest(red: 128, green: 128, blue: 128), 244)
    }

    /// A space on a background shows, so a selected row's bar is not trimmed
    /// off; and an erase fills with the background, as bce promises.
    func testABackgroundIsKept() {
        let s = screen("\u{1B}[48;5;236m x \u{1B}[m")
        XCTAssertEqual(s.text, " x ")
        let erased = screen("\u{1B}[44m\u{1B}[K\u{1B}[m", columns: 10)
        XCTAssertEqual(erased.display.rows[0], [TerminalScreen.Run(text: String(repeating: " ", count: 10),
                                                                   style: .init(background: 4))])
    }

    // MARK: - The cursor, and the grid

    func testTheCursorMovesAbsolutelyAndRelatively() {
        XCTAssertEqual(screen("\u{1B}[3;5Hx").text, "\n\n    x")
        XCTAssertEqual(screen("abc\u{1B}[2Dx").text, "axc")
        XCTAssertEqual(screen("\u{1B}[5;1Ha\u{1B}[2Ab\u{1B}[Bc\u{1B}[3Cd").text, "\n\n b\n  c   d\na")
        XCTAssertEqual(screen("\u{1B}[2;3Hx\u{1B}[Gy\u{1B}[4dz").text, "\ny x\n\n z")
        // mrk-menu sends row 0, which is row 1.
        XCTAssertEqual(screen("\u{1B}[0;3Hx").text, "  x")
        XCTAssertEqual(screen("a\r\nb\u{1B}[Ec\u{1B}[2Fd").text, "d\nb\nc")
        // Clamped to the corner; the cursor stays on the last column it wrote.
        XCTAssertEqual(screen("\u{1B}[99;99Hx", columns: 10, rows: 3).display.cursor, .init(row: 2, offset: 9))
    }

    func testEraseInDisplay() {
        XCTAssertEqual(screen("one\r\ntwo\r\nthree\u{1B}[2;2H\u{1B}[J").text, "one\nt")
        XCTAssertEqual(screen("one\r\ntwo\r\nthree\u{1B}[2;2H\u{1B}[1J").text, "\n  o\nthree")
        XCTAssertEqual(screen("one\r\ntwo\u{1B}[2J\u{1B}[Hx").text, "x")
    }

    func testInsertAndDeleteCharactersAndLines() {
        XCTAssertEqual(screen("abcdef\u{1B}[3G\u{1B}[2@").text, "ab  cdef")
        XCTAssertEqual(screen("abcdef\u{1B}[3G\u{1B}[2P").text, "abef")
        XCTAssertEqual(screen("abcdef\u{1B}[3G\u{1B}[2X").text, "ab  ef")
        XCTAssertEqual(screen("a\r\nb\r\nc\u{1B}[2;1H\u{1B}[L").text, "a\n\nb\nc")
        XCTAssertEqual(screen("a\r\nb\r\nc\u{1B}[1;1H\u{1B}[M").text, "b\nc")
        XCTAssertEqual(screen("abc\u{1B}[4h\u{1B}[1GX\u{1B}[4lY").text, "XYbc", "insert mode, then replace")
        XCTAssertEqual(screen("a\u{1B}[3b").text, "aaaa", "REP repeats the last character")
    }

    /// A full row wraps only when the next character comes, as in xterm, so
    /// a program that fills the last column does not scroll a line for
    /// nothing.
    func testAutowrapWaitsForTheNextCharacter() {
        let wrapped = screen("abcdefg", columns: 5)
        XCTAssertEqual(rowTexts(wrapped), ["abcde", "fg"])
        let full = screen("abcde", columns: 5)
        XCTAssertEqual(full.text, "abcde")
        XCTAssertEqual(full.display.cursor, .init(row: 0, offset: 4))
        XCTAssertEqual(screen("abcde\r\nx", columns: 5).text, "abcde\nx")
        XCTAssertEqual(screen("\u{1B}[?7labcdefg", columns: 5).text, "abcdg", "with autowrap off")
    }

    /// A line autowrap carried on is one line in the text, as Terminal
    /// copies it, the spaces at the wrap included, and so is one that has
    /// scrolled off.
    func testAWrappedLineIsOneLineOfText() {
        XCTAssertEqual(screen("abcdefg", columns: 5).text, "abcdefg")
        XCTAssertEqual(screen("abcd efgh\r\nx", columns: 5).text, "abcd efgh\nx")
        var s = screen("abcdefg\r\n", columns: 5, rows: 2)
        s.feed("x\r\n")
        XCTAssertEqual(s.scrollback.count, 2)
        XCTAssertEqual(s.text, "abcdefg\nx\n")
        XCTAssertEqual(screen("abcdefg\u{1B}[1;1H\u{1B}[2K", columns: 5).text, "\nfg", "a row erased runs on no more")
    }

    /// Lines that scroll off the top are kept, and erasing them does nothing:
    /// they are the console's record of the run.
    func testScrolledLinesAreKept() {
        let lines = (1...30).map { "line \($0)" }
        var s = screen(lines.joined(separator: "\r\n") + "\r\n")
        XCTAssertEqual(s.scrollback.count, 7)
        XCTAssertEqual(s.scrollback.first, [TerminalScreen.Run(text: "line 1", style: .init())])
        XCTAssertEqual(s.text, lines.joined(separator: "\n") + "\n")
        s.feed("\u{1B}[3J\u{1B}c")
        XCTAssertEqual(s.scrollback.count, 7)
    }

    /// A scroll region scrolls only its rows; what leaves it is not saved
    /// unless it starts at the top.
    func testAScrollRegion() {
        var s = screen("top\r\n\u{1B}[2;3r\u{1B}[2;1Ha\r\nb\r\nc\u{1B}[4;1Hbottom", columns: 10, rows: 4)
        XCTAssertEqual(s.text, "top\nb\nc\nbottom")
        XCTAssertEqual(s.scrollback, [])
        s.feed("\u{1B}[2;1H\u{1B}M")
        XCTAssertEqual(s.text, "top\n\nb\nbottom", "reverse index at the top of the region")
        s.feed("\u{1B}[r\u{1B}[4;1H\r\n")
        XCTAssertEqual(s.scrollback.count, 1, "a full-screen region saves again")
    }

    func testSaveAndRestoreTheCursor() {
        XCTAssertEqual(screen("ab\u{1B}7\u{1B}[3;1Hx\u{1B}8y").text, "aby\n\nx")
        XCTAssertEqual(screen("ab\u{1B}[s\u{1B}[3;1Hx\u{1B}[uy").text, "aby\n\nx")
    }

    // MARK: - The alternate screen

    /// mrk-picker and mrk-menu draw on the alternate screen, and leave the
    /// primary as it was when they exit.
    func testTheAlternateScreen() {
        var s = screen("before\r\n", columns: 20, rows: 5)
        s.feed("\u{1B}[?1049h\u{1B}[2J\u{1B}[3J\u{1B}[1;1Hpicker\u{1B}[5;1Hhelp")
        XCTAssertTrue(s.usesAlternateScreen)
        XCTAssertEqual(rowTexts(s), ["picker", "", "", "", "help"], "every row, the whole page")
        XCTAssertEqual(s.text, "picker\n\n\n\nhelp", "without the primary's lines")
        s.feed("\u{1B}[?1049l")
        XCTAssertFalse(s.usesAlternateScreen)
        XCTAssertEqual(s.text, "before\n")
        XCTAssertEqual(s.display.cursor, .init(row: 1, offset: 0))
        s.feed("after")
        XCTAssertEqual(s.text, "before\nafter")
    }

    /// A program that dies on the alternate screen leaves the console as it
    /// found it.
    func testAProgramThatExitsPutsTheScreenBack() {
        var s = screen("before\r\n\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1h\u{1B}[?2004h\u{1B}[31mx")
        XCTAssertFalse(s.cursorVisible)
        XCTAssertTrue(s.applicationCursorKeys)
        XCTAssertTrue(s.bracketedPaste)
        s.programExited()
        XCTAssertFalse(s.usesAlternateScreen)
        XCTAssertTrue(s.cursorVisible)
        XCTAssertFalse(s.applicationCursorKeys)
        XCTAssertFalse(s.bracketedPaste)
        s.feed("y")
        XCTAssertEqual(s.display.rows[1], [TerminalScreen.Run(text: "y", style: .init())])
    }

    // MARK: - What a program asks

    /// termenv's question, as lipgloss 1.0 asks it before main: the
    /// background colour, fenced by a cursor report. Unanswered, it waits
    /// five seconds.
    func testTermenvsQuestionIsAnswered() {
        var s = TerminalScreen()
        s.backgroundColor = .init(red: 0x05, green: 0x0E, blue: 0x08)
        s.feed("ab\u{1B}]11;?\u{1B}\\\u{1B}[6n")
        XCTAssertEqual(String(decoding: s.takeReplies(), as: UTF8.self),
                       "\u{1B}]11;rgb:0505/0e0e/0808\u{1B}\\\u{1B}[1;3R")
        XCTAssertEqual(s.takeReplies(), [], "each answer once")
        XCTAssertEqual(s.text, "ab")
    }

    func testTheOtherQuestions() {
        func replies(_ bytes: String) -> String {
            var s = TerminalScreen(columns: 100, rows: 30)
            s.feed(bytes)
            return String(decoding: s.takeReplies(), as: UTF8.self)
        }
        XCTAssertEqual(replies("\u{1B}]10;?\u{7}"), "\u{1B}]10;rgb:cccc/cccc/cccc\u{7}", "ends as the question did")
        XCTAssertEqual(replies("\u{1B}[5n"), "\u{1B}[0n")
        XCTAssertEqual(replies("\u{1B}[c"), "\u{1B}[?62;22c")
        XCTAssertEqual(replies("\u{1B}[>c"), "\u{1B}[>1;10;0c")
        XCTAssertEqual(replies("\u{1B}[18t"), "\u{1B}[8;30;100t")
        XCTAssertEqual(replies("\u{1B}[?25$p\u{1B}[?2026$p"), "\u{1B}[?25;1$y\u{1B}[?2026;0$y")
        XCTAssertEqual(replies("\u{1B}[?6h\u{1B}[3;4r\u{1B}[2;5H\u{1B}[6n"), "\u{1B}[2;5R", "origin mode counts from the region")
        // gum's start, with bubbletea v2: none of it needs an answer, and
        // none of it is text.
        var gum = TerminalScreen()
        gum.feed("\u{1B}[?25l\u{1B}[?5W\u{1B}[?2004h\u{1B}[>4;2m\u{1B}[>1u\u{1B}[?u\r\u{1B}[J")
        XCTAssertEqual(gum.takeReplies(), [])
        XCTAssertEqual(gum.text, "")
        XCTAssertEqual(gum.display.rows[0], [], "CSI > 4;2 m is not SGR")
    }

    func testOtherSequencesAreTakenOutWhole() {
        // A window title, the cursor hidden and shown, a character set, a link.
        let s = screen("\u{1B}]0;title\u{7}a\u{1B}[?25lb\u{1B}[?25h\u{1B}(Bc\u{1B}[2Ad\u{1B}]8;;http://x\u{1B}\\e\u{1B}P+q\u{1B}\\f")
        XCTAssertEqual(s.text, "abcdef")
        XCTAssertEqual(screen("\u{1B}]0;cut short\u{1B}[1mx").display.rows[0], [TerminalScreen.Run(text: "x", style: .init(bold: true))],
                       "an escape ends an unfinished string and starts its own sequence")
    }

    // MARK: - Characters

    func testWideAndCombiningCharacters() {
        let wide = screen("日本x")
        XCTAssertEqual(wide.text, "日本x")
        XCTAssertEqual(wide.display.cursor?.offset, 3)
        XCTAssertEqual(screen("日本x\u{1B}[3G\u{1B}[P").text, "日 x", "deleting half a wide character")
        XCTAssertEqual(screen("e\u{301}x").text, "e\u{301}x")
        XCTAssertEqual(screen("e\u{301}x\u{1B}[2Gy").text, "e\u{301}y", "a mark and its letter are one column")
        XCTAssertEqual(rowTexts(screen("abcd日", columns: 5)), ["abcd", "日"], "a wide character does not split")
        XCTAssertEqual(TerminalScreen.width(of: "✓"), 1)
        XCTAssertEqual(TerminalScreen.width(of: "✅"), 2)
        XCTAssertEqual(TerminalScreen.width(of: "\u{301}"), 0)
    }

    func testDECLineDrawing() {
        XCTAssertEqual(screen("\u{1B}(0lqk\r\nx x\r\nmqj\u{1B}(Bq").text, "┌─┐\n│ │\n└─┘q")
    }

    /// A character can arrive split across two reads.
    func testACharacterSplitAcrossFeeds() {
        var s = TerminalScreen()
        let bytes = Array("✓ ok".utf8)
        s.feed(Array(bytes[0..<2]))
        s.feed(Array(bytes[2...]))
        XCTAssertEqual(s.text, "✓ ok")
        XCTAssertEqual(s.display.cursor?.offset, 4)
    }

    func testBrokenUTF8IsAReplacement() {
        var s = TerminalScreen()
        s.feed([0x61, 0xE2, 0x9C, 0x62, 0xFF, 0x63])
        XCTAssertEqual(s.text, "a\u{FFFD}b\u{FFFD}c")
    }

    // MARK: - The size

    /// A smaller screen keeps the cursor on it: blank rows under the cursor
    /// go first, then rows from the top, into the saved lines. A narrower
    /// one cuts its rows; a program draws again for the new size.
    func testResizing() {
        var s = screen("one\r\ntwo\r\nthree", columns: 10, rows: 6)
        s.resize(columns: 10, rows: 4)
        XCTAssertEqual(s.scrollback, [], "only blank rows went")
        s.resize(columns: 10, rows: 2)
        XCTAssertEqual(s.scrollback.map { $0.map(\.text).joined() }, ["one"])
        XCTAssertEqual(rowTexts(s), ["two", "three"])
        XCTAssertEqual(s.display.cursor, .init(row: 1, offset: 5))
        s.resize(columns: 3, rows: 5)
        XCTAssertEqual(s.text, "one\ntwo\nthr")
        XCTAssertEqual(s.display.cursor, .init(row: 1, offset: 2))
        s.feed("\r\n\u{1B}[18t")
        XCTAssertEqual(String(decoding: s.takeReplies(), as: UTF8.self), "\u{1B}[8;5;3t")
    }

    func testEachChangeIsANewRevision() {
        var s = TerminalScreen()
        let first = s.revision
        s.feed("x")
        XCTAssertNotEqual(s.revision, first)
        let second = s.revision
        s.resize(columns: 100, rows: 30)
        XCTAssertNotEqual(s.revision, second)
    }

    /// gum choose, as gum 2.0.2 drew it on 2026-11-06: bubbletea v2's inline
    /// renderer moves up over what it drew and erases it, so the picker
    /// stays in one place and goes when it is done.
    func testGumsInlinePickerRedrawsInPlace() {
        var s = screen("$ make sync\r\n")
        let frame = "\r\u{1B}[J\u{1B}[38;5;99mChoose:\u{1B}[m\r\n\u{1B}[38;5;212m> one\u{1B}[m\r\n  two\r\n  three\r\n\n\n"
            + "\u{1B}[38;5;241m←↓↑→\u{1B}[m \u{1B}[38;5;239mnavigate\u{1B}[m"
        s.feed("\u{1B}[?25l\u{1B}[?2004h" + frame)
        XCTAssertEqual(s.text, "$ make sync\nChoose:\n> one\n  two\n  three\n\n\n←↓↑→ navigate")
        s.feed("\r\u{1B}[6A" + frame.replacingOccurrences(of: "> one\u{1B}[m\r\n  two", with: "  one\u{1B}[m\r\n> two"))
        XCTAssertEqual(s.text, "$ make sync\nChoose:\n  one\n> two\n  three\n\n\n←↓↑→ navigate")
        s.feed("\r\u{1B}[6A\u{1B}[J\u{1B}[>4m\u{1B}[<1u\u{1B}[J\u{1B}[?25h\u{1B}[?2004ltwo\r\n")
        XCTAssertEqual(s.text, "$ make sync\ntwo\n")
    }
}

final class ConsoleMetricsTests: XCTestCase {
    /// The console's narrowest window holds 80 columns however tall it is:
    /// the bezel is widest on a tube as tall as it is wide, and a scroller
    /// that always shows takes its width too.
    func testTheNarrowestWindowHolds80Columns() {
        let tube = ConsoleWindowView.minimumSize.width - 32  // the screen's padding, 16 a side
        let inset = TubeFace().boxInset(for: CGSize(width: tube, height: tube))
        let scroller = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let room = NSSize(width: tube - 2 * inset - scroller, height: tube - 2 * inset)
        XCTAssertGreaterThanOrEqual(ConsoleMetrics.cells(in: room)?.columns ?? 0, 80)
    }

    func testCells() {
        let size = ConsoleMetrics.cells(in: NSSize(width: 2 * 10 + 2 * 5 + 100 * ConsoleMetrics.advance + 1,
                                                   height: 2 * 8 + 30 * ConsoleMetrics.lineHeight + 1))
        XCTAssertEqual(size, .init(columns: 100, rows: 30))
    }

    /// A view not laid out yet is no size at all, never a terminal of 2 × 2:
    /// a resize to that would cut every row on the screen.
    func testAViewNotLaidOutIsNoSize() {
        XCTAssertNil(ConsoleMetrics.cells(in: .zero))
        XCTAssertNil(ConsoleMetrics.cells(in: NSSize(width: 800, height: 0)))
        XCTAssertNil(ConsoleMetrics.cells(in: NSSize(width: 0, height: 600)))
        XCTAssertNil(ConsoleMetrics.cells(in: NSSize(width: 2 * 10 + 2 * 5 + ConsoleMetrics.advance, height: 600)))
        XCTAssertEqual(ConsoleMetrics.cells(in: NSSize(width: 2 * 10 + 2 * 5 + 2 * ConsoleMetrics.advance,
                                                      height: 2 * 8 + 2 * ConsoleMetrics.lineHeight)),
                       .init(columns: 2, rows: 2))
    }
}

final class ConsolePainterTests: XCTestCase {
    /// A character SF Mono lacks still takes its cells, so the rest of its
    /// row lines up with the rows under it: mrk-status's ⚠ is drawn in
    /// Menlo, which is narrower.
    func testEveryCharacterTakesItsCells() {
        let painter = ConsolePainter(style: .green)
        for (text, cells) in [("a…b", 3), ("a⚠b", 3), ("✔ ok", 4), ("日本x", 5), ("✅x", 3)] {
            let width = painter.text([TerminalScreen.Run(text: text, style: .init())]).size().width
            XCTAssertEqual(width, CGFloat(cells) * ConsoleMetrics.advance, accuracy: 0.05, text)
        }
        let bold = painter.text([TerminalScreen.Run(text: "⚠ x", style: .init(bold: true))]).size().width
        XCTAssertEqual(bold, 3 * ConsoleMetrics.advance, accuracy: 0.05)
    }
}

final class ConsoleKeysTests: XCTestCase {
    private func bytes(_ characters: String?, keyCode: UInt16 = 0, _ modifiers: NSEvent.ModifierFlags = [],
                       _ modes: ConsoleKeys.Modes = .init()) -> String? {
        ConsoleKeys.bytes(characters: characters, keyCode: keyCode, modifiers: modifiers, modes: modes)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    func testTypingAndTheEditingKeys() {
        XCTAssertEqual(bytes("y"), "y")
        XCTAssertEqual(bytes("é"), "é")
        XCTAssertEqual(bytes("\r", keyCode: 36), "\r")
        XCTAssertEqual(bytes("\u{7F}", keyCode: 51), "\u{7F}")
        XCTAssertEqual(bytes("\t", keyCode: 48), "\t")
    }

    /// The keypad's Enter is Return, not the ⌃C AppKit types for it.
    func testKeypadEnterIsReturn() {
        XCTAssertEqual(bytes("\u{3}", keyCode: 76), "\r")
    }

    func testControlKeysOnlyWithControlHeld() {
        XCTAssertEqual(bytes("\u{3}", keyCode: 8, .control), "\u{3}")
        XCTAssertEqual(bytes("\u{4}", keyCode: 2, .control), "\u{4}")
        XCTAssertNil(bytes("\u{4}", keyCode: 2))
    }

    /// Escape and ⇧Tab, which a picker reads to go back.
    func testEscapeAndShiftTab() {
        XCTAssertEqual(bytes("\u{1B}", keyCode: 53), "\u{1B}")
        XCTAssertEqual(bytes("\u{19}", keyCode: 48, .shift), "\u{1B}[Z")
    }

    /// ⌃Z and ⌃Y would suspend the command with nothing to start it again.
    func testNothingSuspends() {
        XCTAssertNil(bytes("\u{1A}", keyCode: 6, .control))
        XCTAssertNil(bytes("\u{19}", keyCode: 16, .control))
    }

    func testTheArrowsAsTheProgramAsks() {
        XCTAssertEqual(bytes("\u{F700}", keyCode: 126, [.numericPad, .function]), "\u{1B}[A")
        XCTAssertEqual(bytes("\u{F701}", keyCode: 125), "\u{1B}[B")
        XCTAssertEqual(bytes("\u{F703}", keyCode: 124), "\u{1B}[C")
        XCTAssertEqual(bytes("\u{F702}", keyCode: 123), "\u{1B}[D")
        XCTAssertEqual(bytes("\u{F700}", keyCode: 126, [], .init(applicationCursor: true)), "\u{1B}OA")
        XCTAssertEqual(bytes("\u{F700}", keyCode: 126, .shift), "\u{1B}[1;2A")
        XCTAssertEqual(bytes("\u{F703}", keyCode: 124, [.option, .control], .init(applicationCursor: true)), "\u{1B}[1;7C")
    }

    /// The page keys, Home and End scroll the console on the primary screen,
    /// and go to a full-screen program on the alternate one.
    func testThePageKeysGoToAFullScreenProgram() {
        let full = ConsoleKeys.Modes(fullScreen: true)
        XCTAssertNil(bytes("\u{F72C}", keyCode: 116))
        XCTAssertNil(bytes("\u{F729}", keyCode: 115))
        XCTAssertEqual(bytes("\u{F72C}", keyCode: 116, [], full), "\u{1B}[5~")
        XCTAssertEqual(bytes("\u{F72D}", keyCode: 121, [], full), "\u{1B}[6~")
        XCTAssertEqual(bytes("\u{F729}", keyCode: 115, [], full), "\u{1B}[H")
        XCTAssertEqual(bytes("\u{F72B}", keyCode: 119, [], full), "\u{1B}[F")
    }

    func testTheOtherFunctionKeys() {
        XCTAssertEqual(bytes("\u{F728}", keyCode: 117), "\u{1B}[3~")
        XCTAssertEqual(bytes("\u{F704}", keyCode: 122), "\u{1B}OP")
        XCTAssertEqual(bytes("\u{F708}", keyCode: 96), "\u{1B}[15~")
        XCTAssertEqual(bytes("\u{F70F}", keyCode: 111), "\u{1B}[24~")
        XCTAssertNil(bytes("\u{F746}"))
    }

    func testTheAppKeepsCommand() {
        XCTAssertNil(bytes("c", keyCode: 8, .command))
        XCTAssertNil(bytes("\u{F700}", keyCode: 126, .command))
        XCTAssertNil(bytes(""))
        XCTAssertNil(bytes(nil))
    }

    func testPaste() {
        XCTAssertEqual(String(decoding: ConsoleKeys.paste("a\nb\r\nc", bracketed: false), as: UTF8.self), "a\rb\rc")
        XCTAssertEqual(String(decoding: ConsoleKeys.paste("x\u{1B}[201~y", bracketed: true), as: UTF8.self),
                       "\u{1B}[200~xy\u{1B}[201~")
    }
}
