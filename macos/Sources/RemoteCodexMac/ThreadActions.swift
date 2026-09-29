import AppKit
import Foundation
import RemoteCodexCore

extension AppState {
    func refreshNavigation() async {
        guard let api = client else { return }
        do {
            let value: WorkbenchSnapshot = try await api.relay("/relay/account/workbench")
            if client === api { navigation = value }
        } catch { /* A navigation failure must not prevent encrypted conversations. */ }
    }
    func setFavorite(_ reference: ThreadReference, favorite: Bool) async {
        guard let api = client else { return }
        var body: [String: Any] = ["deviceId": reference.deviceId, "threadId": reference.threadId,
            "title": reference.title, "workspaceLabel": reference.workspaceLabel, "favorite": favorite]
        if let workspace = reference.workspaceId { body["workspaceId"] = workspace }
        await perform {
            let result: WorkbenchSnapshot = try await api.relay("/relay/account/workbench", method: "POST", body: body)
            if client === api { navigation = result }
        }
    }
    func recordVisit(favorite: Bool? = nil) async {
        guard let api = client, let device = deviceID, let thread = detail?.thread, thread.id == threadID else { return }
        var body: [String: Any] = ["deviceId": device, "threadId": thread.id, "title": thread.title,
            "workspaceId": thread.workspaceId, "workspaceLabel": workspaces.first { $0.id == thread.workspaceId }?.label ?? "Workspace"]
        if let favorite { body["favorite"] = favorite }
        await perform {
            let snapshot: WorkbenchSnapshot = try await api.relay("/relay/account/workbench", method: "POST", body: body)
            if client === api { navigation = snapshot }
        }
    }
    func selectReference(_ device: String, _ thread: String) {
        guard UUID(uuidString: device) != nil, UUID(uuidString: thread) != nil else { return }
        UserDefaults.standard.set(thread, forKey: "native-thread:" + relay + "/" + device)
        page = "conversation"
        if device == deviceID {
            if let row = threads.first(where: { $0.id == thread }) { workspaceID = row.workspaceId }
            threadID = thread; contentMode = "chat"
        } else {
            UserDefaults.standard.set(thread, forKey: "native-thread:" + relay + "/" + device)
            deviceID = device
        }
    }
    func openNotification(_ notification: WorkbenchNotification) {
        guard let origin = try? RelayClient.normalizedOrigin(relay),
              let url = URL(string: notification.href, relativeTo: origin)?.absoluteURL,
              BrowserPolicy.sameOrigin(url, origin) else { error = "Invalid notification destination."; return }
        let parts = url.path.split(separator: "/")
        guard parts.count == 4, parts[0] == "devices", parts[2] == "threads" else { error = "Unknown notification destination."; return }
        selectReference(String(parts[1]), String(parts[3]))
    }
    func exportTranscript() async {
        guard let api = client, let device = deviceID, let thread = threadID else { return }
        await perform {
            let bytes = try await api.deviceData(device, "/api/threads/\(thread)/exports/html?limit=100")
            let panel = NSSavePanel(); panel.nameFieldStringValue = "remote-codex-transcript.html"
            if panel.runModal() == .OK, let url = panel.url { try bytes.write(to: url, options: .atomic) }
        }
    }
    func fork(turn: String) async {
        guard !busy, let api = client, let device = deviceID, let thread = threadID else { return }
        busy = true; defer { busy = false }
        await perform {
            struct Result: Decodable { let thread: ThreadDetail }
            let result: Result = try await api.device(device, "/api/threads/\(thread)/fork", method: "POST", body: ["mode": "turn", "turnId": turn])
            guard device == deviceID else { return }
            threads.insert(result.thread.thread, at: 0); threadID = result.thread.thread.id
        }
    }
    func respond(_ request: ActionRequest, answers: [String: [String]]) async {
        guard let api = client, let device = deviceID, let thread = threadID else { return }
        await perform {
            let body = ["answers": answers.mapValues { ["answers": $0] }]
            _ = try await api.deviceData(device, "/api/threads/\(thread)/requests/\(request.id)/respond", method: "POST", body: JSONSerialization.data(withJSONObject: body))
            await refreshThread()
        }
    }
    func mergeHistory(_ fresh: [Turn], prepend: Bool = false) {
        let freshIDs = Set(fresh.map(\.id))
        if prepend { history = fresh + history.filter { !freshIDs.contains($0.id) }; return }
        let replacements = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let existing = Set(history.map(\.id))
        history = history.map { replacements[$0.id] ?? $0 } + fresh.filter { !existing.contains($0.id) }
    }
    func loadOlderHistory() async {
        guard !historyLoading, let api = client, let device = deviceID, let thread = threadID, let first = history.first else { return }
        let generation = selectionGeneration
        historyLoading = true; defer { if generation == selectionGeneration { historyLoading = false } }
        do {
            let page: ThreadDetail = try await api.device(device, "/api/threads/\(thread)?limit=3&view=summary&beforeTurnId=\(first.id)")
            guard generation == selectionGeneration, client === api, device == deviceID, thread == threadID, !Task.isCancelled else { return }
            mergeHistory(page.turns, prepend: true)
            if page.turns.isEmpty { historyExhausted = true }
            threadError = nil
        } catch { if generation == selectionGeneration, client === api, device == deviceID, thread == threadID, !Task.isCancelled { threadError = error.localizedDescription } }
    }
    func itemDetail(thread: String, item: String) async throws -> HistoryItem {
        guard let api = client, let device = deviceID else { throw APIError("Select a device first.") }
        return try await api.device(device, "/api/threads/\(thread)/items/\(item.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? item)/detail")
    }
    func turnDetail(thread: String, turn: String) async throws -> Turn {
        guard let api = client, let device = deviceID else { throw APIError("Select a device first.") }
        return try await api.device(device, "/api/threads/\(thread)/turns/\(turn)/detail")
    }
    func openRemoteLink(_ url: URL, document: String? = nil) {
        if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url); return }
        guard url.scheme == nil || url.scheme == "file", let files = fileWorkspace,
              let root = workspaces.first(where: { $0.id == workspaceID })?.absPath else { error = "Unsupported link destination."; return }
        do {
            let path = try RemoteFileLink.path(url.absoluteString, root: root, document: document)
            contentMode = "files"
            Task { await files.openPath(path) }
        } catch { self.error = error.localizedDescription }
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
