import SwiftUI
import RemoteCodexCore

@main
struct RemoteCodexApp: App {
    @NSApplicationDelegateAdaptor(NativeAppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var browser = WorkspaceBrowser()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        Window("Remote Codex", id: "main") {
            RootView(browser: browser).environmentObject(state)
                .frame(minWidth: 800, minHeight: 600)
                .tint(Color(red: 0.23, green: 0.39, blue: 0.94))
                .preferredColorScheme(state.authenticated ? browser.colorScheme : appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .task { appDelegate.state = state; appDelegate.browser = browser; await state.restore() }
        }
        .defaultSize(width: 1260, height: 820)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { browser.perform("newThread") }.keyboardShortcut("n").disabled(browser.web == nil)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Workspace Settings…") { browser.perform("settings") }.keyboardShortcut(",").disabled(browser.web == nil)
                SettingsLink { Text("Connection Settings…") }
            }
            CommandGroup(after: .toolbar) {
                Button("Back") { browser.perform("back") }.keyboardShortcut("[").disabled(!browser.canGoBack)
                Button("Forward") { browser.perform("forward") }.keyboardShortcut("]").disabled(!browser.canGoForward)
                Button("Devices") { browser.perform("home") }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Reload Workspace…") { browser.perform("reload") }.keyboardShortcut("r")
                Button("Open in Browser") { browser.openInBrowser() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Zoom In") { browser.perform("zoomIn") }.keyboardShortcut("+")
                Button("Zoom Out") { browser.perform("zoomOut") }.keyboardShortcut("-")
                Button("Actual Size") { browser.perform("actualSize") }.keyboardShortcut("0")
            }
        }
        Settings {
            Form {
                Text("Change appearance in Workspace Settings (⌘,). The window follows the workspace theme.").font(.callout)
                Section("Connection") {
                    LabeledContent("Relay", value: state.relay)
                    LabeledContent("Transport", value: "HPKE · AES-256-GCM")
                    Text("Session tokens and device identity pins are stored in macOS Keychain.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Workspace") {
                    Text("The workspace uses the same UI as the relay website, including chat, files, terminals and settings. Window controls, menus, file dialogs and downloads are native macOS.")
                    Button("Sign Out", role: .destructive) {
                        let alert = NSAlert(); alert.messageText = "Sign out of this relay?"
                        alert.informativeText = "Save edited files and drafts first. Your existing conversations remain on the device."
                        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Sign Out")
                        if alert.runModal() == .alertSecondButtonReturn { Task { await state.signOut() } }
                    }
                }
            }.formStyle(.grouped).frame(width: 480, height: 460)
                .preferredColorScheme(browser.colorScheme)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var browser: WorkspaceBrowser
    var body: some View {
        VStack(spacing: 0) {
            if !state.authenticated, let error = state.error {
                InlineError(message: error) { state.error = nil }
            }
            if state.authenticated { DesktopWorkspaceView(browser: browser) } else { SignInView() }
        }
        .onChange(of: state.authenticated) { _, signedIn in if !signedIn { browser.reset() } }
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
    @State private var renaming: ThreadSummary?
    @State private var deleting: ThreadSummary?
    @State private var renamedTitle = ""
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill").font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote Codex").font(.headline)
                        Text("YOUR AGENT WORKSPACE").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
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
                            .contextMenu {
                                Button("Rename…") { renamedTitle = thread.title; renaming = thread }
                                Button("Delete…", role: .destructive) { deleting = thread }.disabled(thread.activeTurnId != nil)
                            }
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
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("Workspace view", selection: $state.contentMode) {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right").tag("chat")
                        Label("Files", systemImage: "folder").tag("files")
                        Label("Full workspace", systemImage: "square.grid.2x2").tag("web")
                    }.pickerStyle(.segmented).frame(maxWidth: 420)
                    Spacer()
                }.padding(12).controlGlass().padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
                if let error = state.error { InlineError(message: error) { state.error = nil } }
                if state.contentMode == "files" {
                    if let files = state.fileWorkspace { FilesView(files: files).id(files.api.deviceID + files.api.workspaceID) }
                    else { ContentUnavailableView("Select a workspace", systemImage: "folder") }
                } else if state.contentMode == "web" {
                    if let url = state.webURL {
                        FullWorkspaceView(url: url, cookies: state.webCookies) { state.error = $0 }.id(url.host)
                    } else { ContentUnavailableView("Select a device", systemImage: "desktopcomputer") }
                } else { ConversationView().id(state.threadID) }
            }
        }
        .task(id: state.deviceID) { await state.loadDevice() }
        .task(id: state.threadID) { await state.loadThread(); await state.poll() }
        .onChange(of: state.workspaceID) { _, _ in
            state.selectWorkspace()
            if !state.visibleThreads.contains(where: { $0.id == state.threadID }) { state.threadID = nil }
        }
        .onChange(of: state.contentMode) { _, value in if value == "web" { state.openFullWorkspace() } }
        .sheet(isPresented: $state.showingNewThread) { NewThreadView() }
        .sheet(isPresented: $state.showingNewWorkspace) { NewWorkspaceView() }
        .sheet(isPresented: $state.showingThreadSettings) { ThreadSettingsView() }
        .sheet(item: $renaming) { thread in
            VStack(alignment: .leading, spacing: 18) {
                Text("Rename thread").font(.title2.bold())
                TextField("Title", text: $renamedTitle).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { renaming = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Rename") { Task { await state.renameThread(thread, title: renamedTitle); renaming = nil } }.keyboardShortcut(.defaultAction).disabled(renamedTitle.isEmpty)
                }
            }.padding(24).frame(width: 420)
        }
        .confirmationDialog("Delete this thread?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Thread", role: .destructive) { if let thread = deleting { Task { await state.deleteThread(thread) } }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This removes the conversation from Remote Codex. This action cannot be undone.") }
    }
}

struct ThreadSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var model = ""
    @State private var effort = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Conversation model").font(.title2.bold())
            Picker("Model", selection: $model) {
                if !state.threadModels.contains(where: { $0.model == model }) { Text(model.isEmpty ? "Loading…" : model).tag(model) }
                ForEach(state.threadModels) { Text($0.displayName).tag($0.model) }
            }
            Picker("Reasoning", selection: $effort) {
                Text("Auto").tag("")
                ForEach(state.threadModels.first(where: { $0.model == model })?.supportedReasoningEfforts ?? []) { Text($0.reasoningEffort.capitalized).tag($0.reasoningEffort) }
            }
            if let error = state.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { state.showingThreadSettings = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") { Task { await state.saveThreadSettings(model: model, effort: effort) } }.disabled(state.busy || model.isEmpty || state.active).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 440)
            .onAppear {
                model = state.detail?.thread.model ?? ""
                let current = state.detail?.thread.reasoningEffort ?? ""
                effort = current == "auto" ? "" : current
            }
            .onChange(of: model) { _, value in
                if !(state.threadModels.first(where: { $0.model == value })?.supportedReasoningEfforts ?? []).contains(where: { $0.reasoningEffort == effort }) { effort = "" }
            }
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
