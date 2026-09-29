import Foundation
import CryptoKit

struct SocketCipher {
    let channel: String
    let send: SymmetricKey
    let receive: SymmetricKey
    var sent: UInt64 = 0
    var received: Int64 = -1
    private func aad(_ n: UInt64, _ value: [String: Any]) -> Data {
        Data("rcd-ws-v1\n\(channel)\n\(n)\n\(value["type"] as? String ?? "")\n\(value["threadId"] as? String ?? "")\n\(value["shellId"] as? String ?? "")".utf8)
    }
    private func nonce(_ n: UInt64) throws -> AES.GCM.Nonce {
        var big = n.bigEndian
        return try AES.GCM.Nonce(data: Data(repeating: 0, count: 4) + withUnsafeBytes(of: &big) { Data($0) })
    }
    mutating func seal(_ message: [String: Any]) throws -> Data {
        guard sent < 9_007_199_254_740_991 else { throw APIError("Encrypted channel exhausted.") }
        let n = sent; sent += 1
        let box = try AES.GCM.seal(JSONSerialization.data(withJSONObject: message), using: send, nonce: nonce(n), authenticating: aad(n, message))
        return try JSONSerialization.data(withJSONObject: [
            "type": message["type"] ?? NSNull(), "threadId": message["threadId"] ?? NSNull(), "shellId": message["shellId"] ?? NSNull(),
            "encrypted": ["version": 1, "channelId": channel, "sequence": n, "body": (box.ciphertext + box.tag).base64URL]
        ])
    }
    mutating func open(_ data: Data) throws -> [String: Any] {
        guard data.count <= 8 * 1024 * 1024,
              let wire = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sealed = wire["encrypted"] as? [String: Any], sealed["version"] as? Int == 1,
              sealed["channelId"] as? String == channel,
              let number = sealed["sequence"] as? NSNumber else { throw APIError("Invalid encrypted socket frame.") }
        let sequence = number.doubleValue
        guard sequence >= 0, sequence <= 9_007_199_254_740_991, sequence.rounded() == sequence,
              sequence > Double(received), let encoded = sealed["body"] as? String else { throw APIError("Encrypted event replay rejected.") }
        let n = UInt64(sequence), bytes = try Data(base64URL: encoded)
        guard bytes.count >= 16 else { throw APIError("Truncated socket frame.") }
        let box = try AES.GCM.SealedBox(nonce: nonce(n), ciphertext: bytes.dropLast(16), tag: bytes.suffix(16))
        let clear = try AES.GCM.open(box, using: receive, authenticating: aad(n, wire))
        guard let value = try JSONSerialization.jsonObject(with: clear) as? [String: Any],
              aad(n, value) == aad(n, wire) else { throw APIError("Encrypted event scope mismatch.") }
        received = Int64(n); return value
    }
}

@MainActor public final class DeviceSocket {
    private let task: URLSessionWebSocketTask
    private var cipher: SocketCipher
    init(task: URLSessionWebSocketTask, cipher: SocketCipher) { self.task = task; self.cipher = cipher; task.maximumMessageSize = 8 * 1024 * 1024; task.resume() }
    public func send(_ message: [String: Any]) async throws {
        let data = try cipher.seal(message)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }
    public func receive() async throws -> [String: Any] {
        let message = try await task.receive()
        let data: Data
        switch message { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: throw APIError("Unknown socket frame.") }
        return try cipher.open(data)
    }
    public func close() { task.cancel(with: .normalClosure, reason: nil) }
}
