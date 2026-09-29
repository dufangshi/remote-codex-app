import Foundation

/// Lightweight lexical coloring, never a formatter: ranges address the original UTF-16 text.
public enum CodeSyntax {
    public enum Kind: Int, Sendable { case comment, string, number, keyword, type, function }
    public struct Token: Equatable, Sendable {
        public let range: NSRange
        public let kind: Kind
    }
    public static func language(_ path: String) -> String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "js", "jsx", "mjs", "cjs", "ts", "tsx": return "JavaScript / TypeScript"
        case "swift": return "Swift"
        case "rs": return "Rust"
        case "py", "pyi": return "Python"
        case "sh", "bash", "zsh": return "Shell"
        case "json", "jsonc": return "JSON"
        case "css", "scss", "less": return "CSS"
        case "html", "htm", "xml", "svg", "vue", "svelte": return "Markup"
        case "yaml", "yml", "toml": return "Configuration"
        case "sql": return "SQL"
        case "c", "h", "cpp", "hpp", "cc", "java", "kt", "go", "cs": return "Code"
        default: return nil
        }
    }
    public static let maximumUTF16Length = 500_000
    public static func tokens(_ text: String, path: String) -> [Token] {
        guard let language = language(path), text.utf16.count <= maximumUTF16Length else { return [] }
        let hashComments = ["Python", "Shell", "Configuration"].contains(language)
        let comments = language == "Markup" ? #"<!--[\s\S]*?(?:-->|$)"# : language == "SQL" ? #"--[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"# : hashComments ? #"#[^\r\n]*"# : #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        let strings = #"\"\"\"[\s\S]*?(?:\"\"\"|$)|'''[\s\S]*?(?:'''|$)|\"(?:\\[\s\S]|[^\"\\])*?(?:\"|$)|'(?:\\[\s\S]|[^'\\\r\n])*?(?:'|$)|`(?:\\[\s\S]|[^`\\])*?(?:`|$)"#
        let keywords = "as async await break case catch class const continue def default defer delete do else enum export extends false finally fn for from func function guard if impl import in init interface is let match module mut namespace new nil none null of override package private protected public raise readonly return self static struct super switch throw throws trait true try type typeof undefined use var void where while with yield select insert update delete into values create table join on and or not"
        let patterns = [comments, strings, #"\b(?:0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#,
                        "\\b(?:" + keywords.components(separatedBy: " ").joined(separator: "|") + ")\\b",
                        #"\b[A-Z][A-Za-z0-9_]*\b"#, #"\b[a-zA-Z_$][\w$]*(?=\s*\()"#]
        guard let regex = try? NSRegularExpression(pattern: patterns.map { "(" + $0 + ")" }.joined(separator: "|"), options: language == "SQL" ? [.caseInsensitive] : []) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            for index in 1...patterns.count where match.range(at: index).location != NSNotFound {
                return Token(range: match.range, kind: Kind(rawValue: index - 1)!)
            }
            return nil
        }
    }
}
