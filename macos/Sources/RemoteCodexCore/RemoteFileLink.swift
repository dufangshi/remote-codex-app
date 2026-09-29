import Foundation

/// Resolve remote document links without ever asking macOS to open a file URL.
public enum RemoteFileLink {
    public static func path(_ raw: String, root: String, document: String? = nil) throws -> String {
        var value = raw
        if value.hasPrefix("file:") {
            guard let url = URL(string: value), url.host == nil || url.host == "" || url.host == "localhost" else { throw APIError("Remote file host is not supported.") }
            value = url.path
        } else {
            guard !value.contains("://"), !value.hasPrefix("//") else { throw APIError("Not a workspace file link.") }
            value = String(value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
            value = value.removingPercentEncoding ?? value
        }
        value = value.replacingOccurrences(of: "\\", with: "/")
        value = value.replacingOccurrences(of: ":\\d+(?::\\d+)?$", with: "", options: .regularExpression)
        let base = root.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.hasPrefix("/" + base + "/") { value = String(value.dropFirst(base.count + 2)) }
        else if value.hasPrefix(base + "/") { value = String(value.dropFirst(base.count + 1)) }
        else if value.hasPrefix("/") || value.range(of: "^[A-Za-z]:/", options: .regularExpression) != nil { throw APIError("This link is outside the selected remote workspace.") }
        else if let document { value = (document as NSString).deletingLastPathComponent + "/" + value }
        var parts: [String] = []
        for part in value.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { guard !parts.isEmpty else { throw APIError("This link leaves the remote workspace.") }; parts.removeLast() }
            else { parts.append(String(part)) }
        }
        guard !parts.isEmpty else { throw APIError("This link does not name a file.") }
        return parts.joined(separator: "/")
    }
}
