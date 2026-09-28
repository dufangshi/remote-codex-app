import Foundation

public struct Device: Decodable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let connected: Bool?
    public init(id: String, name: String, connected: Bool?) {
        self.id = id; self.name = name; self.connected = connected
    }
}
public struct Grant: Decodable {
    public let deviceId: String
    public let deviceName: String?
    public let scope: String?
}
public struct Portal: Decodable {
    public let devices: [Device]
    public let sharedDevicesWithMe: [Grant]?
    public var allDevices: [Device] {
        var result = devices
        for grant in sharedDevicesWithMe ?? [] where !result.contains(where: { $0.id == grant.deviceId }) {
            result.append(Device(id: grant.deviceId, name: grant.deviceName ?? "Shared device", connected: nil))
        }
        return result
    }
}
public struct Workspace: Decodable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let absPath: String
}
public struct ThreadSummary: Decodable, Identifiable, Hashable {
    public let id: String
    public let workspaceId: String
    public let title: String
    public let provider: String
    public let agentId: String?
    public let model: String?
    public let reasoningEffort: String?
    public let status: String
    public let activeTurnId: String?
    public let lastError: String?
}
public struct HistoryItem: Decodable, Identifiable {
    public let id: String
    public let kind: String
    public let text: String
    public let previewText: String?
    public let detailText: String?
    public let status: String?
    public let assetPath: String?
}
public struct Turn: Decodable, Identifiable {
    public let id: String
    public let status: String
    public let error: String?
    public let model: String?
    public let reasoningEffort: String?
    public let items: [HistoryItem]
}
public struct ActionRequest: Decodable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String
    public let description: String?
}
public struct ThreadDetail: Decodable {
    public let thread: ThreadSummary
    public let turns: [Turn]
    public let pendingRequests: [ActionRequest]
}
public struct ReasoningOption: Decodable, Identifiable {
    public let reasoningEffort: String
    public let description: String
    public var id: String { reasoningEffort }
}
public struct ModelOption: Decodable, Identifiable {
    public let id: String
    public let model: String
    public let displayName: String
    public let isDefault: Bool
    public let hidden: Bool
    public let supportedReasoningEfforts: [ReasoningOption]
    public let defaultReasoningEffort: String?
}
public struct AgentBackend: Decodable {
    public let provider: String
    public let displayName: String
    public let enabled: Bool
}
public struct LoginResult: Decodable {
    public let token: String?
    public let challengeRequired: Bool?
}
public struct APIError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
