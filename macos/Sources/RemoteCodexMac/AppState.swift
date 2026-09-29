import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import RemoteCodexCore

struct DraftImage: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let mime: String
    var image: NSImage? { NSImage(data: data) }
    var payload: ImageAttachment { ImageAttachment(data: data, mimeType: mime) }
}
struct AgentChoice: Identifiable {
    let id: String
    let provider: String
    let agentId: String?
    let displayName: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var relay = UserDefaults.standard.string(forKey: "relayOrigin") ?? "https://remote.lnz-study.com"
    @Published var identifier = ""
    @Published var password = ""
    @Published var code = ""
    @Published var challenge = false
    @Published var authenticated = false
    @Published var busy = false
    @Published var sending = false
    @Published var error: String?
    @Published var devices: [Device] = []
    @Published var deviceID: String?
    @Published var workspaces: [Workspace] = []
    @Published var workspaceID: String?
    @Published var threads: [ThreadSummary] = []
    @Published var threadID: String?
    @Published var detail: ThreadDetail?
    @Published var agents: [AgentChoice] = []
    @Published var agentID = ""
    @Published var models: [ModelOption] = []
    @Published var modelID = ""
    @Published var effort = ""
    @Published var draft = ""
    @Published var images: [DraftImage] = []
    @Published var query = ""
    @Published var showingNewThread = false
    @Published var showingNewWorkspace = false
    @Published var workspacePath = ""
    @Published var workspaceLabel = ""
    @Published var newTitle = ""
    @Published var approvalMode = "guarded"
    @Published var lastRefresh: Date?
    @Published var contentMode = "chat"
    @Published var threadLoading = false
    @Published var threadError: String?
    @Published var historyLoading = false
    @Published var history: [Turn] = []
    @Published var historyExhausted = false
    @Published var fileWorkspace: WorkspaceFiles?
    @Published var showingSidebar = true
    @Published var showingSettings = false
    @Published var showingSearch = false
    @Published var conversationQuery = ""
    @Published var deviceLoading = false
    @Published var navigation: WorkbenchSnapshot?
    @Published var page = "conversation"
    @Published var portal: Portal?
    @Published var showingTools = false
    @Published var showingShare = false
    @Published var pinnedThreads = Set(UserDefaults.standard.stringArray(forKey: "native-pinned-threads") ?? [])
    @Published var showingThreadSettings = false
    @Published var notificationStatus = "Checking macOS notifications…"
    let systemNotifications = SystemNotifications()
    @Published var threadModels: [ModelOption] = []
    private(set) var client: RelayClient?
    var fileSessions: [String: WorkspaceFiles] = [:]
    private var refreshInFlight: [String: UUID] = [:]
    private(set) var selectionGeneration = UUID()
    private var drafts: [String: (String, [DraftImage])] = [:]
    private var loadedThread: String?
    private var pendingSubmissions: [String: (fingerprint: String, requestID: String)] = [:]

    var visibleThreads: [ThreadSummary] {
        threads.filter { ($0.workspaceId == workspaceID || workspaceID == nil) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var selectedModel: ModelOption? { models.first { $0.model == modelID } }
    var active: Bool { detail?.thread.activeTurnId != nil }
    var deviceName: String { devices.first { $0.id == deviceID }?.name ?? "Device" }
    var hasOlderHistory: Bool { !historyExhausted && (detail?.totalTurnCount ?? history.count) > history.count }
    var hasUnsavedFiles: Bool { fileSessions.values.contains { $0.hasUnsavedChanges } }
    var hasDrafts: Bool { !draft.isEmpty || !images.isEmpty || drafts.values.contains { !$0.0.isEmpty || !$0.1.isEmpty } }
    func togglePin(_ id: String) {
        if pinnedThreads.contains(id) { pinnedThreads.remove(id) } else { pinnedThreads.insert(id) }
        UserDefaults.standard.set(Array(pinnedThreads), forKey: "native-pinned-threads")
    }

    func perform(_ work: () async throws -> Void) async {
        do { try await work() } catch is CancellationError { } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func restore() async {
        busy = true; defer { busy = false }
        await perform {
            let api = try await RelayClient(origin: relay, vault: KeychainStore(service: Bundle.main.bundleIdentifier ?? "com.remotecodex.mac"))
            client = api
            guard api.signedIn else { return }
            try await loadPortal(api)
        }
    }
    func signIn() async {
        busy = true; error = nil; defer { busy = false }
        await perform {
            if !challenge { client = try await RelayClient(origin: relay, vault: KeychainStore(service: Bundle.main.bundleIdentifier ?? "com.remotecodex.mac")) }
            guard let api = client else { return }
            let ready = try await (challenge ? api.verify(code: code) : api.login(identifier: identifier, password: password))
            password = ""; code = ""; challenge = !ready
            if ready {
                relay = api.origin.absoluteString
                UserDefaults.standard.set(relay, forKey: "relayOrigin")
                try await loadPortal(api)
            }
        }
    }
    private func loadPortal(_ api: RelayClient) async throws {
        let portal: Portal = try await api.relay("/relay/portal")
        guard client === api else { return }
        devices = portal.allDevices; authenticated = true; challenge = false
        self.portal = portal
        systemNotifications.start(state: self, client: api)
        await refreshNavigation()
        // One-time route migration from the 0.3 web workspace. Only public IDs.
        let migration = "native-layout-v4:" + relay
        if !UserDefaults.standard.bool(forKey: migration) {
            if let path = UserDefaults.standard.string(forKey: "workspace-route:" + api.origin.absoluteString) {
                let parts = path.split(separator: "/")
                if parts.count == 4, parts[0] == "devices", parts[2] == "threads",
                   UUID(uuidString: String(parts[1])) != nil, UUID(uuidString: String(parts[3])) != nil {
                    UserDefaults.standard.set(String(parts[1]), forKey: "native-device:" + relay)
                    UserDefaults.standard.set(String(parts[3]), forKey: "native-thread:" + relay + "/" + parts[1])
                }
            }
            UserDefaults.standard.set(true, forKey: migration)
        }
        if !devices.contains(where: { $0.id == deviceID }) {
            let saved = UserDefaults.standard.string(forKey: "native-device:" + relay)
            deviceID = devices.first(where: { $0.id == saved })?.id ?? devices.first?.id
        }
    }
    func refreshPortal() async { await perform { if let client { try await loadPortal(client) } } }
    func signOut() async {
        guard !hasUnsavedFiles else { error = "Save or close your modified file tabs before signing out."; return }
        systemNotifications.stop()
        if let client { await perform { try await client.logout() } }
        client = nil; authenticated = false; challenge = false
        devices = []; deviceID = nil; workspaces = []; workspaceID = nil
        threads = []; threadID = nil; detail = nil; draft = ""; images = []; drafts = [:]; loadedThread = nil
        pendingSubmissions = [:]
        fileSessions = [:]; fileWorkspace = nil; history = []; navigation = nil
    }
    func loadDevice() async {
        workspaces = []; threads = []; workspaceID = nil; threadID = nil; detail = nil; error = nil; threadError = nil
        fileWorkspace = nil; contentMode = "chat"
        guard let api = client, let device = deviceID else { return }
        deviceLoading = true
        defer { if device == deviceID { deviceLoading = false } }
        await perform {
            async let fetchedWorkspaces: [Workspace] = api.device(device, "/api/workspaces")
            async let fetchedThreads: [ThreadSummary] = api.device(device, "/api/threads")
            let (spaces, rows) = try await (fetchedWorkspaces, fetchedThreads)
            guard client === api, device == deviceID, !Task.isCancelled else { return }
            workspaces = spaces; threads = rows
            let saved = UserDefaults.standard.string(forKey: "native-thread:" + relay + "/" + device)
            let selected = rows.first(where: { $0.id == saved }) ?? rows.first
            workspaceID = selected?.workspaceId ?? spaces.first?.id
            threadID = selected?.id
            UserDefaults.standard.set(device, forKey: "native-device:" + relay)
            selectWorkspace()
        }
    }
    func loadThread() async {
        selectionGeneration = UUID()
        if let previous = loadedThread { drafts[previous] = (draft, images) }
        loadedThread = threadID
        if let device = deviceID, let thread = threadID {
            UserDefaults.standard.set(thread, forKey: "native-thread:" + relay + "/" + device)
        }
        let saved = threadID.flatMap { drafts[$0] }
        draft = saved?.0 ?? ""; images = saved?.1 ?? []; detail = nil; history = []; historyExhausted = false; historyLoading = false; threadError = nil
        if threadID != nil { contentMode = "chat" }
        await refreshThread()
        await recordVisit()
    }
    func refreshThread() async {
        guard let api = client, let device = deviceID, let thread = threadID else { return }
        let key = device + "/" + thread
        let generation = selectionGeneration
        guard refreshInFlight[key] != generation else { return }
        refreshInFlight[key] = generation
        threadLoading = detail == nil
        defer { if refreshInFlight[key] == generation { refreshInFlight.removeValue(forKey: key) }; if generation == selectionGeneration { threadLoading = false } }
        do {
            let value: ThreadDetail = try await api.device(device, "/api/threads/\(thread)?limit=3&view=summary")
            guard generation == selectionGeneration, client === api, device == deviceID, thread == threadID, !Task.isCancelled else { return }
            mergeHistory(value.turns)
            detail = value; lastRefresh = Date(); threadError = nil
            if let index = threads.firstIndex(where: { $0.id == thread }) { threads[index] = value.thread }
            else { threads.append(value.thread) }
            if workspaceID != value.thread.workspaceId { workspaceID = value.thread.workspaceId }
        } catch {
            if generation == selectionGeneration, client === api, device == deviceID, thread == threadID, !Task.isCancelled { threadError = error.localizedDescription }
        }
    }
    func poll() async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(active ? 1 : (NSApp.isActive ? 4 : 15))) } catch { return }
            if contentMode == "chat" { await refreshThread() }
        }
    }
    func prepareNewThread() async {
        guard let api = client, let device = deviceID, workspaceID != nil else { return }
        showingNewThread = true; models = []; agents = []; agentID = ""; modelID = ""; effort = ""; newTitle = ""
        await perform {
            let backends: [AgentBackend] = try await api.device(device, "/api/agent-runtimes")
            var choices: [AgentChoice] = []
            for backend in backends where backend.enabled {
                if backend.provider == "acp" {
                    let rows: [ModelOption] = try await api.device(device, "/api/agent-runtimes/acp/agents")
                    choices += rows.filter { !$0.hidden }.map { AgentChoice(id: "acp/" + $0.id, provider: "acp", agentId: $0.id, displayName: $0.displayName) }
                    if !rows.isEmpty { continue }
                }
                choices.append(AgentChoice(id: backend.provider, provider: backend.provider, agentId: nil, displayName: backend.displayName))
            }
            guard device == deviceID else { return }
            agents = choices
            agentID = agents.first?.id ?? ""
        }
    }
    func loadModels() async {
        models = []; modelID = ""; effort = ""
        guard let api = client, let device = deviceID, let choice = agents.first(where: { $0.id == agentID }) else { return }
        let agent = agentID
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "cwd", value: workspaces.first { $0.id == workspaceID }?.absPath)]
        if let id = choice.agentId { query.queryItems?.append(URLQueryItem(name: "agentId", value: id)) }
        await perform {
            let rows: [ModelOption] = try await api.device(device, "/api/agent-runtimes/\(choice.provider)/models?" + (query.percentEncodedQuery ?? ""))
            guard agent == agentID, device == deviceID, !Task.isCancelled else { return }
            models = rows.filter { !$0.hidden }
            modelID = models.first(where: { $0.isDefault })?.model ?? models.first?.model ?? ""
        }
    }
    func createThread() async {
        guard let api = client, let device = deviceID, let workspace = workspaceID, !modelID.isEmpty,
              let choice = agents.first(where: { $0.id == agentID }) else { return }
        busy = true; defer { busy = false }
        await perform {
            var body: [String: Any] = ["workspaceId": workspace, "provider": choice.provider, "model": modelID, "approvalMode": approvalMode]
            if let id = choice.agentId { body["agentId"] = id }
            if !newTitle.isEmpty { body["title"] = newTitle }
            if !effort.isEmpty { body["reasoningEffort"] = effort }
            let created: ThreadSummary = try await api.device(device, "/api/threads/start", method: "POST", body: body)
            guard device == deviceID else { return }
            threads.insert(created, at: 0); threadID = created.id; showingNewThread = false
        }
    }
    func createWorkspace(input: [String: Any]? = nil) async {
        guard let api = client, let device = deviceID else { return }
        busy = true; defer { busy = false }
        await perform {
            let created: Workspace = try await api.device(device, "/api/workspaces", method: "POST", body: input ?? ["absPath": workspacePath, "label": workspaceLabel])
            guard device == deviceID else { return }
            workspaces.append(created); workspaceID = created.id; showingNewWorkspace = false
            page = "conversation"; threadID = nil
            workspacePath = ""; workspaceLabel = ""
        }
    }
    func send() async {
        guard let api = client, let device = deviceID, let thread = threadID, !sending,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else { return }
        let text = draft, attachments = images
        let fingerprint = text + attachments.map { $0.id.uuidString }.joined()
        let submission = pendingSubmissions[thread]
        let requestID = submission?.fingerprint == fingerprint ? submission!.requestID : UUID().uuidString.lowercased()
        pendingSubmissions[thread] = (fingerprint, requestID)
        sending = true; error = nil; defer { sending = false }
        await perform {
            let payload = try PromptBody.build(text: text, requestID: requestID, images: attachments.map(\.payload))
            _ = try await api.deviceData(device, "/api/threads/\(thread)/prompt", method: "POST", body: payload.body, contentType: payload.contentType)
            pendingSubmissions.removeValue(forKey: thread)
            if threadID == thread, deviceID == device {
                if draft == text { draft = "" }
                images.removeAll { image in attachments.contains { $0.id == image.id } }
                await refreshThread()
            } else if let saved = drafts[thread] {
                drafts[thread] = (saved.0 == text ? "" : saved.0, saved.1.filter { image in !attachments.contains { $0.id == image.id } })
            }
        }
    }
    func interrupt() async {
        guard let api = client, let device = deviceID, let thread = threadID else { return }
        await perform {
            _ = try await api.deviceData(device, "/api/threads/\(thread)/interrupt", method: "POST", body: Data("{}".utf8))
            await refreshThread()
        }
    }
    func respond(_ request: ActionRequest, allow: Bool) async {
        guard let api = client, let device = deviceID, let thread = threadID else { return }
        await perform {
            _ = try await api.deviceData(device, "/api/threads/\(thread)/requests/\(request.id)/respond", method: "POST", body: JSONSerialization.data(withJSONObject: ["allow": allow]))
            await refreshThread()
        }
    }
    func addImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        do {
            var selected: [DraftImage] = []
            guard images.count + panel.urls.count <= 8 else { throw APIError("Attach up to 8 images per message.") }
            for url in panel.urls {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 10 * 1024 * 1024 else { throw APIError("Each image must be 10 MB or smaller.") }
                let data = try Data(contentsOf: url)
                guard NSImage(data: data) != nil else { throw APIError("\(url.lastPathComponent) is not a valid image.") }
                selected.append(DraftImage(name: url.lastPathComponent, data: data, mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"))
            }
            guard (images + selected).reduce(0, { $0 + $1.data.count }) <= 24 * 1024 * 1024 else { throw APIError("Combined images must be 24 MB or smaller.") }
            images.append(contentsOf: selected)
        } catch { self.error = error.localizedDescription }
    }
    func image(path: String, thread: String) async throws -> NSImage {
        guard let api = client, let device = deviceID else { throw APIError("No device selected.") }
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "path", value: path)]
        let data = try await api.deviceData(device, "/api/threads/\(thread)/assets/image?" + (query.percentEncodedQuery ?? ""))
        guard data.count <= 25 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 960, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
            throw APIError("This image cannot be previewed.")
        }
        return NSImage(cgImage: thumb, size: .zero)
    }
    func openWeb(settings: Bool = false) {
        guard let origin = try? RelayClient.normalizedOrigin(relay) else { return }
        let path: String
        if let device = deviceID, let thread = threadID, !settings { path = "/devices/\(device)/threads/\(thread)" }
        else if let device = deviceID { path = "/devices/\(device)/workspaces" }
        else { path = "/" }
        if let url = URL(string: origin.absoluteString + path) { NSWorkspace.shared.open(url) }
    }
}
