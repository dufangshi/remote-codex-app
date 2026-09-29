import Foundation

/// Block parsing for the SwiftUI renderer; no HTML or JavaScript execution.
public enum MarkdownBlock: Equatable {
    case paragraph(String), heading(Int, String), code(String, String)
    case list(String, String), quote(String), rule
    case table([String], [[String]])
}
public enum MarkdownParser {
    public static func blocks(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [MarkdownBlock] = [], paragraph: [String] = []
        var i = 0
        func flush() { if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] } }
        while i < lines.count {
            let line = lines[i], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush(); let fence = trimmed.first!; let count = trimmed.prefix { $0 == fence }.count
                let marker = String(repeating: String(fence), count: count); let language = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces); i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(marker) { code.append(lines[i]); i += 1 }
                result.append(.code(language, code.joined(separator: "\n")))
            } else if i + 1 < lines.count, line.contains("|"), isSeparator(lines[i + 1]) {
                flush(); let header = cells(line); i += 2; var rows: [[String]] = []
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    let row = cells(lines[i]); rows.append(Array((row + Array(repeating: "", count: header.count)).prefix(header.count))); i += 1
                }
                result.append(.table(header, rows)); continue
            } else if i + 1 < lines.count, !trimmed.isEmpty, trimmed.range(of: "^(?:>|#|[-*+] |[0-9]+[.)] )", options: .regularExpression) == nil,
                      lines[i + 1].range(of: "^\\s*(?:={3,}|-{3,})\\s*$", options: .regularExpression) != nil {
                flush(); result.append(.heading(lines[i + 1].contains("=") ? 1 : 2, trimmed)); i += 1
            } else if trimmed.isEmpty { flush() }
            else if ["---", "***", "___"].contains(trimmed) { flush(); result.append(.rule) }
            else if trimmed.hasPrefix(">") {
                flush(); var quoted: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoted.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                result.append(.quote(quoted.joined(separator: "\n"))); continue
            }
            else if let range = trimmed.range(of: "^#{1,6} ", options: .regularExpression) {
                flush(); result.append(.heading(trimmed[range].count - 1, String(trimmed[range.upperBound...])))
            } else if let range = trimmed.range(of: "^(?:[-*+] |[0-9]+[.)] )", options: .regularExpression) {
                flush(); let marker = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                let content = String(trimmed[range.upperBound...])
                if content.hasPrefix("[ ] ") { result.append(.list("☐", String(content.dropFirst(4)))) }
                else if content.lowercased().hasPrefix("[x] ") { result.append(.list("☑", String(content.dropFirst(4)))) }
                else { result.append(.list(["-", "*", "+"].contains(marker) ? "•" : marker, content)) }
            } else { paragraph.append(line) }
            i += 1
        }
        flush(); return result
    }
    public static func cells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }; if s.hasSuffix("|") { s.removeLast() }
        var values: [String] = [], value = "", escaped = false, code = false
        for c in s {
            if escaped { if c != "|" { value.append("\\") }; value.append(c); escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "`" { code.toggle() }
            if c == "|", !code { values.append(value.trimmingCharacters(in: .whitespaces)); value = "" }
            else { value.append(c) }
        }
        if escaped { value.append("\\") }
        values.append(value.trimmingCharacters(in: .whitespaces)); return values
    }
    private static func isSeparator(_ line: String) -> Bool {
        let values = cells(line)
        return !values.isEmpty && values.allSatisfy { $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }
    }
}
