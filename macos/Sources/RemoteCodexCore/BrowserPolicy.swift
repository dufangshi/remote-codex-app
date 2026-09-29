import Foundation

/// Keeps notification and link destinations inside the configured relay origin.
public enum BrowserPolicy {
    public static func sameOrigin(_ url: URL, _ origin: URL) -> Bool {
        func port(_ value: URL) -> Int? { value.port ?? (value.scheme == "https" ? 443 : value.scheme == "http" ? 80 : nil) }
        return url.user == nil && url.password == nil && url.scheme == origin.scheme && url.host == origin.host && port(url) == port(origin)
    }
}
