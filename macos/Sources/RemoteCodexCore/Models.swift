import Foundation

public struct Device: Decodable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let connected: Bool?
    public let tokenPreview: String?
    public let lastSeenAt: String?
    public let hostedStatus: String?
    public init(id: String, name: String, connected: Bool?) {
        self.id = id; self.name = name; self.connected = connected
        tokenPreview = nil; lastSeenAt = nil; hostedStatus = nil
    }
}
public struct Grant: Decodable, Identifiable {
    public let id: String
    public let deviceId: String
    public let deviceName: String?
    public let deviceConnected: Bool?
    public let scope: String?
    public let threadId: String?
    public let threadTitle: String?
    public let workspaceId: String?
    public let workspaceLabel: String?
    public let workspaceScope: String?
    public let workspaceIds: [String]?
    public let threadAccess: String?
    public let workspaceAccess: String?
    public let canCreateThreads: Bool?
    public let label: String?
    public let ownerUsername: String?
    public let targetUsername: String?
    public let expiresAt: String?
}
public struct Portal: Decodable {
    public let devices: [Device]
    public let sharedDevicesWithMe: [Grant]?
    public let sharedWithMe: [Grant]?
    public let sharedByMe: [Grant]?
    public let grantsByMe: [Grant]?
    public var allDevices: [Device] {
        var result = devices
        for grant in sharedDevicesWithMe ?? [] where !result.contains(where: { $0.id == grant.deviceId }) {
            result.append(Device(id: grant.deviceId, name: grant.deviceName ?? "Shared device", connected: grant.deviceConnected))
        }
        return result
    }
}
public struct Workspace: Decodable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let absPath: String
    public let isFavorite: Bool?
    public let lastOpenedAt: String?
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
    public let createdAt: String?
    public let kind: String
    public let text: String
    public let previewText: String?
    public let detailText: String?
    public let status: String?
    public let assetPath: String?
    public let hasDeferredDetail: Bool?
    public let title: String?
}
public struct Turn: Decodable, Identifiable {
    public let id: String
    public let status: String
    public let error: String?
    public let model: String?
    public let reasoningEffort: String?
    public let items: [HistoryItem]
    public let startedAt: String?
    public let completedAt: String?
    public let tokenUsage: TokenUsage?
    public let priceEstimate: PriceEstimate?
    public let hasDeferredItems: Bool?
    public let deferredItemCount: Int?
}
public struct TokenUsage: Decodable { public let total: TokenBreakdown }
public struct TokenBreakdown: Decodable {
    public let totalTokens: Int
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
}
public struct PriceEstimate: Decodable { public let totalUsd: Double }
public struct ActionQuestion: Decodable, Identifiable {
    public let id: String
    public let question: String
    public let isSecret: Bool
    public let multiSelect: Bool?
    public let options: [QuestionOption]?
}
public struct QuestionOption: Decodable { public let label: String; public let description: String }
public struct ActionRequest: Decodable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String
    public let description: String?
    public let questions: [ActionQuestion]?
}
public struct ThreadDetail: Decodable {
    public let thread: ThreadSummary
    public let turns: [Turn]
    public let pendingRequests: [ActionRequest]
    public let totalTurnCount: Int?
}
public struct FileNode: Decodable, Identifiable {
    public let name: String
    public let path: String
    public let kind: String
    public let size: Int?
    public let children: [FileNode]?
    public var id: String { path }
    public var isDirectory: Bool { kind == "directory" }
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
public struct WorkbenchSnapshot: Decodable {
    public let threads: [ThreadReference]
    public let notifications: [WorkbenchNotification]
}
public struct ThreadReference: Decodable, Identifiable {
    public let deviceId: String
    public let threadId: String
    public let title: String
    public let workspaceLabel: String
    public let workspaceId: String?
    public let deviceName: String
    public let favorite: Bool
    public var id: String { deviceId + "/" + threadId }
}
public struct WorkbenchNotification: Decodable, Identifiable {
    public let id: String
    public let title: String
    public let href: String
    public let occurredAt: String
}
