import Foundation
import Security

public protocol SecretStore: AnyObject {
    func read(_ key: String) async throws -> String?
    func write(_ value: String?, for key: String) async throws
}

public final class KeychainStore: SecretStore {
    private let service: String
    public init(service: String = "com.remotecodex.mac") { self.service = service }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    public func read(_ key: String) async throws -> String? {
        try await Task.detached { try self.readSync(key) }.value
    }
    private func readSync(_ key: String) throws -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw APIError("Unable to read Keychain (\(status)).")
        }
        return value
    }
    public func write(_ value: String?, for key: String) async throws {
        try await Task.detached { try self.writeSync(value, for: key) }.value
    }
    private func writeSync(_ value: String?, for key: String) throws {
        let q = query(key)
        guard let value else {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw APIError("Unable to remove Keychain entry (\(status)).")
            }
            return
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw APIError("Unable to save Keychain entry (\(status)).") }
    }
}
