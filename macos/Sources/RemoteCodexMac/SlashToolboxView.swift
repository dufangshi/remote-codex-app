import SwiftUI
import RemoteCodexCore

struct SlashToolboxView: View {
    @EnvironmentObject var state: AppState
    let close: () -> Void
    @State private var items: [[String: String]] = []
    @State private var capabilities: [String: [String: Bool]] = [:]
    @State private var panel = "root"
    @State private var rows: [[String: Any]] = []
    @State private var loading = false
    @State private var failure: String?
    @State private var fast = false
    @State private var plan = false
    @State private var objective = ""
    @State private var budget = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if panel != "root" {
                HStack { Button { panel = "root"; failure = nil } label: { Label("Back", systemImage: "chevron.left") }; Spacer(); Text(panel.capitalized).font(.headline) }
            }
            if loading { ProgressView().controlSize(.small) }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if panel == "root" {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            let action = item["action"] ?? ""
                            if available(action) {
                                row(item["command"] ?? item["label"] ?? action, status: status(action)) { Task { await activate(item) } }
                                    .disabled(action == "unsupported" || loading || (["fork", "compact"].contains(action) && state.active))
                                    .help(item["description"] ?? "")
                            }
                        }
                        if items.isEmpty && !loading { Text("No backend tools available for this conversation.").font(.caption).foregroundStyle(Palette.muted) }
                    } else if panel == "fork" {
                        row("Fork latest", status: "CREATE") { Task { await forkLatest() } }.disabled(state.active)
                        Divider()
                        Text("Fork from selected turn").font(.caption).foregroundStyle(Palette.muted).padding(8)
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, value in
                            row("Turn \((value["turnIndex"] as? Int ?? 0) + 1)", status: value["status"] as? String ?? "") {
                                if let id = value["turnId"] as? String { Task { await state.fork(turn: id); if state.error == nil { close() } } }
                            }.disabled(state.active || state.busy)
                        }
                    } else if panel == "goal" {
                        Text("New goal").font(.headline)
                        TextField("Objective", text: $objective, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
                        TextField("Token budget (optional)", text: $budget).textFieldStyle(.roundedBorder)
                        Button("Create goal") { Task { await createGoal() } }.disabled(objective.isEmpty || loading)
                        Text("Existing goal").font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                            Text(item["objective"] as? String ?? "").textSelection(.enabled)
                            Text(item["status"] as? String ?? "").font(.caption).foregroundStyle(Palette.muted)
                        }
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item["name"] as? String ?? item["eventName"] as? String ?? item["command"] as? String ?? "Item").font(.callout)
                                if let description = item["description"] as? String { Text(description).font(.caption).foregroundStyle(Palette.muted).lineLimit(4) }
                                if let auth = item["authStatus"] as? String { Text(auth).font(.caption).foregroundStyle(Palette.muted) }
                                if let tools = item["tools"] as? [[String: Any]] { Text("\(tools.count) tools").font(.caption).foregroundStyle(Palette.muted) }
                                if let command = item["command"] as? String { Text(command).font(.caption.monospaced()).textSelection(.enabled) }
                                if panel == "skills", let name = item["name"] as? String {
                                    Button("Insert /$" + name) { state.draft += "/$" + name + " "; close() }.disabled(item["enabled"] as? Bool == false)
                                }
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                        }
                        if rows.isEmpty && !loading { Text("No \(panel) configured.").foregroundStyle(Palette.muted).padding(10) }
                        if panel == "mcp" || panel == "hooks" {
                            // Editing these is web-only; the native Settings sheet holds local
                            // display preferences and cannot configure them.
                            Button("Manage in browser…") { close(); state.openWeb() }
                        }
                    }
                }
            }.scrollIndicators(.never).frame(height: panel == "root" ? min(360, CGFloat(max(1, items.filter { available($0["action"] ?? "") }.count)) * 38) : 360)
        }.padding(8).frame(width: 288).fixedSize(horizontal: false, vertical: true)
            .glassPanel(cornerRadius: 16).shadow(color: .black.opacity(0.22), radius: 16, y: 8).buttonStyle(WorkbenchButton())
            .task { await loadRoot() }
    }
    private func row(_ title: String, status: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Text(status).font(.system(size: 11)).tracking(1.4).foregroundStyle(Palette.muted) }
        }.buttonStyle(MenuRowStyle())
    }
    private func available(_ action: String) -> Bool {
        switch action {
        case "fast": return capabilities["controls"]?["performanceMode"] == true
        case "compact": return capabilities["turns"]?["compact"] == true
        case "goal": return capabilities["controls"]?["goals"] == true
        case "fork": return capabilities["branching"]?["fork"] == true
        case "skills": return capabilities["management"]?["skills"] == true
        case "mcp": return capabilities["management"]?["mcpStatus"] == true
        case "hooks": return capabilities["management"]?["hooks"] == true
        default: return true
        }
    }
    private func status(_ action: String) -> String { action == "fast" ? (fast ? "ON" : "OFF") : action == "unsupported" ? "UNAVAILABLE" : action == "compact" ? "RUN" : action == "prompt" ? "COMPOSE" : "OPEN" }
    private func request(_ suffix: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Any {
        guard let client = state.client, let device = state.deviceID, let thread = state.threadID else { throw APIError("Choose a conversation.") }
        let bytes = try await client.deviceData(device, "/api/threads/\(thread)" + suffix, method: method, body: body.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data())
        return try JSONSerialization.jsonObject(with: bytes)
    }
    private func loadRoot() async {
        loading = true; defer { loading = false }
        do {
            let snapshot = try await request("/capabilities") as? [String: Any] ?? [:]
            capabilities = snapshot["effectiveCapabilities"] as? [String: [String: Bool]] ?? [:]
            items = (snapshot["toolboxItems"] as? [[String: Any]] ?? []).map { $0.compactMapValues { $0 as? String } }.filter { !($0["command"] ?? "").hasPrefix("/$") }
            let detail = try await request("?limit=1&view=summary") as? [String: Any]
            let thread = detail?["thread"] as? [String: Any]
            fast = thread?["fastMode"] as? Bool ?? false; plan = thread?["collaborationMode"] as? String == "plan"
        } catch { failure = error.localizedDescription }
    }
    private func setting(_ body: [String: Any]) async {
        loading = true; defer { loading = false }
        do { _ = try await request("/settings", method: "PATCH", body: body); await state.refreshThread(); failure = nil }
        catch { failure = error.localizedDescription }
    }
    private func activate(_ item: [String: String]) async {
        let action = item["action"] ?? ""
        if action == "prompt" { state.draft += (item["command"] ?? "") + " "; close(); return }
        if action == "fast" { await setting(["fastMode": !fast]); if failure == nil { fast.toggle() }; return }
        if action == "harness" { close(); state.openWeb(); return }
        loading = true; failure = nil; defer { loading = false }
        do {
            if action == "compact" { _ = try await request("/compact", method: "POST", body: [:]); close(); await state.refreshThread(); return }
            panel = action
            let path = ["fork": "/fork-turns", "skills": "/skills", "mcp": "/mcp-servers", "hooks": "/hooks", "goal": "/goal"][action]
            guard let path else { return }
            let result = try await request(path)
            if let array = result as? [[String: Any]] { rows = array }
            else if let object = result as? [String: Any] {
                let key = ["mcp": "servers", "goal": "goal"][action] ?? action
                rows = object[key] as? [[String: Any]] ?? (object[key] as? [String: Any]).map { [$0] } ?? []
            }
        } catch { failure = error.localizedDescription }
    }
    private func forkLatest() async {
        loading = true; defer { loading = false }
        do {
            let result = try await request("/fork", method: "POST", body: ["mode": "latest"]) as? [String: Any]
            if let detail = result?["thread"] as? [String: Any], let thread = detail["thread"] as? [String: Any], let id = thread["id"] as? String {
                await state.refreshLists(); state.threadID = id; close()
            }
        } catch { failure = error.localizedDescription }
    }
    private func createGoal() async {
        loading = true; defer { loading = false }
        do {
            var body: [String: Any] = ["objective": objective]
            if !budget.isEmpty { guard let value = Int(budget), value > 0 else { throw APIError("Use a positive token budget.") }; body["tokenBudget"] = value }
            _ = try await request("/goal", method: "POST", body: body); close()
        } catch { failure = error.localizedDescription }
    }
}
