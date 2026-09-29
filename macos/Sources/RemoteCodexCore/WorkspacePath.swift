import Foundation

/// Breadcrumbs contain only workspace-relative paths. The server additionally
/// validates canonical paths (including symlinks) against the workspace root.
public enum WorkspacePath {
    public struct Crumb: Equatable, Identifiable {
        public let label: String
        public let path: String
        public var id: String { path }
    }
    public static func normalize(_ value: String) throws -> String {
        guard !value.hasPrefix("/"), !value.contains("\\"), !value.contains(":"), !value.contains("\0") else { throw APIError("Use a path inside this workspace.") }
        var parts: [Substring] = []
        for part in value.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard !parts.isEmpty else { throw APIError("Cannot navigate above the workspace root.") }
                parts.removeLast()
            } else { parts.append(part) }
        }
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }
    public static func breadcrumbs(_ directory: String, rootLabel: String) throws -> [Crumb] {
        let path = try normalize(directory)
        var result = [Crumb(label: rootLabel, path: ".")]
        if path == "." { return result }
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            parts.append(part); result.append(Crumb(label: String(part), path: parts.joined(separator: "/")))
        }
        return result
    }
    public static func parent(_ directory: String) throws -> String {
        let path = try normalize(directory)
        return try normalize((path as NSString).deletingLastPathComponent)
    }
}
