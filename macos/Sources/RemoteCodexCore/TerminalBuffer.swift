import Foundation

/// Stateful VT text screen. Escape sequences can cross socket frames.
public struct TerminalBuffer {
    public private(set) var lines: [[Character]] = [[]]
    public private(set) var row = 0
    public private(set) var column = 0
    public private(set) var bracketedPaste = false
    public private(set) var cursorVisible = true
    public var columns = 100
    public var rows = 32
    private var escape = ""
    private var saved = (0, 0)
    private var primary: ([[Character]], Int, Int)?
    public init() {}
    public var text: String { lines.map { String($0) }.joined(separator: "\n") }
    public mutating func clear() { lines = [[]]; row = 0; column = 0; escape = "" }
    private mutating func ensure() {
        row = max(0, min(row, 4000)); column = max(0, min(column, max(1, columns) - 1))
        while lines.count <= row { lines.append([]) }
    }
    private mutating func newline() {
        row += 1; ensure()
        if primary != nil && lines.count > rows { lines.removeFirst(); row -= 1 }
        else if lines.count > 2000 { lines.removeFirst(lines.count - 2000); row = lines.count - 1 }
    }
    public mutating func feed(_ text: String) {
        for c in text {
            if !escape.isEmpty {
                escape.append(c)
                if escape.hasPrefix("\u{1b}]") {
                    if c == "\u{7}" || escape.hasSuffix("\u{1b}\\") { escape = "" }
                } else if escape.hasPrefix("\u{1b}[") {
                    if escape.count > 2, let scalar = c.unicodeScalars.first, scalar.value >= 0x40, scalar.value <= 0x7e {
                        control(String(escape.dropFirst(2))); escape = ""
                    }
                } else if escape.count == 2 {
                    if c == "7" { saved = (row, column) }
                    if c == "8" { (row, column) = saved; ensure() }
                    if c == "D" { newline() }
                    if c == "M" { row = max(0, row - 1) }
                    escape = ""
                }
                if escape.count > 4096 { escape = "" }
                continue
            }
            switch c {
            case "\u{1b}": escape = String(c)
            case "\r": column = 0
            case "\n": newline()
            case "\r\n": column = 0; newline()
            case "\u{8}", "\u{7f}": column = max(0, column - 1)
            case "\t": column = min(max(1, columns) - 1, (column / 8 + 1) * 8)
            default:
                if c.unicodeScalars.allSatisfy({ $0.value < 32 }) { continue }
                if column >= columns { column = 0; newline() }
                ensure()
                while lines[row].count <= column { lines[row].append(" ") }
                lines[row][column] = c; column += 1
            }
        }
    }
    private mutating func control(_ value: String) {
        guard let op = value.last else { return }
        let raw = String(value.dropLast())
        if raw.hasPrefix("?") {
            let flags = raw.dropFirst().split(separator: ";").compactMap { Int($0) }
            if flags.contains(2004) { bracketedPaste = op == "h" }
            if flags.contains(25) { cursorVisible = op != "l" }
            if flags.contains(1049) || flags.contains(1047) {
                if op == "h", primary == nil { primary = (lines, row, column); lines = [[]]; row = 0; column = 0 }
                else if op == "l", let original = primary { (lines, row, column) = original; primary = nil }
            }
            return
        }
        let p = raw.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        let n = max(1, p.first ?? 1), top = max(0, lines.count - rows)
        switch op {
        case "A": row = max(top, row - n)
        case "B": row += n
        case "C": column += n
        case "D": column -= n
        case "G": column = n - 1
        case "H", "f": row = top + n - 1; column = max(1, p.count > 1 ? p[1] : 1) - 1
        case "d": row = top + n - 1
        case "E": row += n; column = 0
        case "F": row = max(top, row - n); column = 0
        case "s": saved = (row, column)
        case "u": (row, column) = saved
        case "J":
            let mode = p.first ?? 0
            if mode == 2 || mode == 3 { lines = [[]]; row = 0; column = 0 }
            else if mode == 0 { ensure(); lines[row] = Array(lines[row].prefix(column)); if row + 1 < lines.count { lines.removeSubrange((row + 1)...) } }
        case "K":
            ensure()
            switch p.first ?? 0 {
            case 2: lines[row] = []
            case 1: for i in 0..<min(column + 1, lines[row].count) { lines[row][i] = " " }
            default: lines[row] = Array(lines[row].prefix(column))
            }
        case "P": ensure(); if column < lines[row].count { lines[row].removeSubrange(column..<min(lines[row].count, column + n)) }
        case "@": ensure(); while lines[row].count < column { lines[row].append(" ") }; lines[row].insert(contentsOf: repeatElement(" ", count: min(n, columns)), at: column)
        default: break
        }
        ensure()
    }
}
