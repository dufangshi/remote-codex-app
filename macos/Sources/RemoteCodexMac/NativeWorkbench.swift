import SwiftUI
import RemoteCodexCore

struct NativeWorkbench: View {
    @EnvironmentObject var state: AppState
    @State private var renaming: ThreadSummary?
    @State private var deleting: ThreadSummary?
    @State private var title = ""
    @State private var notifications = false
    @State private var shortcutsExpanded = true
    @State private var recentExpanded = true
    var body: some View {
        Group {
        if state.page != "conversation" { PortalPages() }
        else {
        HStack(spacing: 0) {
            activityRail
            VStack(spacing: 0) {
                topbar
                HStack(spacing: 0) {
                    if state.showingSidebar && state.page == "conversation" { sidebar.frame(width: 236); Divider().overlay(Palette.border) }
                    VStack(spacing: 0) {
                        if state.page == "conversation" { tabs; if state.showingTools { toolsBar } }
                        if let error = state.error { InlineError(message: error) { state.error = nil } }
                        if state.page != "conversation" { selectionPage }
                        else if state.contentMode == "files", let files = state.fileWorkspace {
                            FilesView(files: files).id(files.api.deviceID + files.api.workspaceID)
                        } else if state.contentMode == "terminal" { NativeTerminalView().id(state.deviceID ?? "") }
                        else { ConversationView().id(state.threadID) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        }
        }.background(Palette.background)
            .task(id: state.deviceID) { await state.loadDevice() }
            .task(id: state.threadID) { await state.loadThread(); await state.poll() }
            .onChange(of: state.workspaceID) { _, _ in
                state.selectWorkspace()
                if !state.visibleThreads.contains(where: { $0.id == state.threadID }) { state.threadID = state.visibleThreads.first?.id }
            }
            .sheet(isPresented: $state.showingNewThread) { NewThreadView() }
            .sheet(isPresented: $state.showingNewWorkspace) { NewWorkspaceView() }
            .sheet(isPresented: $state.showingSettings) { AppSettingsView() }
            .sheet(item: $state.activeShareSheet) { sheet in
                switch sheet {
                case .link: ThreadShareLinkView()
                case .permissions: ThreadSharingPermissionsView()
                case .transcript: ThreadTranscriptExportView()
                }
            }
            .sheet(item: $renaming) { thread in
                VStack(alignment: .leading, spacing: 20) {
                    Text("Rename thread").font(.title2.bold())
                    TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { renaming = nil }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Rename") { Task { await state.renameThread(thread, title: title); renaming = nil } }.keyboardShortcut(.defaultAction)
                    }
                }.padding(28).frame(width: 420).glassBar()
            }
            .confirmationDialog("Delete this thread?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete Thread", role: .destructive) { if let thread = deleting { Task { await state.deleteThread(thread) } }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("This permanently removes the conversation. It cannot be undone.") }
    }
    private var activityRail: some View {
        VStack(spacing: 18) {
            IconButton(title: "Remote Codex home", icon: "house") { state.page = "workspaces" }
            IconButton(title: "Chat", icon: "bubble.left", selected: state.contentMode == "chat") { state.page = "conversation"; state.contentMode = "chat" }
            IconButton(title: "Terminal", icon: "terminal", selected: state.contentMode == "terminal") { state.page = "conversation"; state.contentMode = "terminal" }
            IconButton(title: "Files", icon: "folder", selected: state.contentMode == "files") { state.page = "conversation"; state.contentMode = "files" }
            Spacer()
            IconButton(title: "Settings", icon: "gearshape") { state.showingSettings = true }
        }.padding(.bottom, 12).frame(width: 50).glassBar()
            .overlay(alignment: .trailing) { Palette.border.frame(width: 1).allowsHitTesting(false) }
    }
    private var topbar: some View {
        HStack(spacing: 12) {
            IconButton(title: "Toggle sidebar", icon: "sidebar.left") { state.showingSidebar.toggle() }
            Text("Remote Codex").font(.system(size: 16, weight: .semibold))
            IconButton(title: "Back to workspaces", icon: "arrow.left") { state.page = "workspaces" }
            Rectangle().fill(Palette.border).frame(width: 1, height: 22).padding(.horizontal, 6)
            Label(state.deviceName, systemImage: "desktopcomputer").foregroundStyle(Palette.muted).lineLimit(1)
            Button { state.showingSearch.toggle() } label: {
                Label("Search conversation", systemImage: "magnifyingglass").foregroundStyle(Palette.muted)
            }.buttonStyle(.plain).padding(.leading, 12)
            Spacer()
            IconButton(title: "Notifications", icon: "bell") { notifications.toggle(); Task { await state.refreshNavigation() } }
                .popover(isPresented: $notifications) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Notifications").font(.headline)
                        Text(state.notificationStatus).font(.caption).foregroundStyle(Palette.muted)
                        Button("Enable macOS notifications") { Task { await state.systemNotifications.enable() } }
                        Text("Latest 10 events").font(.caption).foregroundStyle(Palette.muted)
                        ForEach(Array((state.navigation?.notifications ?? []).prefix(10))) { event in
                            Button { state.openNotification(event); notifications = false } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(event.title).font(.callout)
                                    Text(event.occurredAt).font(.caption).foregroundStyle(Palette.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                        if state.navigation?.notifications.isEmpty != false { Text("You're all caught up.").foregroundStyle(Palette.muted) }
                    }.padding(20).frame(width: 340)
                }
        }.padding(.horizontal, 12).frame(height: 48).glassBar()
            .overlay(alignment: .bottom) { Palette.border.frame(height: 1) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(state.workspaces.first { $0.id == state.workspaceID }?.label ?? "Workspace").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            Menu {
                ForEach(state.workspaces) { workspace in Button(workspace.label) { state.workspaceID = workspace.id } }
                Divider(); Button("All workspaces") { state.page = "workspaces" }
            } label: {
                HStack { Image(systemName: "folder"); Text(state.workspaces.first { $0.id == state.workspaceID }?.label ?? "Choose workspace").lineLimit(1); Spacer(); Image(systemName: "chevron.down").font(.caption) }
                    .padding(9).frame(maxWidth: .infinity).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Choose workspace")
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Find a chat", text: $state.query).textFieldStyle(.plain)
            }.padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            if state.deviceLoading { ProgressView().controlSize(.small) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeading("Shortcuts", expanded: $shortcutsExpanded, count: nil)
                    if shortcutsExpanded {
                        ForEach((state.navigation?.threads ?? []).filter(\.favorite)) { referenceRow($0) }
                        if !(state.navigation?.threads ?? []).contains(where: \.favorite) {
                            Text("Pin a chat from its menu.").font(.caption).foregroundStyle(Palette.muted).padding(10)
                        }
                    }
                    sectionHeading("Recent chats", expanded: $recentExpanded, count: min(20, state.navigation?.threads.count ?? state.visibleThreads.count)).padding(.top, 18)
                    if recentExpanded {
                        if let references = state.navigation?.threads, !references.isEmpty {
                            ForEach(references.filter { state.query.isEmpty || $0.title.localizedCaseInsensitiveContains(state.query) }.prefix(20)) { reference in
                                referenceRow(reference)
                            }
                        } else { ForEach(state.visibleThreads) { threadRow($0) } }
                    }
                }
            }.scrollIndicators(.never)
            Text("Your conversations, together.").font(.caption).foregroundStyle(Palette.muted).padding(.vertical, 8)
        }.padding(.horizontal, 12).padding(.top, 14).glassBar()
    }
    private func sectionHeading(_ name: String, expanded: Binding<Bool>, count: Int?) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right").font(.caption)
                Text(name); Spacer(); if let count { Text("\(count)") }
            }.foregroundStyle(Palette.muted).padding(8)
        }.buttonStyle(.plain)
    }
    private func referenceRow(_ reference: ThreadReference) -> some View {
        Button { state.selectReference(reference.deviceId, reference.threadId) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(reference.title).font(.system(size: 14)).lineLimit(1)
                Text(reference.deviceName + " · " + reference.workspaceLabel).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).background(state.deviceID == reference.deviceId && state.threadID == reference.threadId ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).contextMenu {
            Button(reference.favorite ? "Unpin" : "Pin to Shortcuts") { Task { await state.setFavorite(reference, favorite: !reference.favorite) } }
        }
    }
    private func threadRow(_ thread: ThreadSummary) -> some View {
        HStack(spacing: 8) {
            Button {
                state.threadID = thread.id; state.contentMode = "chat"
            } label: {
                HStack(spacing: 9) {
                    Circle().stroke(thread.activeTurnId == nil ? Palette.muted : Palette.accent, lineWidth: 1.5).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(thread.title.isEmpty ? "Untitled" : thread.title).font(.system(size: 14)).lineLimit(1)
                        Text(state.deviceName + " · " + (state.workspaces.first { $0.id == thread.workspaceId }?.label ?? "Workspace"))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 12).padding(.leading, 10).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button(state.pinnedThreads.contains(thread.id) ? "Unpin" : "Pin to Shortcuts") { state.togglePin(thread.id) }
                Button("Rename…") { title = thread.title; renaming = thread }
                Button("Delete…", role: .destructive) { deleting = thread }.disabled(thread.activeTurnId != nil)
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.trailing, 6).accessibilityLabel("Actions for " + thread.title)
        }.background(state.threadID == thread.id ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(state.threadID == thread.id ? Palette.muted.opacity(0.45) : .clear))
    }
    private var tabs: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(state.visibleThreads) { thread in
                        Button { state.selectReference(state.deviceID ?? "", thread.id) } label: {
                            HStack(spacing: 8) {
                                Circle().stroke(thread.activeTurnId == nil ? Palette.muted : Palette.accent, lineWidth: 1.5).frame(width: 6, height: 6)
                                Text(thread.title.isEmpty ? "Untitled" : thread.title).lineLimit(1)
                            }.padding(.horizontal, 16).frame(height: 42).frame(maxWidth: 190)
                                .background(state.threadID == thread.id ? Palette.background : .clear)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) { if state.threadID == thread.id { Palette.accent.frame(height: 2).allowsHitTesting(false) } }
                                .overlay(alignment: .trailing) { Palette.border.frame(width: 1) }
                        }.buttonStyle(.plain)
                    }
                    IconButton(title: "New Chat", icon: "plus") { Task { await state.prepareNewThread() } }.disabled(state.workspaceID == nil)
                }
            }.scrollIndicators(.never)
            IconButton(title: "Thread tools", icon: "slider.horizontal.3", selected: state.showingTools) { state.showingTools.toggle() }.disabled(state.threadID == nil)
        }.frame(height: 42).background(Palette.chrome).overlay(alignment: .bottom) { Palette.border.frame(height: 1) }
    }
    private var toolsBar: some View {
        HStack(spacing: 8) {
            Button { state.page = "workspaces" } label: { Label(state.workspaces.first { $0.id == state.workspaceID }?.label ?? "Workspace", systemImage: "folder") }.buttonStyle(WorkbenchButton())
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
            Text(state.detail?.thread.title ?? "Loading…").lineLimit(1).font(.system(size: 13))
            IconButton(title: "Pin / Unpin", icon: "star") {
                let favorite = state.navigation?.threads.first { $0.deviceId == state.deviceID && $0.threadId == state.threadID }?.favorite ?? false
                Task { await state.recordVisit(favorite: !favorite) }
            }
            Spacer()
            IconButton(title: "Share as link", icon: "link") { state.activeShareSheet = .link }
            IconButton(title: "Sharing permissions", icon: "person.2") { state.activeShareSheet = .permissions }
            IconButton(title: "Download transcript", icon: "arrow.down.to.line") { state.activeShareSheet = .transcript }
            Menu {
                Button("Model and reasoning…") { Task { await state.prepareThreadSettings() } }
                Button("Copy Remote Codex session ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(state.threadID ?? "", forType: .string) }
                if let thread = state.detail?.thread {
                    Button("Rename…") { title = thread.title; renaming = thread }
                    Button("Delete…", role: .destructive) { deleting = thread }.disabled(state.active)
                }
            } label: { Image(systemName: "ellipsis").frame(width: 30, height: 32).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Thread actions")
            IconButton(title: "Toggle Explorer", icon: "sidebar.right") { state.contentMode = state.contentMode == "files" ? "chat" : "files" }
        }.padding(.horizontal, 12).frame(height: 46).glassBar()
    }
    private var selectionPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.page == "devices" ? "Your devices" : state.deviceName).font(.system(size: 28, weight: .semibold))
                        Text(state.page == "devices" ? "Choose a connected device to browse its workspaces." : "Workspaces").foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    if state.page == "workspaces" {
                        Button("All devices") { state.page = "devices" }
                        Button("Add workspace") { state.showingNewWorkspace = true }
                    }
                    Button("Refresh") { Task { if state.page == "devices" { await state.refreshPortal() } else { await state.refreshLists() } } }
                }
                if state.deviceLoading && state.page == "workspaces" { ProgressView("Loading workspaces…") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 18) {
                    if state.page == "devices" {
                        ForEach(state.devices) { device in
                            Button { state.deviceID = device.id; state.page = "workspaces" } label: {
                                VStack(alignment: .leading, spacing: 16) {
                                    Image(systemName: "desktopcomputer").font(.title)
                                    Text(device.name).font(.headline)
                                    Label(device.connected == true ? "Online" : "Offline / shared", systemImage: "circle.fill").font(.caption).foregroundStyle(device.connected == true ? Palette.accent : Palette.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    } else {
                        ForEach(state.workspaces) { workspace in
                            Button {
                                state.workspaceID = workspace.id; state.selectWorkspace()
                                state.threadID = state.threads.first { $0.workspaceId == workspace.id }?.id
                                state.page = "conversation"; state.contentMode = "chat"
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(systemName: "folder").font(.title).foregroundStyle(Palette.accent)
                                    Text(workspace.label).font(.headline)
                                    Text(workspace.absPath).font(.caption.monospaced()).foregroundStyle(Palette.muted).lineLimit(2)
                                    Text("\(state.threads.filter { $0.workspaceId == workspace.id }.count) conversations").font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(36)
        }.scrollIndicators(.never).buttonStyle(WorkbenchButton())
    }
}
