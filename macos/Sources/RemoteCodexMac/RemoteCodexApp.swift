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
                .task { appDelegate.state = state; await state.restore() }
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
    @State private var model = ""
    @State private var effort = ""
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Model").font(.headline); Spacer(); IconButton(title: "Close model picker", icon: "xmark") { state.showingThreadSettings = false } }
            TextField("Search models", text: $search).textFieldStyle(.plain).padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(state.threadModels.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) || $0.model.localizedCaseInsensitiveContains(search) }) { choice in
                        Button {
                            model = choice.model
                            if !choice.supportedReasoningEfforts.contains(where: { $0.reasoningEffort == effort }) { effort = "" }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) { Text(choice.displayName); Text(choice.model).font(.caption).foregroundStyle(Palette.muted) }
                                Spacer(); if model == choice.model { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(model == choice.model ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if state.threadModels.isEmpty { ProgressView("Loading available models…").padding() }
                }
            }.scrollIndicators(.never).frame(height: 220)
            Divider()
            Text("Reasoning effort").font(.caption).foregroundStyle(Palette.muted)
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    effortButton("Auto", value: "")
                    ForEach(state.threadModels.first(where: { $0.model == model })?.supportedReasoningEfforts ?? []) { effortButton($0.reasoningEffort.capitalized, value: $0.reasoningEffort) }
                }
            }.scrollIndicators(.never)
            if let error = state.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Text(state.active ? "Available when this turn finishes." : "Applies to this conversation").font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                Button("Apply") { Task { await state.saveThreadSettings(model: model, effort: effort) } }.buttonStyle(WorkbenchButton(selected: true)).disabled(state.busy || model.isEmpty || state.active)
            }
        }.padding(16).frame(width: 370).background(Palette.panel)
            .onAppear {
                model = state.detail?.thread.model ?? ""
                let current = state.detail?.thread.reasoningEffort ?? ""
                effort = current == "auto" ? "" : current
            }
    }
    private func effortButton(_ title: String, value: String) -> some View {
        Button(title) { effort = value }.buttonStyle(WorkbenchButton(selected: effort == value))
            .background(effort == value ? Palette.selected : Palette.surface, in: RoundedRectangle(cornerRadius: 7))
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
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add a remote workspace").font(.title2.weight(.semibold))
            Text("Use an existing absolute directory on \(state.deviceName), not on this Mac.").foregroundStyle(.secondary)
            TextField("Remote path", text: $state.workspacePath)
            TextField("Workspace name", text: $state.workspaceLabel)
            if let error = state.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { state.showingNewWorkspace = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Workspace") { Task { await state.createWorkspace() } }.buttonStyle(.borderedProminent)
                    .disabled(state.busy || state.workspacePath.isEmpty || state.workspaceLabel.isEmpty)
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 450)
    }
}
