import SwiftUI
import RemoteCodexCore

struct NativeSettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @State private var tab = "Preferences"
    @State private var supervisor: [String: Any] = [:]
    @State private var harnesses: [[String: Any]] = []
    @State private var profiles: [[String: Any]] = []
    @State private var active: [String: String] = [:]
    @State private var jobs: [String: Any] = [:]
    @State private var harness = "codex"
    @State private var error: String?
    @State private var notice: String?
    @State private var busy = false
    @State private var confirm: SettingsAction?
    @State private var editing = false
    @State private var name = ""
    @State private var baseURL = ""
    @State private var key = ""
    @State private var apiType = "responses"
    @State private var template = ""
    private let tabs = ["Preferences", "Device", "Harnesses", "Upstreams", "Templates"]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings").font(.system(size: 23, weight: .semibold))
                    Text(state.deviceName + " · " + (URL(string: state.relay)?.host ?? state.relay)).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                IconButton(title: "Close settings", icon: "xmark") { dismiss() }
            }.padding(24)
            HStack(spacing: 6) {
                ForEach(tabs, id: \.self) { item in
                    Button(item) { tab = item }.buttonStyle(WorkbenchButton(selected: tab == item))
                }
                Spacer()
            }.padding(.horizontal, 20).padding(.bottom, 12)
            Divider().overlay(Palette.border)
            if let error { InlineError(message: error) { self.error = nil } }
            if let notice { Text(notice).font(.callout).foregroundStyle(Palette.accent).padding(12) }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch tab {
                    case "Preferences": preferences
                    case "Device": device
                    case "Harnesses": harnessPanel
                    case "Upstreams": upstreams
                    default: templates
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Palette.border)
            HStack {
                Label("Native SwiftUI · encrypted device connection", systemImage: "checkmark.shield").font(.caption).foregroundStyle(Palette.muted)
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }.frame(width: 760, height: 640).background(Palette.panel).foregroundStyle(Palette.text)
            .task(id: tab) { if tab != "Preferences" { await load() } }
            .alert(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
                Button("Cancel", role: .cancel) { confirm = nil }
                Button("Continue", role: confirm?.method == "DELETE" ? .destructive : nil) {
                    if let action = confirm { Task { await perform(action) } }; confirm = nil
                }
            } message: { Text(confirm?.detail ?? "") }
            .sheet(isPresented: $editing) { upstreamEditor }
    }
    private var preferences: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionTitle("Appearance", subtitle: "The same green-neutral palette as the web workspace.")
            Picker("Theme", selection: $appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            }.pickerStyle(.segmented).frame(width: 330)
            Divider()
            sectionTitle("Keyboard", subtitle: "⌘N  New chat     ⌘F  Search     ⌘⇧E  Files\n⌘Return  Send     ⌘S  Save file     ⌘,  Settings")
            Divider()
            sectionTitle("Account", subtitle: "Session credentials and device identities stay in macOS Keychain.")
            Button("Sign Out", role: .destructive) {
                confirm = SettingsAction(title: "Sign out?", detail: "Save your files and drafts first. Existing conversations remain on the device.", path: "signout")
            }
        }
    }
    private var device: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Supervisor", subtitle: "Manage the runtime on " + state.deviceName + ".")
            LabeledContent("Running version", value: supervisor["runningVersion"] as? String ?? "Unknown")
            LabeledContent("Installed version", value: supervisor["installedVersion"] as? String ?? "Unknown")
            LabeledContent("Latest version", value: supervisor["latestVersion"] as? String ?? "Check for updates")
            if let reason = supervisor["reason"] as? String { Text(reason).font(.callout).foregroundStyle(Palette.muted) }
            HStack {
                Button("Check for Updates") { Task { await perform(SettingsAction(title: "Check", path: "supervisor/check")) } }
                    .disabled(busy || supervisor["canUpdate"] as? Bool != true)
                Button("Update…") { confirm = SettingsAction(title: "Update Supervisor?", detail: "The device may disconnect briefly. Running tasks will be handled by its managed updater.", path: "supervisor/update") }.disabled(busy || supervisor["canUpdate"] as? Bool != true)
                Button("Restart…") { confirm = SettingsAction(title: "Restart Supervisor?", detail: "This restarts the selected device's service.", path: "supervisor/restart") }.disabled(busy || supervisor["canRestart"] as? Bool != true)
            }
            status(supervisor["job"] as? [String: Any])
            Button("Refresh Status") { Task { await load() } }.disabled(busy)
        }
    }
    private var harnessPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Harnesses", subtitle: "Install, update and reload each agent independently.")
            ForEach(harnesses.indices, id: \.self) { index in
                let row = harnesses[index], id = row["id"] as? String ?? ""
                VStack(alignment: .leading, spacing: 14) {
                    Text(row["name"] as? String ?? id).font(.headline)
                    ForEach(["base", "adapter"], id: \.self) { component in
                        if let installation = row[component] as? [String: Any] {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(component == "base" ? "Harness" : "ACP adapter").font(.callout)
                                    Text(installation["version"] as? String ?? "Not installed").font(.caption).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                let action = installation["installed"] as? Bool == false ? "install" : "update"
                                Button(action.capitalized + "…") {
                                    confirm = SettingsAction(title: action.capitalized + " " + id + "?", detail: "This changes the selected harness on " + state.deviceName + ".", path: "harnesses/" + id, body: ["action": action, "component": component])
                                }.disabled(busy || !(installation[action == "install" ? "canInstall" : "canUpdate"] as? Bool ?? false))
                            }
                        }
                    }
                    status(jobs[id] as? [String: Any] ?? row["job"] as? [String: Any])
                }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            Button("Refresh Status") { Task { await load() } }.disabled(busy)
        }
    }
    private var upstreams: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                sectionTitle("Upstreams", subtitle: "Separate configurations for each harness.")
                Spacer(); Button("Add Upstream") { name = ""; baseURL = ""; key = ""; editing = true }
            }
            Picker("Harness", selection: $harness) {
                Text("Codex").tag("codex"); Text("Claude Code").tag("claude"); Text("Gemini CLI").tag("gemini"); Text("Grok Build").tag("grok")
            }.pickerStyle(.segmented)
            let filtered = profiles.filter { $0["harness"] as? String == harness }
            ForEach(filtered.indices, id: \.self) { index in
                let p = filtered[index], id = p["id"] as? String ?? ""
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(p["name"] as? String ?? "Upstream").font(.headline); Spacer(); if active[harness] == id { Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.accent) } }
                    Text(p["baseUrl"] as? String ?? "").font(.caption).foregroundStyle(Palette.muted)
                    HStack {
                        Button("Use Upstream") { confirm = SettingsAction(title: "Switch upstream?", detail: "Applies this profile and reloads idle harness sessions. Running turns keep their current configuration.", path: "upstreams/" + id, body: ["action": "activate"]) }.disabled(active[harness] == id || busy)
                        Button("Test Connection…") { confirm = SettingsAction(title: "Test connection?", detail: "Sends a small inference request. Provider charges may apply.", path: "upstreams/" + id, body: ["action": "test"]) }
                        Spacer()
                        Button("Delete…", role: .destructive) { confirm = SettingsAction(title: "Delete upstream?", detail: "Removes this profile. If active, the Supervisor restores its prior configuration.", path: "upstreams/" + id, method: "DELETE") }
                    }
                }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if filtered.isEmpty { Text("No upstream profiles for this harness.").foregroundStyle(Palette.muted) }
        }
    }
    private var templates: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Device templates", subtitle: "Import schemaVersion 1 JSON. Models are discovered from the upstream; no model field is required.")
            NativeComposer(text: $template, code: true, identifier: "templateEditor") {}.frame(height: 230).padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Validate") { templateAction(apply: false) }
                Button("Apply Template…") { templateAction(apply: true) }.buttonStyle(.borderedProminent)
            }.disabled(template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            Text("Template keys are sent only through the encrypted connection to this device.").font(.caption).foregroundStyle(Palette.muted)
        }
    }
    private var upstreamEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add " + harness.capitalized + " upstream").font(.title2.bold())
            TextField("Name", text: $name)
            TextField("Base URL", text: $baseURL)
            SecureField("API key", text: $key)
            if ["codex", "grok"].contains(harness) {
                Picker("API format", selection: $apiType) { Text("Responses").tag("responses"); Text("Chat Completions").tag("chat_completions") }
            }
            Text("Available models will be discovered from the upstream.").font(.caption).foregroundStyle(Palette.muted)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Cancel") { key = ""; editing = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    Task {
                        await perform(SettingsAction(title: "Save", path: "upstreams", body: ["name": name, "harness": harness, "baseUrl": baseURL, "apiKey": key, "apiType": apiType, "authType": "api_key"]))
                        if error == nil { key = ""; editing = false }
                    }
                }.disabled(name.isEmpty || baseURL.isEmpty || key.isEmpty || busy)
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 480).background(Palette.panel)
    }
    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 17, weight: .semibold)); Text(subtitle).font(.callout).foregroundStyle(Palette.muted) }
    }
    @ViewBuilder private func status(_ job: [String: Any]?) -> some View {
        if let job {
            Text([job["state"], job["phase"], job["error"]].compactMap { $0 as? String }.joined(separator: " · ")).font(.caption).foregroundStyle(Palette.muted)
        }
    }
    private func api(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Any {
        guard let client = state.client, let device = state.deviceID else { throw APIError("Select a device first.") }
        let bytes = try await client.deviceData(device, "/api/management/" + path, method: method, body: try body.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data())
        return bytes.isEmpty ? [:] : try JSONSerialization.jsonObject(with: bytes)
    }
    private func load() async {
        busy = true; error = nil; defer { busy = false }
        do {
            switch tab {
            case "Device": supervisor = try await api("supervisor") as? [String: Any] ?? [:]
            case "Harnesses":
                harnesses = try await api("harnesses") as? [[String: Any]] ?? []
                jobs = try await api("jobs") as? [String: Any] ?? [:]
            case "Upstreams":
                let data = try await api("upstreams") as? [String: Any] ?? [:]
                profiles = data["profiles"] as? [[String: Any]] ?? []; active = data["active"] as? [String: String] ?? [:]
            default: break
            }
        } catch { self.error = error.localizedDescription }
    }
    private func perform(_ action: SettingsAction) async {
        if action.path == "signout" { await state.signOut(); if !state.authenticated { dismiss() }; return }
        busy = true; error = nil; notice = nil
        do {
            _ = try await api(action.path, method: action.method, body: action.method == "DELETE" ? nil : action.body)
            await load(); notice = "Request accepted. Refresh status to see background job progress."
        } catch { self.error = error.localizedDescription }
        busy = false
    }
    private func templateAction(apply: Bool) {
        do {
            guard let object = try JSONSerialization.jsonObject(with: Data(template.utf8)) as? [String: Any] else { throw APIError("Template must be a JSON object.") }
            let action = SettingsAction(title: "Apply device template?", detail: "Installs the listed harnesses and changes upstream configuration on " + state.deviceName + ".", path: "templates", body: ["template": object["template"] ?? object, "apply": apply])
            if apply { confirm = action } else { Task { await perform(action) } }
        } catch { self.error = error.localizedDescription }
    }
}

private struct SettingsAction {
    var title: String
    var detail = ""
    var path: String
    var method = "POST"
    var body: [String: Any] = [:]
}
