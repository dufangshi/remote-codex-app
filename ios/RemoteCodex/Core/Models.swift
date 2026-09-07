import Foundation

struct ApiErrorBody: Decodable {
    let code: String?
    let message: String
    let details: ApiErrorDetails?
}

struct ApiErrorDetails: Decodable {
    let reason: String?
}

struct RelayUser: Codable, Equatable {
    var id: String
    var email: String
    var username: String
    var role: String
}

struct RegistrationSettings: Codable {
    var enabled: Bool?
    var registrationPasswordConfigured: Bool?
    var googleAuthEnabled: Bool?
    var githubAuthEnabled: Bool?
}

struct RelaySession: Codable {
    var authenticated: Bool
    var user: RelayUser?
    var registrationEnabled: Bool?
    var registrationSettings: RegistrationSettings?
}

struct RelayLoginResult: Decodable {
    var token: String?
    var challengeRequired: Bool?
    var authenticator: Bool?
    var passkey: Bool?
    var session: RelaySession
}

struct LoginChallenge: Decodable {
    var challengeRequired: Bool?
    var authenticator: Bool?
    var passkey: Bool?
}

struct SecurityStatus: Decodable {
    var authenticatorEnabled: Bool?
    var passkeyAvailable: Bool?
    var recoveryCodesRemaining: Int?
    var recentlyVerified: Bool?
    var passkeys: [SecurityPasskey]?
    var sessions: [SecuritySession]?
    var trustedBrowsers: [TrustedBrowser]?
}

struct SecurityPasskey: Decodable, Identifiable {
    var id: String
    var name: String?
    var createdAt: Double?
    var lastUsedAt: Double?
}

struct SecuritySession: Decodable, Identifiable {
    var id: String
    var name: String?
    var current: Bool?
    var createdAt: Double?
    var expiresAt: Double?
}

struct TrustedBrowser: Decodable, Identifiable {
    var id: String
    var name: String?
    var createdAt: Double?
    var expiresAt: Double?
    var lastUsedAt: Double?
}

struct AuthenticatorEnrollment: Decodable {
    var secret: String?
    var uri: String?
    var qrSvg: String?
}

struct RecoveryCodesResult: Decodable {
    var recoveryCodes: [String]?
}

struct SetupTokenResult: Decodable {
    var token: String
}

struct RelayRegisterResult: Decodable {
    var token: String?
    var session: RelaySession?
    var pendingApproval: Bool?
}

struct RelayDevice: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var token: String?
    var tokenPreview: String?
    var connected: Bool?
    var hostedStatus: String?
}

struct RelayCreateDeviceResult: Decodable {
    var device: RelayDevice
    var token: String
}

struct RelayAccessEvent: Codable, Identifiable {
    var id: String?
    var username: String?
    var kind: String?
    var accessedAt: String?
}

struct RelayShare: Codable, Identifiable {
    var id: String
    var ownerUsername: String?
    var targetUsername: String?
    var deviceId: String
    var deviceName: String?
    var threadId: String
    var threadTitle: String?
    var workspaceId: String?
    var workspaceLabel: String?
    var threadAccess: String?
    var workspaceAccess: String?
    var lastAccessedAt: String?
    var accessEvents: [RelayAccessEvent]?
}

struct RelayGrant: Codable, Identifiable {
    var id: String
    var ownerUsername: String?
    var targetUsername: String?
    var deviceId: String
    var deviceName: String?
    var threadId: String?
    var threadTitle: String?
    var workspaceId: String?
    var workspaceLabel: String?
    var threadAccess: String?
    var workspaceAccess: String?
    var lastAccessedAt: String?
    var accessEvents: [RelayAccessEvent]?
}

struct RelayPortal: Decodable {
    var user: RelayUser
    var devices: [RelayDevice]
    var sharedWithMe: [RelayShare]?
    var sharedByMe: [RelayShare]?
    var sharedDevicesWithMe: [RelayGrant]?
    var sharedThreadsWithMe: [RelayGrant]?
    var grantsByMe: [RelayGrant]?
}

struct Workspace: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var absPath: String?
    var isFavorite: Bool?
    var createdAt: String?
    var lastOpenedAt: String?
}

struct RuntimeConfig: Decodable {
    var appName: String?
    var appVersion: String?
    var environment: String?
    var host: String?
    var port: Int?
    var workspaceRoot: String?
}

struct WorkspaceSettings: Decodable {
    var workspaceRoot: String?
    var devHome: String?
    var defaultBackend: String?
}

struct ThreadSummary: Codable, Identifiable, Equatable {
    var id: String
    var workspaceId: String?
    var provider: String?
    var title: String?
    var model: String?
    var status: String?
    var updatedAt: String?
    var lastTurnCompletedAt: String?
}

struct AgentBackend: Decodable, Identifiable {
    var provider: String
    var displayName: String?
    var enabled: Bool?
    var isDefault: Bool?
    var id: String { provider }
}

struct ModelOption: Decodable, Identifiable {
    var id: String?
    var model: String
    var displayName: String?
    var isDefault: Bool?
}

struct ThreadEvent: Decodable {
    var type: String
    var threadId: String
    var payload: [String: AnyCodable]?
}

struct AnyCodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v; return }
        if let v = try? container.decode(Bool.self) { value = v; return }
        if let v = try? container.decode(Int.self) { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        value = ""
    }
    var string: String? { value as? String }
}

enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}

func normalizeRelayUrl(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return "" }
    if !value.contains("://") { value = "https://" + value }
    while value.hasSuffix("/") { value.removeLast() }
    return value
}
