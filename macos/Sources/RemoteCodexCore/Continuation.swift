import Foundation

/// Mirrors the Rust stream route, while keeping every chunk in its original ACL scope.
struct Continuation {
    let prefix: String
    private var token: String?
    private var index: UInt64 = 1
    init(path: String) {
        let parts = path.split(separator: "?", maxSplits: 1)[0].split(separator: "/")
        prefix = parts.count >= 3 && ["threads", "workspaces"].contains(String(parts[1])) && UUID(uuidString: String(parts[2])) != nil
            ? "/api/\(parts[1])/\(parts[2])/transport/stream/" : "/api/transport/stream/"
    }
    mutating func accept(_ next: String) throws {
        guard next.hasPrefix(prefix), let url = URLComponents(string: next), url.scheme == nil, url.host == nil,
              url.fragment == nil, url.percentEncodedQuery == "chunk=\(index)", url.percentEncodedPath.hasPrefix(prefix) else {
            throw APIError("Invalid encrypted continuation scope.")
        }
        let candidate = String(url.percentEncodedPath.dropFirst(prefix.count))
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard (1...128).contains(candidate.utf8.count), candidate.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              token == nil || token == candidate, index < 1024 else { throw APIError("Invalid encrypted continuation sequence.") }
        token = candidate; index += 1
    }
}
