import Foundation
import RemoteCodexCore

extension AppState {
    func mergeHistory(_ fresh: [Turn], prepend: Bool = false) {
        let freshIDs = Set(fresh.map(\.id))
        if prepend { history = fresh + history.filter { !freshIDs.contains($0.id) }; return }
        let replacements = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let existing = Set(history.map(\.id))
        history = history.map { replacements[$0.id] ?? $0 } + fresh.filter { !existing.contains($0.id) }
    }
    func loadOlderHistory() async {
        guard !historyLoading, let api = client, let device = deviceID, let thread = threadID, let first = history.first else { return }
        historyLoading = true; defer { historyLoading = false }
        do {
            let page: ThreadDetail = try await api.device(device, "/api/threads/\(thread)?limit=20&view=full&beforeTurnId=\(first.id)")
            guard device == deviceID, thread == threadID, !Task.isCancelled else { return }
            mergeHistory(page.turns, prepend: true)
            if page.turns.isEmpty { historyExhausted = true }
            threadError = nil
        } catch { if device == deviceID, thread == threadID, !Task.isCancelled { threadError = error.localizedDescription } }
    }
    func itemDetail(thread: String, item: String) async throws -> HistoryItem {
        guard let api = client, let device = deviceID else { throw APIError("Select a device first.") }
        return try await api.device(device, "/api/threads/\(thread)/items/\(item.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? item)/detail")
    }
    func selectWorkspace() {
        guard let api = client, let device = deviceID, let workspace = workspaces.first(where: { $0.id == workspaceID }) else { fileWorkspace = nil; return }
        let key = device + "/" + workspace.id
        if fileSessions[key] == nil {
            fileSessions[key] = WorkspaceFiles(api: WorkspaceAPI(client: api, deviceID: device, workspaceID: workspace.id), label: workspace.label)
        }
        fileWorkspace = fileSessions[key]
    }
    func refreshLists() async {
        guard let api = client, let device = deviceID else { return }
        await perform {
            async let spaces: [Workspace] = api.device(device, "/api/workspaces")
            async let rows: [ThreadSummary] = api.device(device, "/api/threads")
            let (newSpaces, newRows) = try await (spaces, rows)
            guard device == deviceID, client === api else { return }
            workspaces = newSpaces; threads = newRows
            if !newSpaces.contains(where: { $0.id == workspaceID }) { workspaceID = newSpaces.first?.id }
            if !newRows.contains(where: { $0.id == threadID }) { threadID = nil }
        }
    }
    func openFullWorkspace() {
        guard let client else { return }
        let route: String
        if let device = deviceID, let thread = threadID { route = "/devices/\(device)/threads/\(thread)" }
        else if let device = deviceID { route = "/devices/\(device)/workspaces" }
        else { route = "/relay-devices" }
        webCookies = client.browserCookies()
        webURL = URL(string: client.origin.absoluteString + route)
        contentMode = "web"
    }
    func renameThread(_ thread: ThreadSummary, title: String) async {
        guard let api = client, let device = deviceID, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await perform {
            let updated: ThreadSummary = try await api.device(device, "/api/threads/\(thread.id)", method: "PATCH", body: ["title": title])
            guard device == deviceID else { return }
            if let index = threads.firstIndex(where: { $0.id == thread.id }) { threads[index] = updated }
            await refreshThread()
        }
    }
    func deleteThread(_ thread: ThreadSummary) async {
        guard let api = client, let device = deviceID else { return }
        await perform {
            _ = try await api.deviceData(device, "/api/threads/\(thread.id)", method: "DELETE")
            guard device == deviceID else { return }
            threads.removeAll { $0.id == thread.id }
            if threadID == thread.id { threadID = nil; detail = nil; history = [] }
        }
    }
    func prepareThreadSettings() async {
        guard let api = client, let device = deviceID, let thread = detail?.thread else { return }
        threadModels = []; showingThreadSettings = true
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "cwd", value: workspaces.first { $0.id == thread.workspaceId }?.absPath)]
        if let agent = thread.agentId { query.queryItems?.append(URLQueryItem(name: "agentId", value: agent)) }
        await perform {
            let values: [ModelOption] = try await api.device(device, "/api/agent-runtimes/\(thread.provider)/models?" + (query.percentEncodedQuery ?? ""))
            if device == deviceID, thread.id == threadID { threadModels = values.filter { !$0.hidden } }
        }
    }
    func saveThreadSettings(model: String, effort: String) async {
        guard let api = client, let device = deviceID, let thread = threadID else { return }
        busy = true; defer { busy = false }
        await perform {
            _ = try await api.deviceData(device, "/api/threads/\(thread)/settings", method: "PATCH", body: JSONSerialization.data(withJSONObject: ["model": model, "reasoningEffort": effort.isEmpty ? "auto" : effort]))
            showingThreadSettings = false; await refreshThread()
        }
    }
}
