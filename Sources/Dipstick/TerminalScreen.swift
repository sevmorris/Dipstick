import Foundation

/// The screen of the terminal the console runs its commands on: a grid of
/// cells, as an xterm has, and above it the lines that have scrolled off its
/// top, which the console keeps as the record of the run.
///
/// The console says TERM=xterm-256color, and this is the part of xterm that
/// the programs mrk starts use. A script's lines, with SGR's colour and
/// weight. git's progress, which a carriage return writes over. And the
/// full-screen programs: bubbletea's renderers, which move the cursor up and
/// erase what they drew before (gum choose, inline), or draw on the alternate
/// screen with absolute moves (mrk-picker and mrk-menu). So the cursor
/// moves, erases, inserts and deletes; a scroll region; the alternate screen;
/// autowrap; and the modes that change what the keys send (DECCKM, bracketed
/// paste), which the console reads. Every other sequence is taken out whole.
///
/// A program can ask the terminal things, and some wait for the answer:
/// termenv, under lipgloss 1.0, asks for the background colour (OSC 11)
/// fenced by a cursor position report (DSR 6n), and waits five seconds when
/// nothing answers. The answers queue up in `replies`, which the session
/// types back at the program.
///
/// Erasing the saved lines (ED 3) does nothing: bubbletea sends it as it
/// starts, and the lines are the console's record of what ran. Nor is a line
/// reflowed when the screen changes width: a narrower screen cuts its rows,
/// as xterm's does, and the program draws again for the new size.
struct TerminalScreen: Sendable {
    struct Style: Hashable, Sendable {
        var bold = false
        var dim = false
        var underline = false
        var inverse = false
        /// An xterm colour: 0 to 7, 8 to 15 for the bright ones, then the
        /// colour cube and the greys up to 255. nil for the terminal's own. A
        /// 24-bit colour is the nearest of the 256.
        var color: UInt8?
        /// The background, the same way.
        var background: UInt8?
    }

    /// Text in one style.
    struct Run: Equatable, Sendable {
        var text: String
        var style: Style
    }

    /// Where the cursor is drawn: a row of `Display.rows`, and a place in its
    /// text in UTF-16 units, as a text view counts.
    struct Cursor: Equatable, Sendable {
        var row: Int
        var offset: Int
    }

    /// What the console draws of the grid. On the primary screen, the rows
    /// down to the last one written or the cursor's, whichever is lower, so
    /// a short run shows as lines and not as a page with a gap under it. On
    /// the alternate screen, every row: the program drew the whole page.
    struct Display: Equatable, Sendable {
        var rows: [[Run]]
        /// nil when the program has hidden the cursor.
        var cursor: Cursor?
    }

    /// An RGB colour, for the answer to OSC 10 and 11.
    struct RGB: Equatable, Sendable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
    }

    private struct Cell: Equatable, Sendable {
        /// One character with any combining marks after it; "" for the right
        /// half of a wide character.
        var text: String
        var style: Style
        /// The columns it takes: 1, or 2 for a wide character, or 0 for the
        /// right half of one.
        var width: UInt8 = 1
        /// On a row's last cell: autowrap carried the line on to the next
        /// row. It goes where the row goes, and a new cell clears it.
        var wraps = false

        /// Nothing shows: a space with nothing under it.
        var isBlank: Bool {
            text == " " && style.background == nil && !style.inverse && !style.underline
        }
    }

    private struct SavedCursor: Sendable {
        var row: Int
        var column: Int
        var style: Style
        var pendingWrap: Bool
        var originMode: Bool
        var graphics: Bool
    }

    private enum State: Sendable {
        case ground, escape, escapeIntermediate, csi, string, stringEscape
    }

    private(set) var columns: Int
    private(set) var rows: Int
    /// The rows that have scrolled off the top of the primary screen, oldest
    /// first. It only grows.
    private(set) var scrollback: [[Run]] = []
    /// Whether each of them ran on into the next.
    private var scrollbackWraps: [Bool] = []
    /// Bumped by every change, so a view can tell whether it has drawn this.
    private(set) var revision = 0

    /// The keys' modes, which the console reads to know what a key sends.
    private(set) var applicationCursorKeys = false
    private(set) var bracketedPaste = false
    private(set) var cursorVisible = true

    /// The colours the answers to OSC 10 and 11 give, which the console sets
    /// from its screen's look: lipgloss picks its light or dark colours by
    /// the background.
    var foregroundColor = RGB(red: 0xCC, green: 0xCC, blue: 0xCC)
    var backgroundColor = RGB(red: 0, green: 0, blue: 0)

    private var grid: [[Cell]]
    /// The primary screen's grid while the alternate screen shows.
    private var primaryGrid: [[Cell]]?
    private var row = 0
    private var column = 0
    /// The last column has been written, and the next character goes on the
    /// next line: xterm's way, so that a full row does not scroll before
    /// there is anything to put under it.
    private var pendingWrap = false
    /// The scroll region, rows `top` to `bottom`.
    private var top = 0
    private var bottom: Int
    private var style = Style()
    private var saved: SavedCursor?
    private var savedForAlternate: SavedCursor?
    private var autowrap = true
    private var originMode = false
    private var insertMode = false
    /// G0 is DEC's line-drawing set, as ESC ( 0 chooses.
    private var graphics = false
    /// For REP, which repeats it.
    private var lastPrinted: Unicode.Scalar?

    private var replies: [UInt8] = []

    private var state = State.ground
    private var parameters: [UInt8] = []
    private var intermediates: [UInt8] = []
    private var stringData: [UInt8] = []
    private var stringIsCommand = false
    private var pending: [UInt8] = []
    private var pendingNeeds = 0

    init(columns: Int = 80, rows: Int = 24) {
        self.columns = max(2, columns)
        self.rows = max(2, rows)
        bottom = self.rows - 1
        grid = Array(repeating: Array(repeating: Cell(text: " ", style: Style()), count: self.columns),
                     count: self.rows)
    }

    // MARK: - What the console reads

    /// The alternate screen shows, where a full-screen program draws.
    var usesAlternateScreen: Bool { primaryGrid != nil }

    var display: Display {
        let last: Int
        if usesAlternateScreen {
            last = rows - 1
        } else {
            last = max(row, grid.lastIndex { row in row.contains { !$0.isBlank } } ?? 0)
        }
        var shown: [[Run]] = []
        shown.reserveCapacity(last + 1)
        for index in 0...last {
            let cells = grid[index]
            var used = (cells.lastIndex { !$0.isBlank } ?? -1) + 1
            if index == row { used = max(used, column) }
            shown.append(Self.runs(cells[0..<used]))
        }
        let offset = grid[row][0..<column].reduce(0) { $0 + $1.text.utf16.count }
        return Display(rows: shown, cursor: cursorVisible ? Cursor(row: row, offset: offset) : nil)
    }

    /// Everything the console shows, without its styles: the saved lines and
    /// the rows, or only the rows on the alternate screen. A line that
    /// autowrap carried on to the next row is one line, as Terminal copies
    /// it.
    var text: String {
        var lines: [(text: String, wraps: Bool)] = []
        if !usesAlternateScreen {
            for (line, wraps) in zip(scrollback, scrollbackWraps) { lines.append((line.map(\.text).joined(), wraps)) }
        }
        for (index, row) in display.rows.enumerated() {
            let wraps = grid[index].last?.wraps == true
            let runs = wraps ? Self.runs(grid[index][...]) : row
            lines.append((runs.map(\.text).joined(), wraps))
        }
        var text = ""
        for (index, line) in lines.enumerated() {
            text += line.text
            if index < lines.count - 1, !line.wraps { text += "\n" }
        }
        return text
    }

    /// The cursor is at the start of an empty line.
    var atLineStart: Bool {
        column == 0 && !pendingWrap && grid[row].allSatisfy(\.isBlank)
    }

    /// The answers to what the program asked since the last call, to type
    /// back at it.
    mutating func takeReplies() -> [UInt8] {
        defer { replies = [] }
        return replies
    }

    // MARK: - Changes from outside

    mutating func feed(_ text: String) { feed(Array(text.utf8)) }

    mutating func feed(_ data: Data) { feed(Array(data)) }

    mutating func feed(_ bytes: [UInt8]) {
        for byte in bytes { consume(byte) }
        revision &+= 1
    }

    /// The console's screen changed size. Rows that no longer fit go into
    /// the saved lines from the top on the primary screen, after any blank
    /// ones under the cursor; a row that is too long is cut.
    mutating func resize(columns newColumns: Int, rows newRows: Int) {
        let newColumns = max(2, newColumns)
        let newRows = max(2, newRows)
        guard newColumns != columns || newRows != rows else { return }
        var cursorRow = row
        if let primary = primaryGrid {
            var primaryRow = savedForAlternate?.row ?? 0
            primaryGrid = fitted(primary, columns: newColumns, rows: newRows, cursorRow: &primaryRow, saving: true)
            savedForAlternate?.row = primaryRow
            grid = fitted(grid, columns: newColumns, rows: newRows, cursorRow: &cursorRow, saving: false)
        } else {
            grid = fitted(grid, columns: newColumns, rows: newRows, cursorRow: &cursorRow, saving: true)
        }
        columns = newColumns
        rows = newRows
        top = 0
        bottom = rows - 1
        row = min(cursorRow, rows - 1)
        column = min(column, columns - 1)
        pendingWrap = false
        revision &+= 1
    }

    /// The program has exited: back to the primary screen, which holds the
    /// record, and the modes a program sets put back, so that a program that
    /// died on the alternate screen leaves the console as it found it.
    mutating func programExited() {
        if usesAlternateScreen { leaveAlternate(restoringCursor: true) }
        style = Style()
        top = 0
        bottom = rows - 1
        cursorVisible = true
        applicationCursorKeys = false
        bracketedPaste = false
        autowrap = true
        originMode = false
        insertMode = false
        graphics = false
        revision &+= 1
    }

    // MARK: - The parser

    private mutating func consume(_ byte: UInt8) {
        switch state {
        case .ground: ground(byte)
        case .escape: escape(byte)
        case .escapeIntermediate: escapeIntermediate(byte)
        case .csi: csi(byte)
        case .string:
            // An OSC (a window title, a link, a question about a colour), a
            // DCS, and their kind, up to BEL or ST.
            switch byte {
            case 0x07: endString(terminator: [0x07])
            case 0x1B: state = .stringEscape
            case 0x18, 0x1A: state = .ground
            default:
                if stringIsCommand, stringData.count < 4096 { stringData.append(byte) }
            }
        case .stringEscape:
            if byte == 0x5C {
                endString(terminator: [0x1B, 0x5C])
            } else {
                // An escape that is not ST ends the string unread and starts
                // a sequence of its own.
                state = .escape
                escape(byte)
            }
        }
    }

    private mutating func ground(_ byte: UInt8) {
        if pendingNeeds > 0 {
            if byte & 0xC0 == 0x80 {
                pending.append(byte)
                pendingNeeds -= 1
                if pendingNeeds == 0 {
                    print(String(decoding: pending, as: UTF8.self).unicodeScalars.first ?? "\u{FFFD}")
                    pending = []
                }
                return
            }
            // A character cut short: the replacement, then this byte afresh.
            print("\u{FFFD}")
            pending = []
            pendingNeeds = 0
        }
        switch byte {
        case 0x1B: state = .escape
        case 0x00..<0x20: control(byte)
        case 0x7F: break
        case 0x80..<0xC0, 0xF8...: print("\u{FFFD}")
        case 0xC0..<0xE0: begin(byte, needs: 1)
        case 0xE0..<0xF0: begin(byte, needs: 2)
        case 0xF0..<0xF8: begin(byte, needs: 3)
        default: print(Unicode.Scalar(byte))
        }
    }

    private mutating func begin(_ byte: UInt8, needs: Int) {
        pending = [byte]
        pendingNeeds = needs
    }

    private mutating func control(_ byte: UInt8) {
        switch byte {
        case 0x0A, 0x0B, 0x0C:
            // A line feed goes down and keeps the column: the terminal turns
            // a program's "\n" into "\r\n" itself, unless the program has
            // turned that off, as bubbletea does.
            lineFeed()
        case 0x0D:
            column = 0
            pendingWrap = false
        case 0x08:
            column = max(0, column - 1)
            pendingWrap = false
        case 0x09:
            tab(forward: 1)
        default:
            break  // the bell, the shifts, and the rest
        }
    }

    private mutating func escape(_ byte: UInt8) {
        state = .ground
        switch byte {
        case 0x5B:  // [
            parameters = []
            intermediates = []
            state = .csi
        case 0x5D:  // ]
            stringData = []
            stringIsCommand = true
            state = .string
        case 0x50, 0x58, 0x5E, 0x5F:  // P X ^ _
            stringData = []
            stringIsCommand = false
            state = .string
        case 0x20...0x2F:
            intermediates = [byte]
            state = .escapeIntermediate
        case 0x37: saveCursor()  // 7
        case 0x38: restoreCursor()  // 8
        case 0x44: lineFeed()  // D
        case 0x45:  // E
            column = 0
            lineFeed()
        case 0x4D: reverseIndex()  // M
        case 0x63: reset()  // c
        case 0x1B: state = .escape
        default:
            break  // the keypad's modes, a tab stop, a stray ST
        }
    }

    private mutating func escapeIntermediate(_ byte: UInt8) {
        switch byte {
        case 0x20...0x2F:
            intermediates.append(byte)
        case 0x30...0x7E:
            // ESC ( 0 and ESC ( B choose G0's set; the rest of their kind
            // name sets the console has no use for.
            if intermediates == [0x28] { graphics = byte == 0x30 }
            state = .ground
        case 0x1B:
            state = .escape
        case 0x00..<0x20:
            control(byte)
        default:
            state = .ground
        }
    }

    private mutating func csi(_ byte: UInt8) {
        switch byte {
        case 0x30...0x3F:
            parameters.append(byte)
        case 0x20...0x2F:
            intermediates.append(byte)
        case 0x40...0x7E:
            state = .ground
            perform(byte)
        case 0x1B:
            state = .escape
        case 0x18, 0x1A:
            state = .ground
        case 0x00..<0x20:
            // A control character inside a sequence still does what it does.
            control(byte)
        default:
            break
        }
    }

    private mutating func endString(terminator: [UInt8]) {
        state = .ground
        guard stringIsCommand else { return }
        // OSC 10 and 11 with "?" ask for the colours; the answer ends as the
        // question did.
        let command = String(decoding: stringData, as: UTF8.self)
        let asked: RGB? = switch command {
        case "10;?": foregroundColor
        case "11;?": backgroundColor
        default: nil
        }
        guard let asked else { return }
        func hex(_ value: UInt8) -> String { String(format: "%04x", Int(value) * 257) }
        reply("\u{1B}]\(command.prefix(2));rgb:\(hex(asked.red))/\(hex(asked.green))/\(hex(asked.blue))",
              then: terminator)
    }

    private mutating func reply(_ text: String, then terminator: [UInt8] = []) {
        replies += Array(text.utf8) + terminator
    }

    // MARK: - CSI

    private mutating func perform(_ final: UInt8) {
        let marker = parameters.first.flatMap { (0x3C...0x3F).contains($0) ? $0 : nil }
        let body = String(decoding: marker == nil ? parameters[...] : parameters.dropFirst(), as: UTF8.self)
        let numbers = body.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }
        func number(_ index: Int, _ fallback: Int) -> Int {
            index < numbers.count ? (numbers[index] ?? fallback) : fallback
        }
        /// A count: 0 and none are 1.
        func count(_ index: Int = 0) -> Int { max(1, number(index, 1)) }

        if !intermediates.isEmpty {
            switch (marker, intermediates, final) {
            case (0x3F, [0x24], 0x70):  // CSI ? Ps $ p: DECRQM
                let mode = number(0, 0)
                let status = privateMode(mode).map { $0 ? 1 : 2 } ?? 0
                reply("\u{1B}[?\(mode);\(status)$y")
            case (nil, [0x24], 0x70):
                reply("\u{1B}[\(number(0, 0));0$y")
            case (nil, [0x21], 0x70):  // CSI ! p: DECSTR
                softReset()
            default:
                break  // the cursor's shape, and the rest
            }
            return
        }

        switch marker {
        case 0x3F:  // ?
            switch final {
            case 0x68, 0x6C:  // h l
                for mode in numbers.compactMap({ $0 }) { setPrivateMode(mode, final == 0x68) }
            case 0x6E where number(0, 0) == 6:  // n
                reply("\u{1B}[?\(reportedRow);\(column + 1)R")
            case 0x4A: eraseDisplay(number(0, 0))  // J
            case 0x4B: eraseLine(number(0, 0))  // K
            default: break  // kitty's keyboard query, tab stops
            }
            return
        case 0x3E:  // >
            if final == 0x63, number(0, 0) == 0 { reply("\u{1B}[>1;10;0c") }  // c: DA2
            return  // modifyOtherKeys, kitty's keyboard flags, and the rest
        case .some:
            return
        case nil:
            break
        }

        switch final {
        case 0x40: insertCharacters(count())  // @
        case 0x41: cursorUp(count())  // A
        case 0x42, 0x65: cursorDown(count())  // B e
        case 0x43, 0x61: cursorForward(count())  // C a
        case 0x44: cursorBack(count())  // D
        case 0x45:  // E
            cursorDown(count())
            column = 0
        case 0x46:  // F
            cursorUp(count())
            column = 0
        case 0x47, 0x60:  // G `
            column = min(columns - 1, count() - 1)
            pendingWrap = false
        case 0x48, 0x66: moveTo(row: count(0) - 1, column: count(1) - 1)  // H f
        case 0x49: tab(forward: count())  // I
        case 0x4A: eraseDisplay(number(0, 0))  // J
        case 0x4B: eraseLine(number(0, 0))  // K
        case 0x4C: insertLines(count())  // L
        case 0x4D: deleteLines(count())  // M
        case 0x50: deleteCharacters(count())  // P
        case 0x53 where numbers.count <= 1: scrollUp(count())  // S
        case 0x54 where numbers.count <= 1: scrollDown(count())  // T
        case 0x58: eraseCharacters(count())  // X
        case 0x5A: tab(forward: -count())  // Z
        case 0x62:  // b: REP
            if let lastPrinted { for _ in 0..<min(count(), columns * rows) { print(lastPrinted) } }
        case 0x63 where number(0, 0) == 0:  // c: DA1, a VT220 with colour
            reply("\u{1B}[?62;22c")
        case 0x64: moveTo(row: count() - 1, column: column)  // d
        case 0x68, 0x6C:  // h l: IRM is the one ANSI mode with any use here
            if numbers.contains(4) { insertMode = final == 0x68 }
        case 0x6D: sgr(body)  // m
        case 0x6E:  // n
            switch number(0, 0) {
            case 5: reply("\u{1B}[0n")
            case 6: reply("\u{1B}[\(reportedRow);\(column + 1)R")
            default: break
            }
        case 0x72: setMargins(number(0, 1), number(1, rows))  // r
        case 0x73 where numbers.allSatisfy({ $0 == nil }): saveCursor()  // s
        case 0x74 where number(0, 0) == 18:  // t: the size, in characters
            reply("\u{1B}[8;\(rows);\(columns)t")
        case 0x75: restoreCursor()  // u
        default:
            break
        }
    }

    /// The cursor's row as a report gives it: from 1, and from the top of the
    /// scroll region in origin mode.
    private var reportedRow: Int { row - (originMode ? top : 0) + 1 }

    /// A private mode's setting, or nil for one the console does not keep.
    private func privateMode(_ mode: Int) -> Bool? {
        switch mode {
        case 1: applicationCursorKeys
        case 6: originMode
        case 7: autowrap
        case 25: cursorVisible
        case 47, 1047, 1049: usesAlternateScreen
        case 2004: bracketedPaste
        default: nil
        }
    }

    private mutating func setPrivateMode(_ mode: Int, _ on: Bool) {
        switch mode {
        case 1: applicationCursorKeys = on
        case 6:
            originMode = on
            moveTo(row: 0, column: 0)
        case 7:
            autowrap = on
            if !on { pendingWrap = false }
        case 25: cursorVisible = on
        case 47, 1047:
            if on { enterAlternate() } else { leaveAlternate(restoringCursor: false) }
        case 1048:
            if on { saveCursor() } else { restoreCursor() }
        case 1049:
            if on {
                savedForAlternate = currentCursor
                enterAlternate()
            } else {
                leaveAlternate(restoringCursor: true)
            }
        case 2004: bracketedPaste = on
        default:
            break  // the mouse, focus events, synchronized output, and the rest
        }
    }

    private mutating func sgr(_ body: String) {
        let groups = body.split(separator: ";", omittingEmptySubsequences: false)
        func int(_ index: Int) -> Int? { index < groups.count ? Int(groups[index]) : nil }
        var i = 0
        while i < groups.count {
            let group = groups[i]
            if group.contains(":") {
                // The colon form: 38:5:N, 38:2::R:G:B, and 4:3 for a curly
                // underline.
                let parts = group.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
                switch parts.first ?? nil {
                case 38, 48:
                    var value: UInt8?
                    if parts.count >= 3, parts[1] == 5, let n = parts[2], (0...255).contains(n) {
                        value = UInt8(n)
                    } else if parts.count >= 5, parts[1] == 2,
                              let r = parts[parts.count - 3], let g = parts[parts.count - 2], let b = parts[parts.count - 1] {
                        value = Self.nearest(red: r, green: g, blue: b)
                    }
                    if let value {
                        if parts.first == 38 { style.color = value } else { style.background = value }
                    }
                case 4:
                    style.underline = parts.count < 2 || parts[1] != 0
                default:
                    break
                }
                i += 1
                continue
            }
            let code = Int(group) ?? 0
            switch code {
            case 0: style = Style()
            case 1: style.bold = true
            case 2: style.dim = true
            case 4, 21: style.underline = true
            case 7: style.inverse = true
            case 22:
                style.bold = false
                style.dim = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.color = UInt8(code - 30)
            case 39: style.color = nil
            case 40...47: style.background = UInt8(code - 40)
            case 49: style.background = nil
            case 90...97: style.color = UInt8(code - 90 + 8)
            case 100...107: style.background = UInt8(code - 100 + 8)
            case 38, 48, 58:
                // 38;5;N and 38;2;R;G;B. The arguments are skipped, never
                // read as codes of their own; 58, the underline's colour, is
                // read only to skip them.
                let kind = int(i + 1)
                var value: UInt8?
                if kind == 5 {
                    if let n = int(i + 2), (0...255).contains(n) { value = UInt8(n) }
                    i += 2
                } else if kind == 2 {
                    if let r = int(i + 2), let g = int(i + 3), let b = int(i + 4) {
                        value = Self.nearest(red: r, green: g, blue: b)
                    }
                    i += 4
                }
                if let value {
                    if code == 38 { style.color = value } else if code == 48 { style.background = value }
                }
            default:
                break  // italics, blinking, struck through, hidden
            }
            i += 1
        }
    }

    // MARK: - The grid

    /// An erased cell: a space on the current background, as xterm-256color
    /// promises (bce).
    private var blank: Cell { Cell(text: " ", style: Style(background: style.background)) }

    private var blankRow: [Cell] { Array(repeating: blank, count: columns) }

    private mutating func print(_ input: Unicode.Scalar) {
        var scalar = input
        if graphics, let drawn = Self.lineDrawing[scalar] { scalar = drawn }
        let width = Self.width(of: scalar)
        if width == 0 {
            combine(scalar)
            return
        }
        if pendingWrap {
            pendingWrap = false
            grid[row][columns - 1].wraps = true
            column = 0
            lineFeed()
        }
        if width == 2, column == columns - 1 {
            if autowrap {
                grid[row][column] = blank
                grid[row][column].wraps = true
                column = 0
                lineFeed()
            } else {
                column -= 1
            }
        }
        if insertMode {
            grid[row].insert(contentsOf: Array(repeating: blank, count: width), at: column)
            grid[row].removeLast(width)
        }
        clearWide(at: column)
        if width == 2 { clearWide(at: column + 1) }
        grid[row][column] = Cell(text: String(scalar), style: style, width: UInt8(width))
        if width == 2 { grid[row][column + 1] = Cell(text: "", style: style, width: 0) }
        lastPrinted = scalar
        column += width
        if column >= columns {
            column = columns - 1
            pendingWrap = autowrap
        }
    }

    /// A combining mark goes on the character before it.
    private mutating func combine(_ scalar: Unicode.Scalar) {
        var target = pendingWrap ? column : column - 1
        guard target >= 0 else { return }
        if grid[row][target].width == 0, target > 0 { target -= 1 }
        grid[row][target].text.unicodeScalars.append(scalar)
    }

    /// Writing over half of a wide character blanks its other half.
    private mutating func clearWide(at index: Int) {
        guard index < columns else { return }
        let cell = grid[row][index]
        if cell.width == 0, index > 0 { grid[row][index - 1] = blank }
        if cell.width == 2, index + 1 < columns { grid[row][index + 1] = blank }
    }

    private mutating func lineFeed() {
        pendingWrap = false
        if row == bottom {
            scrollUp(1)
        } else if row < rows - 1 {
            row += 1
        }
    }

    private mutating func reverseIndex() {
        pendingWrap = false
        if row == top {
            scrollDown(1)
        } else if row > 0 {
            row -= 1
        }
    }

    /// The scroll region's rows move up. What leaves the top of the primary
    /// screen is saved, as in xterm, when the region starts at the top.
    private mutating func scrollUp(_ n: Int) {
        let saving = !usesAlternateScreen && top == 0
        for _ in 0..<min(n, bottom - top + 1) {
            let gone = grid.remove(at: top)
            if saving { save(gone) }
            grid.insert(blankRow, at: bottom)
        }
    }

    private mutating func scrollDown(_ n: Int) {
        for _ in 0..<min(n, bottom - top + 1) {
            grid.remove(at: bottom)
            grid.insert(blankRow, at: top)
        }
    }

    private mutating func insertLines(_ n: Int) {
        guard (top...bottom).contains(row) else { return }
        for _ in 0..<min(n, bottom - row + 1) {
            grid.remove(at: bottom)
            grid.insert(blankRow, at: row)
        }
        column = 0
        pendingWrap = false
    }

    private mutating func deleteLines(_ n: Int) {
        guard (top...bottom).contains(row) else { return }
        for _ in 0..<min(n, bottom - row + 1) {
            grid.remove(at: row)
            grid.insert(blankRow, at: bottom)
        }
        column = 0
        pendingWrap = false
    }

    private mutating func insertCharacters(_ n: Int) {
        let n = min(n, columns - column)
        // A wide character cut in two, here or where the row ends, goes.
        clearWide(at: column)
        grid[row].insert(contentsOf: Array(repeating: blank, count: n), at: column)
        grid[row].removeLast(n)
        if grid[row][columns - 1].width == 2 { grid[row][columns - 1] = blank }
        pendingWrap = false
    }

    private mutating func deleteCharacters(_ n: Int) {
        let n = min(n, columns - column)
        clearWide(at: column)
        if column + n < columns, grid[row][column + n].width == 0 { grid[row][column + n] = blank }
        grid[row].removeSubrange(column..<(column + n))
        grid[row].append(contentsOf: Array(repeating: blank, count: n))
        pendingWrap = false
    }

    private mutating func eraseCharacters(_ n: Int) {
        let cell = blank
        for index in column..<min(columns, column + n) { grid[row][index] = cell }
        pendingWrap = false
    }

    private mutating func eraseLine(_ mode: Int) {
        let cell = blank
        let range: Range<Int>
        switch mode {
        case 0: range = column..<columns
        case 1: range = 0..<(column + 1)
        case 2: range = 0..<columns
        default: return
        }
        for index in range { grid[row][index] = cell }
        pendingWrap = false
    }

    private mutating func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseLine(0)
            for index in (row + 1)..<rows { grid[index] = blankRow }
        case 1:
            eraseLine(1)
            for index in 0..<row { grid[index] = blankRow }
        case 2:
            for index in 0..<rows { grid[index] = blankRow }
            pendingWrap = false
        default:
            break  // 3, the saved lines: they are the record
        }
    }

    private mutating func moveTo(row newRow: Int, column newColumn: Int) {
        if originMode {
            row = min(bottom, max(top, top + newRow))
        } else {
            row = min(rows - 1, max(0, newRow))
        }
        column = min(columns - 1, max(0, newColumn))
        pendingWrap = false
    }

    private mutating func cursorUp(_ n: Int) {
        row = max(row >= top ? top : 0, row - n)
        pendingWrap = false
    }

    private mutating func cursorDown(_ n: Int) {
        row = min(row <= bottom ? bottom : rows - 1, row + n)
        pendingWrap = false
    }

    private mutating func cursorForward(_ n: Int) {
        column = min(columns - 1, column + n)
        pendingWrap = false
    }

    private mutating func cursorBack(_ n: Int) {
        column = max(0, column - n)
        pendingWrap = false
    }

    /// To the next stop, every eight columns, or back by stops for a
    /// negative count.
    private mutating func tab(forward n: Int) {
        if n > 0 {
            column = min(columns - 1, (column / 8 + n) * 8)
        } else {
            column = max(0, ((column + 7) / 8 + n) * 8)
        }
        pendingWrap = false
    }

    private mutating func setMargins(_ first: Int, _ last: Int) {
        let first = max(1, first)
        let last = min(rows, last == 0 ? rows : last)
        guard first < last else { return }
        top = first - 1
        bottom = last - 1
        moveTo(row: 0, column: 0)
    }

    private var currentCursor: SavedCursor {
        SavedCursor(row: row, column: column, style: style, pendingWrap: pendingWrap,
                    originMode: originMode, graphics: graphics)
    }

    private mutating func saveCursor() {
        saved = currentCursor
    }

    private mutating func restoreCursor() {
        restore(saved ?? SavedCursor(row: 0, column: 0, style: Style(), pendingWrap: false,
                                     originMode: false, graphics: false))
    }

    private mutating func restore(_ cursor: SavedCursor) {
        row = min(rows - 1, cursor.row)
        column = min(columns - 1, cursor.column)
        style = cursor.style
        pendingWrap = cursor.pendingWrap
        originMode = cursor.originMode
        graphics = cursor.graphics
    }

    private mutating func enterAlternate() {
        guard primaryGrid == nil else { return }
        primaryGrid = grid
        grid = Array(repeating: Array(repeating: Cell(text: " ", style: Style()), count: columns), count: rows)
        top = 0
        bottom = rows - 1
        pendingWrap = false
    }

    private mutating func leaveAlternate(restoringCursor: Bool) {
        guard let primary = primaryGrid else { return }
        grid = primary
        primaryGrid = nil
        top = 0
        bottom = rows - 1
        pendingWrap = false
        if restoringCursor, let savedForAlternate { restore(savedForAlternate) }
    }

    /// RIS. The saved lines stay: they are the record.
    private mutating func reset() {
        if usesAlternateScreen { leaveAlternate(restoringCursor: false) }
        style = Style()
        softReset()
        grid = Array(repeating: blankRow, count: rows)
        saved = nil
        savedForAlternate = nil
        bracketedPaste = false
        row = 0
        column = 0
    }

    /// DECSTR.
    private mutating func softReset() {
        cursorVisible = true
        insertMode = false
        originMode = false
        autowrap = true
        applicationCursorKeys = false
        graphics = false
        style = Style()
        top = 0
        bottom = rows - 1
        pendingWrap = false
        saved = nil
    }

    /// GRID made `newColumns` × `newRows`. Rows past the bottom go first when
    /// they are blank and under the cursor, then rows from the top, into the
    /// saved lines when `saving`.
    private mutating func fitted(_ grid: [[Cell]], columns newColumns: Int, rows newRows: Int,
                                 cursorRow: inout Int, saving: Bool) -> [[Cell]] {
        var grid = grid
        var excess = grid.count - newRows
        while excess > 0, grid.count - 1 > cursorRow, grid.last?.allSatisfy(\.isBlank) == true {
            grid.removeLast()
            excess -= 1
        }
        if excess > 0 {
            for gone in grid.prefix(excess) where saving { save(gone) }
            grid.removeFirst(excess)
            cursorRow = max(0, cursorRow - excess)
        }
        let empty = Cell(text: " ", style: Style())
        while grid.count < newRows { grid.append(Array(repeating: empty, count: newColumns)) }
        return grid.map { cells in
            if cells.count >= newColumns {
                var cut = Array(cells.prefix(newColumns))
                if cut.last?.width == 2 { cut[newColumns - 1] = empty }
                return cut
            }
            return cells + Array(repeating: empty, count: newColumns - cells.count)
        }
    }

    /// A row that has left the screen, into the saved lines: all of it when
    /// the line runs on, spaces at the wrap included.
    private mutating func save(_ cells: [Cell]) {
        let wraps = cells.last?.wraps == true
        scrollback.append(Self.runs(wraps ? cells[...] : Self.trimmed(cells)))
        scrollbackWraps.append(wraps)
    }

    private static func trimmed(_ cells: [Cell]) -> ArraySlice<Cell> {
        cells[0..<((cells.lastIndex { !$0.isBlank } ?? -1) + 1)]
    }

    private static func runs(_ cells: ArraySlice<Cell>) -> [Run] {
        var runs: [Run] = []
        for cell in cells where cell.width > 0 {
            if runs.last?.style == cell.style {
                runs[runs.count - 1].text += cell.text
            } else {
                runs.append(Run(text: cell.text, style: cell.style))
            }
        }
        return runs
    }

    // MARK: - Characters and colours

    /// The columns a character takes, as go-runewidth counts them for
    /// bubbletea's layout: 0 for a combining mark, 2 for a wide East Asian
    /// character or an emoji that shows as one, 1 for the rest.
    static func width(of scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        if value < 0x300 { return 1 }
        if value == 0x200D || (0xFE00...0xFE0F).contains(value) || (0xE0100...0xE01EF).contains(value) { return 0 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark: return 0
        default: break
        }
        if scalar.properties.isEmojiPresentation { return 2 }
        let wide: [ClosedRange<UInt32>] = [
            0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
            0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
            0xFFE0...0xFFE6, 0x20000...0x3FFFD,
        ]
        return wide.contains { $0.contains(value) } ? 2 : 1
    }

    /// DEC's line-drawing set, for G0 after ESC ( 0.
    private static let lineDrawing: [Unicode.Scalar: Unicode.Scalar] = {
        let from = "`abcdefghijklmnopqrstuvwxyz{|}~".unicodeScalars
        let to = "◆▒␉␌␍␊°±␤␋┘┐┌└┼⎺⎻─⎼⎽├┤┴┬│≤≥π≠£·".unicodeScalars
        return Dictionary(uniqueKeysWithValues: zip(from, to))
    }()

    /// The xterm colour of INDEX.
    static func rgb(of index: UInt8) -> RGB {
        let base: [(UInt8, UInt8, UInt8)] = [
            (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0), (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
            (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0), (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
        ]
        switch index {
        case 0..<16:
            let (r, g, b) = base[Int(index)]
            return RGB(red: r, green: g, blue: b)
        case 16..<232:
            let n = Int(index) - 16
            func level(_ step: Int) -> UInt8 { step == 0 ? 0 : UInt8(55 + step * 40) }
            return RGB(red: level(n / 36), green: level(n / 6 % 6), blue: level(n % 6))
        default:
            let grey = UInt8(8 + (Int(index) - 232) * 10)
            return RGB(red: grey, green: grey, blue: grey)
        }
    }

    /// The xterm colour nearest a 24-bit one: of the cube, or of the greys.
    static func nearest(red: Int, green: Int, blue: Int) -> UInt8 {
        let (r, g, b) = (min(255, max(0, red)), min(255, max(0, green)), min(255, max(0, blue)))
        func step(_ v: Int) -> Int { v < 48 ? 0 : v < 115 ? 1 : (v - 35) / 40 }
        func level(_ s: Int) -> Int { s == 0 ? 0 : 55 + s * 40 }
        func distance(_ x: Int, _ y: Int, _ z: Int) -> Int {
            (x - r) * (x - r) + (y - g) * (y - g) + (z - b) * (z - b)
        }
        let (sr, sg, sb) = (step(r), step(g), step(b))
        let cube = 16 + 36 * sr + 6 * sg + sb
        let cubeDistance = distance(level(sr), level(sg), level(sb))
        let average = (r + g + b) / 3
        let greyStep = min(23, max(0, (average - 3) / 10))
        let grey = 8 + greyStep * 10
        return distance(grey, grey, grey) < cubeDistance ? UInt8(232 + greyStep) : UInt8(cube)
    }
}
