import SwiftUI
import RemoteCodexCore

@main
struct RemoteCodexApp: App {
    @StateObject private var state = AppState()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        Window("Remote Codex", id: "main") {
            RootView().environmentObject(state)
                .frame(minWidth: 940, minHeight: 640)
                .tint(Color(red: 0.23, green: 0.39, blue: 0.94))
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .task { await state.restore() }
        }
        .defaultSize(width: 1260, height: 820)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thread") { Task { await state.prepareNewThread() } }
                    .keyboardShortcut("n").disabled(state.workspaceID == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await state.refreshPortal(); await state.refreshThread() } }
                    .keyboardShortcut("r")
                Button("Open in Browser") { state.openWeb() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        Settings {
            Form {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Section("Connection") {
                    LabeledContent("Relay", value: state.relay)
                    LabeledContent("Transport", value: "HPKE · AES-256-GCM")
                    Text("Session tokens and device identity pins are stored in macOS Keychain.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Native preview") {
                    Text("Chat updates every second while running, every four seconds while idle, and less often when idle in the background. Account security, provider administration and advanced thread tools are available in the web client.")
                    Button("Open Web Client") { state.openWeb(settings: true) }
                    Button("Sign Out", role: .destructive) { Task { await state.signOut() } }
                }
            }.formStyle(.grouped).frame(width: 480, height: 400)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Group {
            if state.authenticated { WorkspaceView() } else { SignInView() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = state.error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { state.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
                }.padding(12).background(.orange.opacity(0.10))
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

struct WorkspaceView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill").font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote Codex").font(.headline)
                        Text("NATIVE PREVIEW").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(18)
                List(selection: $state.deviceID) {
                    Section("Devices") {
                        ForEach(state.devices) { device in
                            HStack {
                                Image(systemName: "desktopcomputer")
                                Text(device.name).lineLimit(1)
                                Spacer()
                                Circle().fill(device.connected == true ? .green : .secondary.opacity(0.4)).frame(width: 6, height: 6)
                            }.padding(.vertical, 5).tag(device.id)
                        }
                    }
                }.listStyle(.sidebar)
                Divider()
                HStack {
                    SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain)
                    Text(URL(string: state.relay)?.host ?? "Relay").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { Task { await state.refreshPortal() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh devices")
                }.padding(16)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Picker("Workspace", selection: $state.workspaceID) {
                        Text("Choose workspace").tag(String?.none)
                        ForEach(state.workspaces) { Text($0.label).tag(Optional($0.id)) }
                    }.labelsHidden()
                    Button { state.showingNewWorkspace = true } label: { Image(systemName: "folder.badge.plus") }.buttonStyle(.plain).help("Add remote workspace")
                }.padding(14)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a thread", text: $state.query).textFieldStyle(.plain).accessibilityIdentifier("threadSearch")
                }.padding(9).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 14).padding(.bottom, 6)
                List(selection: $state.threadID) {
                    ForEach(state.visibleThreads) { thread in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(thread.title.isEmpty ? "Untitled thread" : thread.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            HStack(spacing: 5) {
                                if thread.activeTurnId != nil { Circle().fill(.green).frame(width: 5, height: 5) }
                                Text(thread.agentId ?? thread.provider)
                                Text("·")
                                Text(thread.status)
                            }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(.vertical, 8).tag(thread.id)
                    }
                }.listStyle(.inset)
                .overlay {
                    if state.visibleThreads.isEmpty { ContentUnavailableView("No conversations", systemImage: "bubble.left.and.bubble.right", description: Text("Select a workspace and start a thread.")) }
                }
            }.navigationTitle(state.deviceName)
                .toolbar {
                    Button { Task { await state.prepareNewThread() } } label: { Label("New Thread", systemImage: "square.and.pencil") }
                        .disabled(state.workspaceID == nil).accessibilityIdentifier("newThread")
                }.navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 390)
        } detail: {
            ConversationView()
        }
        .task(id: state.deviceID) { await state.loadDevice() }
        .task(id: state.threadID) { await state.loadThread(); await state.poll() }
        .onChange(of: state.workspaceID) { _, _ in
            if !state.visibleThreads.contains(where: { $0.id == state.threadID }) { state.threadID = nil }
        }
        .sheet(isPresented: $state.showingNewThread) { NewThreadView() }
        .sheet(isPresented: $state.showingNewWorkspace) { NewWorkspaceView() }
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
