import Foundation
import CryptoKit

extension Data {
    init(base64URL: String) throws {
        let input = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let decoded = Data(base64Encoded: input + String(repeating: "=", count: (4 - input.count % 4) % 4)) else {
            throw APIError("Invalid encrypted transport encoding.")
        }
        self = decoded
    }
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum Packet {
    static let limit = 64 * 1024 * 1024
    static func pack(_ metadata: [String: Any], body: Data) throws -> Data {
        let header = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        guard header.count <= 65536, body.count <= limit else { throw APIError("Encrypted request is too large.") }
        let n = UInt32(header.count)
        return Data([UInt8(n >> 24), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)]) + header + body
    }
    static func unpack(_ bytes: Data) throws -> (metadata: [String: Any], body: Data) {
        guard bytes.count >= 4, bytes.count <= limit + 65540 else { throw APIError("Invalid encrypted packet size.") }
        let n = bytes.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard n <= 65536, n + 4 <= bytes.count,
              let metadata = try JSONSerialization.jsonObject(with: bytes.subdata(in: 4..<(4+n))) as? [String: Any] else {
            throw APIError("Invalid encrypted packet metadata.")
        }
        return (metadata, bytes.subdata(in: (4+n)..<bytes.count))
    }
}

struct KeyDescriptor: Decodable {
    let version: Int
    let challenge: String
    let keyId: String
    let expiresAt: Double
    let serverTime: Double
    let publicKey: String
    let identityKey: String
    let signature: String

    func verify(challenge expected: String) throws {
        guard version == 1, challenge == expected, serverTime.isFinite, expiresAt.isFinite,
              serverTime >= 0, expiresAt <= 9_007_199_254_740_991,
              serverTime.rounded(.towardZero) == serverTime, expiresAt.rounded(.towardZero) == expiresAt,
              expiresAt > serverTime,
              expiresAt - serverTime <= 3600_000 else { throw APIError("Invalid device encryption descriptor.") }
        let identity = try P256.Signing.PublicKey(x963Representation: Data(base64URL: identityKey))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: Data(base64URL: signature))
        let signed = "rcd-key-v1\n\(challenge)\n\(keyId)\n\(Int64(expiresAt))\n\(Int64(serverTime))\n\(publicKey)"
        guard identity.isValidSignature(signature, for: Data(signed.utf8)) else {
            throw APIError("Device encryption signature is invalid.")
        }
    }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward relay credentials or encrypted payloads to a redirect target.
    }
}

@MainActor
public final class RelayClient {
    public let origin: URL
    private let vault: SecretStore
    private let session: URLSession
    private let redirects = NoRedirects()
    private var token: String?
    private var keys: [String: (KeyDescriptor, Double)] = [:]
    private var keyRequests: [String: Task<(KeyDescriptor, Double), Error>] = [:]
    public var signedIn: Bool { token != nil }
    /// Called only with the relay's same-origin HttpOnly cookie from our isolated WebKit store.
    public func syncBrowserSession(_ value: String?) async throws {
        guard value != token else { return }
        try await vault.write(value, for: "session:" + origin.absoluteString)
        token = value
        for cookie in session.configuration.httpCookieStorage?.cookies ?? [] { session.configuration.httpCookieStorage?.deleteCookie(cookie) }
        if value == nil { keys.removeAll() }
    }
    public func pinnedIdentities(_ devices: [String]) async throws -> [String: String] {
        var result: [String: String] = [:]
        for device in devices {
            if let pin = try await vault.read("identity:\(origin.absoluteString):\(device)") { result[device] = pin }
        }
        return result
    }
    public func browserCookies() -> [HTTPCookie] {
        guard let token, let host = origin.host else { return [] }
        var properties: [HTTPCookiePropertyKey: Any] = [.name: "remote_codex_relay_session", .value: token, .domain: host, .path: "/", HTTPCookiePropertyKey("HttpOnly"): "TRUE"]
        if origin.scheme == "https" { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties).map { [$0] } ?? []
    }

    public static func normalizedOrigin(_ text: String) throws -> URL {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: text.contains("://") ? text : "https://" + text),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/",
              c.scheme == "https" || (c.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)) else {
            throw APIError("Enter an HTTPS relay origin, without a path. HTTP is allowed only on localhost.")
        }
        c.path = ""; c.host = host.lowercased()
        guard let url = c.url else { throw APIError("Invalid relay origin.") }
        return url
    }
    public init(origin: String, vault: SecretStore = KeychainStore()) async throws {
        self.origin = try Self.normalizedOrigin(origin)
        self.vault = vault
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: redirects, delegateQueue: nil)
        self.token = try await vault.read("session:" + self.origin.absoluteString)
    }
    public func login(identifier: String, password: String) async throws -> Bool {
        let result: LoginResult = try await relay("/relay/auth/login", method: "POST", body: ["identifier": identifier, "password": password])
        return try await accept(result)
    }
    public func verify(code: String) async throws -> Bool {
        let result: LoginResult = try await relay("/relay/auth/challenge", method: "POST", body: ["code": code, "rememberBrowser": false])
        return try await accept(result)
    }
    private func accept(_ result: LoginResult) async throws -> Bool {
        if let token = result.token, !token.isEmpty {
            try await vault.write(token, for: "session:" + origin.absoluteString)
            self.token = token; return true
        }
        if result.challengeRequired == true { return false }
        throw APIError("Sign-in did not return a session. Complete authentication in your relay account.")
    }
    public func logout() async throws {
        // Local credentials are removed even if an offline relay cannot revoke its session.
        defer {
            token = nil; keys.removeAll()
            for cookie in session.configuration.httpCookieStorage?.cookies ?? [] {
                session.configuration.httpCookieStorage?.deleteCookie(cookie)
            }
        }
        try await vault.write(nil, for: "session:" + origin.absoluteString)
        let _: Data = try await raw("/relay/auth/logout", method: "POST", body: Data("{}".utf8))
    }
    private func raw(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var request = try request(path, method: method)
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError("Invalid relay response.") }
        try check(response.statusCode, data)
        return data
    }
    private func request(_ path: String, method: String) throws -> URLRequest {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: origin.absoluteString + path), url.host == origin.host else {
            throw APIError("Invalid relay request path.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return request
    }
    private func check(_ status: Int, _ data: Data) throws {
        guard (200..<300).contains(status) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw APIError(object?["message"] as? String ?? "Request failed (HTTP \(status)).")
        }
    }
    public func relay<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let data = try await raw(path, method: method, body: try body.map { try JSONSerialization.data(withJSONObject: $0) })
        return try JSONDecoder().decode(T.self, from: data)
    }
    public func device<T: Decodable>(_ id: String, _ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let bytes = try body.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
        let data = try await deviceData(id, path, method: method, body: bytes)
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func key(_ device: String) async throws -> (KeyDescriptor, Double) {
        if let cached = keys[device], cached.0.expiresAt > Date().timeIntervalSince1970 * 1000 + cached.1 + 60_000 { return cached }
        if let pending = keyRequests[device] { return try await pending.value }
        let pending = Task { try await self.fetchKey(device) }
        keyRequests[device] = pending
        defer { keyRequests.removeValue(forKey: device) }
        return try await pending.value
    }
    private func fetchKey(_ device: String) async throws -> (KeyDescriptor, Double) {
        let challenge = UUID().uuidString.lowercased()
        let descriptor: KeyDescriptor = try await relay("/relay/devices/\(device)/api/transport/key?challenge=\(challenge)")
        try descriptor.verify(challenge: challenge)
        let name = "identity:\(origin.absoluteString):\(device)"
        if let pin = try await vault.read(name), pin != descriptor.identityKey {
            throw APIError("This device's encryption identity changed. Connection blocked. Verify the device identity in the web client before resetting its macOS Keychain identity entry.")
        }
        try await vault.write(descriptor.identityKey, for: name)
        let result = (descriptor, descriptor.serverTime - Date().timeIntervalSince1970 * 1000)
        keys[device] = result
        return result
    }
    public func deviceData(_ device: String, _ path: String, method: String = "GET", body: Data = Data(),
                           contentType: String = "application/json") async throws -> Data {
        guard UUID(uuidString: device) != nil, path.hasPrefix("/api/"),
              let route = URLComponents(string: path), route.scheme == nil, route.host == nil, route.fragment == nil,
              !route.path.split(separator: "/").contains("..") else { throw APIError("Invalid device route.") }
        var (metadata, data) = try await exchange(device, path, method: method, body: body, contentType: contentType)
        var continuation = Continuation(path: path)
        while let next = metadata["streamNext"] as? String {
            try Task.checkCancellation()
            try continuation.accept(next)
            let result = try await exchange(device, next, method: "GET", body: Data(), contentType: contentType)
            metadata = result.0; data.append(result.1)
            guard data.count <= Packet.limit else { throw APIError("Device response exceeds 64 MB.") }
        }
        return data
    }
    private func exchange(_ device: String, _ path: String, method: String, body: Data, contentType: String,
                          retry: Bool = true) async throws -> ([String: Any], Data) {
        let (descriptor, offset) = try await key(device)
        let components = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let wire = String(components[0])
        var resource = ""
        if contentType == "application/json", let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let workspace = object["workspaceId"] as? String {
            resource = String(decoding: try JSONSerialization.data(withJSONObject: ["workspaceId": workspace], options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        }
        let requestId = "\(UUID().uuidString.lowercased()).\(Int64(Date().timeIntervalSince1970 * 1000 + offset))"
        let aad = "rcd-http-v1\n\(descriptor.keyId)\n\(requestId)\n\(method)\n\(wire)\n\(resource)"
        var sender = try HPKE.Sender(recipientKey: P256.KeyAgreement.PublicKey(x963Representation: Data(base64URL: descriptor.publicKey)),
                                     ciphersuite: .P256_SHA256_AES_GCM_256, info: Data("remote-codex/relay/v1".utf8))
        let clear = try Packet.pack(["headers": ["content-type": contentType], "query": components.count > 1 ? "?" + components[1] : ""], body: body)
        let sealed = try sender.seal(clear, authenticating: Data(aad.utf8))
        var request = try request("/relay/devices/\(device)\(wire)", method: method)
        request.setValue(descriptor.keyId, forHTTPHeaderField: "x-rcd-key")
        request.setValue(requestId, forHTTPHeaderField: "x-rcd-request")
        request.setValue(sender.encapsulatedKey.base64URL, forHTTPHeaderField: "x-rcd-enc")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if !resource.isEmpty { request.setValue(resource, forHTTPHeaderField: "x-rcd-resource") }
        if method == "GET" { request.setValue(sealed.base64URL, forHTTPHeaderField: "x-rcd-sealed") }
        else { request.httpBody = sealed }
        let (ciphertext, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError("Invalid device response.") }
        guard response.value(forHTTPHeaderField: "x-rcd-encrypted") == "1" else {
            let object = (try? JSONSerialization.jsonObject(with: ciphertext)) as? [String: Any]
            if retry, method == "GET", response.statusCode == 409, object?["code"] as? String == "transport_reconnect_required" {
                keys.removeValue(forKey: device)
                return try await exchange(device, path, method: method, body: body, contentType: contentType, retry: false)
            }
            try check(response.statusCode, ciphertext)
            throw APIError("Unencrypted device response rejected. Update this device's Supervisor.")
        }
        guard ciphertext.count >= 16, ciphertext.count <= Packet.limit + 65556 else { throw APIError("Invalid encrypted response size.") }
        let responseKey = try sender.exportSecret(context: Data("remote-codex/http-response/v1".utf8), outputByteCount: 32)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Data(repeating: 0, count: 12)), ciphertext: ciphertext.dropLast(16), tag: ciphertext.suffix(16))
        let opened = try AES.GCM.open(box, using: responseKey, authenticating: Data((aad + "\nresponse").utf8))
        let packet = try Packet.unpack(opened)
        guard let status = packet.metadata["status"] as? Int else { throw APIError("Missing encrypted response status.") }
        try check(status, packet.body)
        return (packet.metadata, packet.body)
    }
}
