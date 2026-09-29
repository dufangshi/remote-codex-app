import Foundation

/// Seed once without replaying old events. Polls can overlap and reorder events;
/// acknowledgement happens only after the OS accepted a notification request.
public struct NotificationCursor {
    private var seen: Set<String> = []
    private var seeded = false
    public init() {}
    public mutating func pending(_ events: [WorkbenchNotification]) -> [WorkbenchNotification] {
        if !seeded { seen = Set(events.map(\.id)); seeded = true; return [] }
        return events.reversed().filter { !seen.contains($0.id) }
    }
    public mutating func acknowledge(_ id: String) { seen.insert(id) }
    public static func destination(_ href: String, origin: URL) -> (device: String, thread: String)? {
        guard let url = URL(string: href, relativeTo: origin)?.absoluteURL,
              BrowserPolicy.sameOrigin(url, origin), url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 4, parts[0] == "devices", parts[2] == "threads",
              UUID(uuidString: String(parts[1])) != nil, UUID(uuidString: String(parts[3])) != nil else { return nil }
        return (String(parts[1]), String(parts[3]))
    }
}
