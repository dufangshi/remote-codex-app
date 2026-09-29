import Foundation

@MainActor
public struct WorkspaceAPI {
    public let client: RelayClient
    public let deviceID: String
    public let workspaceID: String
    public init(client: RelayClient, deviceID: String, workspaceID: String) {
        self.client = client; self.deviceID = deviceID; self.workspaceID = workspaceID
    }
    public func route(_ action: String, path: String? = nil) -> String {
        let base = "/api/workspaces/\(workspaceID)/files" + (action.isEmpty ? "" : "/" + action)
        guard let path else { return base }
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "path", value: path)]
        return base + "?" + (query.percentEncodedQuery ?? "")
    }
    public func tree(_ path: String = ".") async throws -> FileNode {
        try await client.device(deviceID, route("tree", path: path))
    }
    public func read(_ path: String) async throws -> Data {
        try await client.deviceData(deviceID, route("raw", path: path))
    }
    /// The existing API does not offer atomic compare-and-swap. Refuse a known
    /// conflicting remote edit before PUT, and verify persisted bytes afterwards.
    public func save(_ path: String, content: String, original: Data) async throws -> Data {
        guard try await read(path) == original else { throw APIError("This file changed on the device. Your draft is preserved. Reload the remote version or save your draft as a different file.") }
        let data = Data(content.utf8)
        _ = try await client.deviceData(deviceID, route(""), method: "PUT", body: JSONSerialization.data(withJSONObject: ["path": path, "content": content]))
        guard try await read(path) == data else { throw APIError("The saved file could not be verified. Your draft has been kept; reload to check the remote content.") }
        return data
    }
    public func create(_ path: String, content: String = "") async throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !parts.contains(".."), !parts.contains("") else { throw APIError("Use a relative file path within this workspace.") }
        let parent = (path as NSString).deletingLastPathComponent
        let nodes = try await tree(parent.isEmpty ? "." : parent)
        guard !(nodes.children ?? []).contains(where: { $0.name == (path as NSString).lastPathComponent }) else { throw APIError("A file with this name already exists. Open it to edit instead.") }
        _ = try await client.deviceData(deviceID, route(""), method: "PUT", body: JSONSerialization.data(withJSONObject: ["path": path, "content": content]))
    }
}
