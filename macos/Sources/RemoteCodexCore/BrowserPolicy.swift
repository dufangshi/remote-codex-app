import Foundation

/// Keep native navigation and restoration inside the configured relay origin.
public enum BrowserPolicy {
    public static func sameOrigin(_ url: URL, _ origin: URL) -> Bool {
        func port(_ value: URL) -> Int? { value.port ?? (value.scheme == "https" ? 443 : value.scheme == "http" ? 80 : nil) }
        return url.user == nil && url.password == nil && url.scheme == origin.scheme && url.host == origin.host && port(url) == port(origin)
    }
    public static func restoredURL(_ path: String?, origin: URL) -> URL {
        guard let path, path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: path, relativeTo: origin)?.absoluteURL, sameOrigin(url, origin),
              !url.path.split(separator: "/").contains("..") else { return origin.appendingPathComponent("relay-devices") }
        return url
    }
    public static func rememberedPath(_ url: URL, origin: URL) -> String? {
        guard sameOrigin(url, origin), url.path.hasPrefix("/devices/") || url.path == "/relay-devices" else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.queryItems = parts.queryItems?.filter { $0.name == "workspaceId" && UUID(uuidString: $0.value ?? "") != nil }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
}
