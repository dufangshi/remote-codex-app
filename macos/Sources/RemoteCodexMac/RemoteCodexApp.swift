import SwiftUI
import RemoteCodexCore

@main
struct RemoteCodexApp: App {
    @NSApplicationDelegateAdaptor(NativeAppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        Window("Remote Codex", id: "main") {
            Group {
                if state.authenticated { NativeWorkbench() }
                else {
                    VStack(spacing: 0) {
                        if let error = state.error { InlineError(message: error) { state.error = nil } }
                        SignInView()
                    }
                }
            }.environmentObject(state).frame(minWidth: 900, minHeight: 620)
                .tint(Palette.accent).foregroundStyle(Palette.text)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .task { appDelegate.state = state; await state.restore(); appDelegate.restoreNotification() }
                .onChange(of: state.authenticated) { _, authenticated in if authenticated { appDelegate.restoreNotification() } }
        }
        .defaultSize(width: 1260, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { Task { await state.prepareNewThread() } }.keyboardShortcut("n").disabled(state.workspaceID == nil)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { state.showingSettings = true }.keyboardShortcut(",").disabled(!state.authenticated)
            }
            CommandGroup(after: .toolbar) {
                Button("Search Conversation") { state.showingSearch.toggle() }.keyboardShortcut("f")
                Button("Toggle Sidebar") { state.showingSidebar.toggle() }.keyboardShortcut("s", modifiers: [.command, .control])
                Button("Files") { state.contentMode = state.contentMode == "files" ? "chat" : "files" }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Refresh") { Task { await state.refreshLists(); await state.refreshThread() } }.keyboardShortcut("r")
                Button("Open in Browser") { state.openWeb() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

struct SignInView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 72) {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "terminal.fill").font(.system(size: 56)).foregroundStyle(.tint)
                Text("Your workspace.\nAnywhere.").font(.system(size: 42, weight: .semibold, design: .rounded))
                Text("REMOTE CODEX FOR MAC").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Text("A native home for your devices,\nconversations and coding agents.").font(.title3).foregroundStyle(.secondary)
                Label("End-to-end encrypted", systemImage: "checkmark.shield").font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: 380, alignment: .leading)
            VStack(alignment: .leading, spacing: 18) {
                Text(state.challenge ? "Verify your identity" : "Connect to your relay").font(.title2.weight(.semibold))
                if state.challenge {
                    Text("Enter your authenticator or recovery code. Passkey-only sign-in is not supported in this native preview.").foregroundStyle(.secondary)
                    TextField("Verification code", text: $state.code).accessibilityIdentifier("verificationCode")
                } else {
                    Text("Use your existing Remote Codex account.").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Relay address").font(.caption).foregroundStyle(.secondary)
                        TextField("https://relay.example.com", text: $state.relay).accessibilityIdentifier("relayOrigin")
                    }
                    TextField("Username or email", text: $state.identifier).accessibilityIdentifier("username")
                    SecureField("Password", text: $state.password).accessibilityIdentifier("password")
                }
                Button { Task { await state.signIn() } } label: {
                    HStack { Spacer(); if state.busy { ProgressView().controlSize(.small) }; Text(state.challenge ? "Verify and connect" : "Sign in"); Spacer() }
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    .disabled(state.busy || (state.challenge ? state.code.isEmpty : state.identifier.isEmpty || state.password.isEmpty))
                    .accessibilityIdentifier("signIn")
                if state.challenge {
                    Button("Back to sign in") { state.challenge = false; state.code = "" }
                }
                Text("Credentials stay in your Keychain. Devices are verified and encrypted before content is loaded.").font(.caption).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder).controlSize(.large).padding(30)
                .frame(width: 380).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.primary.opacity(0.06)))
        }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ThreadSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var section: String?
    private var model: String { state.detail?.thread.model ?? "" }
    private var effort: String { state.detail?.thread.reasoningEffort ?? "auto" }
    private var choices: [ReasoningOption] { state.threadModels.first { $0.model == model }?.supportedReasoningEfforts ?? [] }
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section == "model" ? "Model" : "Effort").font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.horizontal, 12).padding(.vertical, 6)
                    if section == "model" {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(state.threadModels) { choice in
                                    Button {
                                        let next = choice.supportedReasoningEfforts.contains { $0.reasoningEffort == effort } ? effort : (choice.defaultReasoningEffort ?? "auto")
                                        Task { await state.saveThreadSettings(model: choice.model, effort: next) }
                                    } label: { menuLabel(choice.displayName, selected: model == choice.model) }
                                        .buttonStyle(MenuRowStyle(selected: model == choice.model))
                                }
                            }
                        }.scrollIndicators(.never).frame(height: min(288, CGFloat(state.threadModels.count) * 36))
                        if state.threadModels.isEmpty { ProgressView().padding(12) }
                    } else {
                        ForEach(choices) { entry in
                            Button { Task { await state.saveThreadSettings(model: model, effort: entry.reasoningEffort) } } label: {
                                menuLabel(entry.reasoningEffort.capitalized, selected: effort == entry.reasoningEffort)
                            }.buttonStyle(MenuRowStyle(selected: effort == entry.reasoningEffort))
                        }
                        if choices.contains(where: { $0.reasoningEffort == "ultra" }) {
                            Text("Higher effort can consume usage limits faster.").font(.system(size: 12)).foregroundStyle(Palette.muted).padding(12)
                        }
                    }
                }.padding(6).frame(width: section == "model" ? 208 : 176).composerMenuSurface()
            }
            VStack(spacing: 2) {
                Button { section = section == "model" ? nil : "model" } label: {
                    HStack { Text("Model"); Spacer(); Text(state.threadModels.first { $0.model == model }?.displayName ?? model).lineLimit(1).foregroundStyle(Palette.muted); Image(systemName: "chevron.right").font(.system(size: 11)) }
                }.buttonStyle(MenuRowStyle())
                Button { section = section == "effort" ? nil : "effort" } label: {
                    HStack { Text("Effort"); Spacer(); Text(effort.capitalized).foregroundStyle(Palette.muted); Image(systemName: "chevron.right").font(.system(size: 11)) }
                }.buttonStyle(MenuRowStyle()).disabled(choices.isEmpty)
                if state.busy { ProgressView().controlSize(.small) }
                if let error = state.error { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
            }.padding(6).frame(width: 216).composerMenuSurface()
        }.fixedSize(horizontal: false, vertical: true).disabled(state.busy || state.active)
    }
    private func menuLabel(_ title: String, selected: Bool) -> some View {
        HStack { Text(title).lineLimit(1); Spacer(); if selected { Image(systemName: "checkmark").font(.system(size: 12)) } }
    }
}

struct NewThreadView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start a conversation").font(.title2.weight(.semibold))
            Form {
                TextField("Title (optional)", text: $state.newTitle)
                Picker("Agent", selection: $state.agentID) {
                    Text("Select agent").tag("")
                    ForEach(state.agents) { Text($0.displayName).tag($0.id) }
                }
                Picker("Model", selection: $state.modelID) {
                    Text(state.models.isEmpty ? "Loading available models…" : "Select model").tag("")
                    ForEach(state.models) { Text($0.displayName).tag($0.model) }
                }
                Picker("Reasoning", selection: $state.effort) {
                    Text("Auto").tag("")
                    ForEach(state.selectedModel?.supportedReasoningEfforts ?? []) { Text($0.reasoningEffort.capitalized).tag($0.reasoningEffort) }
                }
                Picker("Permissions", selection: $state.approvalMode) {
                    Text("Ask before actions").tag("guarded")
                    Text("Full access").tag("yolo")
                }
            }
            if let error = state.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel") { state.showingNewThread = false }.keyboardShortcut(.cancelAction)
                Spacer()
                if state.busy { ProgressView().controlSize(.small) }
                Button("Create Thread") { Task { await state.createThread() } }.buttonStyle(.borderedProminent)
                    .disabled(state.busy || state.modelID.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 460)
            .task(id: state.agentID) { await state.loadModels() }
            .onChange(of: state.modelID) { _, _ in state.effort = "" }
    }
}

struct NewWorkspaceView: View {
    @EnvironmentObject var state: AppState
    @State private var mode = "path"
    @State private var devHome = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add a remote workspace").font(.title2.weight(.semibold))
            Text("Choose a folder, existing path, or Git repository on \(state.deviceName).").foregroundStyle(.secondary)
            Picker("Source", selection: $mode) { Text("New folder").tag("folder"); Text("Existing path").tag("path"); Text("Git repository").tag("git") }.pickerStyle(.segmented)
            if mode == "folder" { Text("Create under \(devHome)").font(.caption).foregroundStyle(.secondary) }
            TextField(mode == "git" ? "Git repository URL" : mode == "folder" ? "Folder name" : "Absolute remote path", text: $state.workspacePath)
            TextField("Workspace name (optional)", text: $state.workspaceLabel)
            if let error = state.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { state.showingNewWorkspace = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Workspace") {
                    var input: [String: Any] = [:]
                    if !state.workspaceLabel.isEmpty { input["label"] = state.workspaceLabel }
                    if mode == "git" { input["gitUrl"] = state.workspacePath }
                    else { input["absPath"] = mode == "folder" ? devHome + "/" + state.workspacePath : state.workspacePath }
                    Task { await state.createWorkspace(input: input) }
                }.buttonStyle(.borderedProminent).disabled(state.busy || state.workspacePath.isEmpty || (mode == "folder" && devHome.isEmpty))
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 500).task {
            struct Settings: Decodable { let devHome: String }
            if let api = state.client, let device = state.deviceID { do { let value: Settings = try await api.device(device, "/api/config/workspace-settings"); devHome = value.devHome } catch { state.error = error.localizedDescription } }
        }
    }
}
