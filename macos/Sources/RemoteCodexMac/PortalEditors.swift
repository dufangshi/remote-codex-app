import SwiftUI
import RemoteCodexCore

struct ThreadShareTarget {
    let deviceId: String
    let threadId: String
    let threadTitle: String?
    let workspaceId: String?
    let workspaceLabel: String?
}

struct AccessEditor: View {
    let device: Device?
    let thread: ThreadShareTarget?
    let grant: Grant?
    let isShare: Bool
    init(device: Device? = nil, thread: ThreadShareTarget? = nil, grant: Grant?, isShare: Bool) {
        self.device = device; self.thread = thread; self.grant = grant; self.isShare = isShare
    }
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var target = ""
    @State private var label = ""
    @State private var threadAccess = "read"
    @State private var workspaceAccess = "none"
    @State private var createThreads = false
    @State private var expires = ""
    @State private var failure: String?
    @State private var busy = false
    private var title: String { device != nil ? "Share device" : thread != nil ? "Invite someone" : "Edit shared access" }
    private var primaryLabel: String { device != nil ? "Share device" : thread != nil ? "Invite" : "Save permissions" }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2)
            if let device { Text(device.name).foregroundStyle(Palette.muted) }
            if let thread { Text(thread.threadTitle?.isEmpty == false ? thread.threadTitle! : "This thread").foregroundStyle(Palette.muted) }
            if device != nil || thread != nil { TextField("Username or email", text: $target) }
            TextField("Label (optional)", text: $label)
            Picker("Thread access", selection: $threadAccess) { Text("View only").tag("read"); Text("Collaborator").tag("control") }
            Picker("Workspace access", selection: $workspaceAccess) { Text("No workspace").tag("none"); Text("Workspace read").tag("read"); Text("Workspace write").tag("write") }.disabled(grant?.scope == "thread" && grant?.workspaceId == nil)
            if device != nil || (!isShare && grant?.scope != "thread") { Toggle("Allow creating threads", isOn: $createThreads) }
            if grant != nil { TextField("Expires at (ISO 8601, blank for no expiry)", text: $expires) }
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button(primaryLabel) { Task { await save() } }.disabled(busy || ((device != nil || thread != nil) && target.isEmpty)) }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 480).glassBar()
            .onAppear { if let grant { label = grant.label ?? ""; threadAccess = grant.threadAccess ?? "read"; workspaceAccess = grant.workspaceAccess ?? "none"; createThreads = grant.canCreateThreads ?? false; expires = grant.expiresAt ?? "" } }
    }
    private func save() async {
        guard let api = state.client else { return }; busy = true; defer { busy = false }
        do {
            struct Reply: Decodable {}
            var body: [String: Any] = ["label": label.isEmpty ? NSNull() : label as Any, "threadAccess": threadAccess, "workspaceAccess": workspaceAccess]
            let route: String
            let method: String
            if let device {
                route = "/relay/grants"; method = "POST"
                body.merge(["deviceId": device.id, "targetIdentifier": target, "scope": "device", "workspaceScope": "all", "workspaceIds": [String](), "canCreateThreads": createThreads]) { _, v in v }
            } else if let thread {
                route = "/relay/shares"; method = "POST"
                body.merge([
                    "deviceId": thread.deviceId, "threadId": thread.threadId, "targetIdentifier": target,
                    "threadTitle": (thread.threadTitle as Any?) ?? NSNull(),
                    "workspaceId": workspaceAccess == "none" ? NSNull() : ((thread.workspaceId as Any?) ?? NSNull()),
                    "workspaceLabel": workspaceAccess == "none" ? NSNull() : ((thread.workspaceLabel as Any?) ?? NSNull()),
                ]) { _, v in v }
            } else if let grant {
                route = "/relay/\(isShare ? "shares" : "grants")/\(grant.id)"; method = "PATCH"
                body["workspaceId"] = grant.workspaceId as Any? ?? NSNull()
                body["workspaceScope"] = grant.workspaceScope ?? "all"; body["workspaceIds"] = grant.workspaceIds ?? []
                body["expiresAt"] = expires.isEmpty ? NSNull() : expires as Any
            } else { return }
            let _: Reply = try await api.relay(route, method: method, body: body)
            await state.refreshPortal(); dismiss()
        } catch { failure = error.localizedDescription }
    }
}

struct RotateTokenView: View {
    let device: Device
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var factor = false
    @State private var verified = false
    @State private var secret = ""
    @State private var result: String?
    @State private var failure: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Replace device token?").font(.title2)
            Text("The current connection will close. Update the device setup with the new token to reconnect. Existing workspaces and threads are kept.")
            if let result { Button("Copy new setup command") { copy(result) }; Text("The token is held only in memory until this dialog closes.").font(.caption) }
            else {
                if !verified { SecureField(factor ? "Authenticator or recovery code" : "Account password", text: $secret).textFieldStyle(.roundedBorder) }
                Button("Replace token", role: .destructive) { Task { await rotate() } }.disabled(busy || (!verified && secret.isEmpty))
            }
            if let failure { Text(failure).foregroundStyle(.red) }; Button("Close") { secret = ""; result = nil; dismiss() }
        }.padding(28).frame(width: 480).glassBar().task {
            struct Security: Decodable { let authenticatorEnabled: Bool; let recentlyVerified: Bool }
            do { if let api = state.client { let value: Security = try await api.relay("/relay/account/security"); factor = value.authenticatorEnabled; verified = value.recentlyVerified } } catch { failure = error.localizedDescription }
        }
    }
    private func rotate() async {
        guard let api = state.client else { return }; busy = true; defer { busy = false; secret = "" }
        do {
            struct Empty: Decodable {}; struct Token: Decodable { let token: String }
            if !verified { let _: Empty = try await api.relay("/relay/account/security/reauth", method: "POST", body: [factor ? "code" : "password": secret]); verified = true }
            let value: Token = try await api.relay("/relay/devices/\(device.id)/token", method: "POST")
            result = SetupCommand.make(origin: api.origin, token: value.token, windows: false); await state.refreshPortal()
        } catch { failure = error.localizedDescription }
    }
}

struct ImportSessionView: View {
    private struct Candidate: Decodable, Identifiable { let sessionId: String; let title: String; let cwd: String?; var id: String { sessionId } }
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var backends: [AgentBackend] = []
    @State private var agents: [ModelOption] = []
    @State private var provider = "codex"
    @State private var agent = ""
    @State private var session = ""
    @State private var search = ""
    @State private var candidates: [Candidate] = []
    @State private var failure: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import a backend session").font(.title2)
            Picker("Backend", selection: $provider) { ForEach(backends, id: \.provider) { Text($0.displayName).tag($0.provider) } }
            if provider == "acp" { Picker("Agent", selection: $agent) { ForEach(agents) { Text($0.displayName).tag($0.id) } } }
            TextField("Search title, ID, or workspace", text: $search).textFieldStyle(.roundedBorder)
            ScrollView { VStack(spacing: 4) {
                let filtered = candidates.filter { search.isEmpty || ($0.title + $0.sessionId + ($0.cwd ?? "")).localizedCaseInsensitiveContains(search) }
                if filtered.isEmpty { Text("No sessions found").foregroundStyle(Palette.muted).padding(24) }
                ForEach(filtered) { entry in
                Button { session = entry.sessionId } label: { VStack(alignment: .leading) { Text(entry.title); Text(entry.cwd ?? entry.sessionId).font(.caption).foregroundStyle(Palette.muted) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(MenuRowStyle(selected: entry.sessionId == session))
            } } }.frame(height: 240)
            TextField("Session ID", text: $session).textFieldStyle(.roundedBorder)
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Import session") { Task { await importSession() } }.disabled(session.isEmpty || busy) }
        }.padding(24).frame(width: 560).glassBar()
            .task {
                do { if let api = state.client, let device = state.deviceID { backends = try await api.device(device, "/api/agent-runtimes"); agents = try await api.device(device, "/api/agent-runtimes/acp/agents"); agent = agents.first?.id ?? "" } } catch { failure = error.localizedDescription }
            }.task(id: provider + agent) { await load() }
    }
    private func load() async {
        guard let api = state.client, let device = state.deviceID else { return }
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "provider", value: provider), URLQueryItem(name: "agentId", value: provider == "acp" ? agent : provider)]
        do { candidates = try await api.device(device, "/api/threads/import-candidates?" + (query.percentEncodedQuery ?? "")); failure = nil } catch { failure = error.localizedDescription }
    }
    private func importSession() async {
        guard let api = state.client, let device = state.deviceID else { return }; busy = true; defer { busy = false }
        do { let result: ThreadDetail = try await api.device(device, "/api/threads/import", method: "POST", body: ["sessionId": session, "provider": provider, "agentId": provider == "acp" ? agent : provider]); await state.refreshLists(); state.selectReference(device, result.thread.id); dismiss() } catch { failure = error.localizedDescription }
    }
}
