import SwiftUI
import UIKit

struct ConnectScreen: View {
    @ObservedObject var store: SessionStore
    var onContinue: () -> Void
    @Environment(\.rcColors) private var colors
    @State private var url: String = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    BrandMark()
                    VStack(alignment: .leading) {
                        Text("Remote Codex").font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.fg)
                        Text("Relay access").font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                    }
                }
                Rectangle().fill(colors.border).frame(height: 1)
                Text("Connect to a relay").font(.system(size: 24, weight: .semibold)).foregroundStyle(colors.fg)
                Text("Enter the public relay URL. Sign-in after this step matches the web portal.")
                    .font(.system(size: 14)).foregroundStyle(colors.fgMuted)
                RcField(label: "Relay URL", text: $url, placeholder: "https://relay.example.com", identifier: "relayUrlField")
                if let error { NoticeView(text: error) }
                RcButton(label: "Continue", identifier: "continueButton") {
                    let normalized = normalizeRelayUrl(url)
                    if normalized.isEmpty { error = "Enter a relay URL."; return }
                    store.relayUrl = normalized
                    onContinue()
                }
            }
            .padding(20)
            .background(colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
            .padding(20)
            .padding(.top, 48)
        }
        .background(colors.appBg)
        .onAppear { url = store.relayUrl.isEmpty ? "https://" : store.relayUrl }
    }
}

struct HomeScreen: View {
    @ObservedObject var store: SessionStore
    let api: APIClient
    @Binding var session: RelaySession?
    var onSignIn: () -> Void
    var onDevices: () -> Void
    var onGuide: () -> Void
    var onChangeRelay: () -> Void
    @Environment(\.rcColors) private var colors
    @State private var loading = true
    @State private var error: String?

    var authenticated: Bool { session?.authenticated == true && session?.user?.role != "admin" }

    var body: some View {
        ScrollView {
            HStack {
                BrandMark()
                VStack(alignment: .leading) {
                    Text("Remote Codex Relay").font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.fg)
                    Text("Private supervisor access").font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                }
                Spacer()
                Button(action: onGuide) {
                    Label("Guide", systemImage: "book")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(colors.border, lineWidth: 1))
                        .foregroundStyle(colors.fg)
                }
                .accessibilityIdentifier("guideButton")
            }
            .padding(16)
            Rectangle().fill(colors.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(dot).frame(width: 8, height: 8)
                    Text(statusLabel).font(.system(size: 14)).foregroundStyle(colors.fgMuted)
                }
                Text(title).font(.system(size: 26, weight: .semibold)).foregroundStyle(colors.fg)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(colors.fgSoft)
                if let error {
                    NoticeView(text: error)
                    RcButton(label: "Retry", primary: false) { Task { await load() } }
                } else if !loading {
                    RcButton(label: authenticated ? "Open devices" : "Sign in", identifier: authenticated ? "openDevicesButton" : "signInEntryButton") {
                        authenticated ? onDevices() : onSignIn()
                    }
                }
                Text(store.relayUrl).font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                RcButton(label: "Change relay URL", primary: false, identifier: "changeRelayButton", action: onChangeRelay)
            }
            .padding(20)
        }
        .background(colors.appBg)
        .task { await load() }
    }

    private var title: String {
        if loading { return "Checking relay access" }
        if error != nil { return "Relay service unavailable" }
        return authenticated ? "Choose a device to continue" : "Sign in to your relay workspace"
    }
    private var subtitle: String {
        if error != nil { return "Your session could not be checked. Verify the relay address and try again." }
        return authenticated
            ? "Open device management to connect to a supervisor, then continue into its workspaces and threads."
            : "Use your relay account to reach the devices, workspaces, and threads shared with you."
    }
    private var statusLabel: String {
        if loading { return "Checking session" }
        if error != nil { return "Connection failed" }
        return authenticated ? "Signed in as \(session?.user?.username ?? "")" : "Signed out"
    }
    private var dot: Color {
        if loading { return colors.fgMuted }
        if error != nil { return colors.dangerFg }
        return authenticated ? colors.successFg : colors.fgMuted
    }

    private func load() async {
        loading = true
        error = nil
        do { session = try await api.fetchSession() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct PortalScreen: View {
    @ObservedObject var store: SessionStore
    let api: APIClient
    var onBack: () -> Void
    var onGuide: () -> Void
    var onAuthenticated: () -> Void
    @Environment(\.rcColors) private var colors
    @State private var session: RelaySession?
    @State private var loading = true
    @State private var mode = "login"
    @State private var identifier = ""
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var registrationPassword = ""
    @State private var error: String?
    @State private var notice: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            HStack {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        BrandMark()
                        Text("Relay home").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(colors.fg)
                }
                .accessibilityIdentifier("relayHomeLink")
                Spacer()
                Button("Guide", action: onGuide).foregroundStyle(colors.fg)
            }
            .padding(16)
            Rectangle().fill(colors.border).frame(height: 1)
            if loading {
                Text("Checking relay session...").foregroundStyle(colors.fgMuted).padding(48)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Relay access").foregroundStyle(colors.accentStrong).font(.system(size: 14, weight: .medium))
                    Text(mode == "login" ? "Welcome back" : "Create your account")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(colors.fg)
                    Text(mode == "login" ? "Sign in to open your devices and shared work." : "Create a relay user account for private supervisor access.")
                        .font(.system(size: 14)).foregroundStyle(colors.fgMuted)
                    HStack {
                        tab("Sign in", "login", "signInTab")
                        tab(session?.registrationEnabled == true ? "Create account" : "Registration closed", "register", "registerTab")
                    }
                    .padding(4)
                    .background(colors.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    if mode == "login" {
                        RcField(label: "Email or username", text: $identifier, identifier: "identifierField")
                    } else {
                        RcField(label: "Email", text: $email, identifier: "emailField")
                        RcField(label: "Username", text: $username, identifier: "usernameField")
                        RcField(label: "Registration code", text: $registrationPassword, secure: true, identifier: "registrationCodeField")
                    }
                    RcField(label: "Password", text: $password, secure: true, identifier: "passwordField")
                    if let error { NoticeView(text: error) }
                    if let notice { NoticeView(text: notice, tone: .accent) }
                    RcButton(label: busy ? "Working..." : (mode == "login" ? "Sign in" : "Create account"), enabled: !busy, identifier: "signInButton") {
                        Task { await submit() }
                    }
                }
                .padding(20)
                .background(colors.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
                .padding(20)
            }
        }
        .background(colors.appBg)
        .task {
            loading = true
            session = try? await api.fetchSession()
            if session?.authenticated == true && session?.user?.role != "admin" {
                onAuthenticated()
            }
            loading = false
        }
    }

    private func tab(_ title: String, _ id: String, _ identifier: String) -> some View {
        Button {
            if id == "register" && session?.registrationEnabled != true { return }
            mode = id
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(mode == id ? colors.panel : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(colors.fg)
        }
        .accessibilityIdentifier(identifier)
    }

    private func submit() async {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        busy = true
        error = nil
        notice = nil
        do {
            if mode == "login" {
                let result = try await api.login(identifier: identifier, password: password)
                if result.session.user?.role == "admin" {
                    await api.logout()
                    error = "This portal accepts relay user accounts only."
                } else {
                    onAuthenticated()
                }
            } else {
                if password.count < 8 { error = "Password must be at least 8 characters." }
                else if username.trimmingCharacters(in: .whitespaces).count < 3 { error = "Username must be at least 3 characters." }
                else {
                    let result = try await api.register(email: email, username: username, password: password, registrationPassword: registrationPassword)
                    if result.pendingApproval == true {
                        notice = "Registration request sent. An admin must approve it before you can sign in."
                        mode = "login"
                    } else {
                        onAuthenticated()
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}

struct GuideScreen: View {
    var onBack: () -> Void
    @Environment(\.rcColors) private var colors
    private let steps = [
        ("Register or sign in", "Open the relay portal, then create or enter your relay account."),
        ("Create a device", "In Devices, choose a recognizable name and create a one-time token for the private supervisor."),
        ("Copy the setup command", "Use Copy setup. The generated command includes the relay URL, device token, and supervisor port."),
        ("Start the supervisor", "Run the command on the workspace host."),
        ("Connect and work", "Return to Devices, wait for Online, then connect."),
        ("Share when needed", "From a thread, open sharing and choose permissions."),
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: onBack) {
                    Label("Relay home", systemImage: "chevron.left").foregroundStyle(colors.fg)
                }
                .accessibilityIdentifier("guideBack")
                Text("Setup guide").foregroundStyle(colors.accentStrong)
                Text("Connect a private supervisor").font(.system(size: 26, weight: .semibold)).foregroundStyle(colors.fg)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading) {
                        Text(String(format: "%02d  %@", index + 1, step.0)).font(.system(size: 16, weight: .semibold)).foregroundStyle(colors.fg)
                        Text(step.1).font(.system(size: 14)).foregroundStyle(colors.fgMuted)
                    }
                }
            }
            .padding(20)
        }
        .background(colors.appBg)
    }
}

struct DevicesScreen: View {
    @ObservedObject var store: SessionStore
    let api: APIClient
    var session: RelaySession?
    var onBack: () -> Void
    var onOpenNav: () -> Void
    var onOpenAccount: () -> Void
    var onConnect: (RelayDevice) -> Void
    var onOpenThread: (String, String, String?) -> Void
    var onOpenDevice: (String) -> Void
    @Environment(\.rcColors) private var colors
    @State private var portal: RelayPortal?
    @State private var loading = true
    @State private var error: String?
    @State private var addOpen = false
    @State private var deviceName = ""
    @State private var created: String?
    @State private var autoConnected = false

    var body: some View {
        VStack(spacing: 0) {
            ProductHeader(title: "Devices", backLabel: "Relay home", onBack: onBack, onOpenNav: onOpenNav, onOpenAccount: onOpenAccount, accountLabel: session?.user?.username)
            if ProcessInfo.processInfo.arguments.contains("--uitesting"),
               let device = (portal?.devices ?? []).first(where: { $0.connected == true }) ?? portal?.devices.first {
                HostedButton(title: "Connect", identifier: "connectDeviceButton") {
                    onConnect(device)
                }
                .frame(height: 44)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Devices and shared sessions").font(.system(size: 26, weight: .semibold)).foregroundStyle(colors.fg)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Devices").font(.system(size: 18, weight: .semibold)).foregroundStyle(colors.fg)
                            Text("Your relay supervisors and their current availability.").font(.system(size: 13)).foregroundStyle(colors.fgMuted)
                        }
                        Spacer()
                        RcButton(label: addOpen ? "Close" : "Add device", primary: false, identifier: "addDeviceButton") { addOpen.toggle() }
                            .frame(width: 140)
                    }
                    if let error { NoticeView(text: error) }
                    if addOpen {
                        RcField(label: "Device name", text: $deviceName, identifier: "deviceNameField")
                        RcButton(label: "Create device", identifier: "createDeviceButton") {
                            Task {
                                if let result = try? await api.createDevice(name: deviceName) {
                                    created = result.token
                                    deviceName = ""
                                    addOpen = false
                                    portal = try? await api.fetchPortal()
                                }
                            }
                        }
                    }
                    if let created { NoticeView(text: "Device created. Copy the one-time token now.\n\(created)", tone: .accent) }
                    VStack(spacing: 0) {
                        ForEach(portal?.devices ?? []) { device in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    StatusDot(online: device.connected == true)
                                    Text(device.name)
                                        .foregroundStyle(colors.fg)
                                        .font(.system(size: 14, weight: .medium))
                                        .accessibilityIdentifier("device-\(device.id)")
                                }
                                Text(device.tokenPreview ?? "").font(.system(size: 12, design: .monospaced)).foregroundStyle(colors.fgMuted)
                                Text(device.connected == true ? "Online. Connected time unavailable." : "Offline")
                                    .font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                                RcButton(
                                    label: "Connect",
                                    enabled: device.connected == true || device.hostedStatus == "stopped",
                                    identifier: "connectDevice-\(device.id)"
                                ) {
                                    onConnect(device)
                                }
                            }
                            .padding(12)
                            Rectangle().fill(colors.border).frame(height: 1)
                        }
                        if !loading && (portal?.devices.isEmpty ?? true) {
                            Text("No devices yet. Add a device to create its one-time supervisor token.")
                                .foregroundStyle(colors.fgMuted)
                                .padding(24)
                        }
                    }
                    .background(colors.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
                    .accessibilityIdentifier("deviceList")
                    Text("Shared access").font(.system(size: 18, weight: .semibold)).foregroundStyle(colors.fg)
                    ForEach(portal?.sharedWithMe ?? []) { share in
                        Button {
                            onOpenThread(share.deviceId, share.threadId, share.workspaceId)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(share.threadTitle ?? "Thread").foregroundStyle(colors.fg)
                                Text(share.deviceName ?? "").font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(colors.appBg)
        .onAppear {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .task {
            while !Task.isCancelled {
                portal = try? await api.fetchPortal()
                loading = false
                if ProcessInfo.processInfo.arguments.contains("--uitesting"),
                   !autoConnected,
                   let device = (portal?.devices ?? []).first(where: { $0.connected == true }) {
                    autoConnected = true
                    onConnect(device)
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}

struct WorkspacesScreen: View {
    let api: APIClient
    let deviceId: String
    var session: RelaySession?
    var onBack: () -> Void
    var onOpenNav: () -> Void
    var onOpenAccount: () -> Void
    var onOpen: (Workspace) -> Void
    var onNew: () -> Void
    var onImport: () -> Void
    var onOpenThread: (String) -> Void = { _ in }
    @Environment(\.rcColors) private var colors
    @State private var workspaces: [Workspace] = []
    @State private var runtime: RuntimeConfig?
    @State private var loading = true
    @State private var finishedThread: ThreadSummary?
    @State private var watchCount = 0
    private static var seenThreadIds: Set<String> = []
    private static var watchPrimed = false

    var body: some View {
        VStack(spacing: 0) {
            Text("watching \(watchCount) threads")
                .font(.system(size: 11))
                .foregroundStyle(colors.fgMuted)
                .accessibilityIdentifier("threadWatchCount")
            if let finishedThread {
                HostedButton(title: "Agent run finished.", identifier: "agentNotificationBanner") {
                    let id = finishedThread.id
                    self.finishedThread = nil
                    onOpenThread(id)
                }
                .frame(height: 44)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            ProductHeader(
                title: "Workspaces",
                backLabel: "Back to devices",
                onBack: onBack,
                onOpenNav: onOpenNav,
                onOpenAccount: onOpenAccount,
                accountLabel: session?.user?.username,
                trailing: AnyView(
                    HStack {
                        Button(action: onImport) { Image(systemName: "square.and.arrow.down") }
                            .accessibilityIdentifier("Import session")
                            .foregroundStyle(colors.fgMuted)
                        Button(action: onNew) {
                            Image(systemName: "plus")
                                .foregroundStyle(colors.accentSolidFg)
                                .frame(width: 36, height: 36)
                                .background(colors.accentSolid)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .accessibilityIdentifier("Add workspace")
                    }
                )
            )
            HStack {
                StatusDot(online: runtime != nil)
                Text("Supervisor").font(.system(size: 14, weight: .medium)).foregroundStyle(colors.fg)
                Text(runtime?.workspaceRoot ?? "Checking runtime...").font(.system(size: 12, design: .monospaced)).foregroundStyle(colors.fgMuted).lineLimit(1)
            }
            .padding(12)
            Rectangle().fill(colors.border).frame(height: 1)
            if !loading && workspaces.isEmpty {
                VStack(spacing: 12) {
                    Text("No workspaces yet").font(.system(size: 18, weight: .semibold)).foregroundStyle(colors.fg)
                    RcButton(label: "Add workspace", identifier: "emptyAddWorkspace", action: onNew)
                }
                .padding(32)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(workspaces) { workspace in
                        Button { onOpen(workspace) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workspace.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.fg)
                                Text(workspace.absPath ?? "").font(.system(size: 12, design: .monospaced)).foregroundStyle(colors.fgMuted)
                                Text(workspace.lastOpenedAt == nil ? "Not opened yet" : "Opened \(workspace.lastOpenedAt ?? "")")
                                    .font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("workspace-\(workspace.id)")
                        Rectangle().fill(colors.border).frame(height: 1)
                    }
                }
                .background(colors.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(16)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("workspaceList")
            }
        }
        .background(colors.appBg)
        .task {
            workspaces = (try? await api.fetchWorkspaces(deviceId: deviceId)) ?? []
            runtime = try? await api.fetchRuntime(deviceId: deviceId)
            loading = false
            if !Self.watchPrimed {
                Self.seenThreadIds = Set(((try? await api.fetchThreads(deviceId: deviceId)) ?? []).map(\.id))
                Self.watchPrimed = true
            }
            watchCount = Self.seenThreadIds.count
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let threads = (try? await api.fetchThreads(deviceId: deviceId)) ?? []
                watchCount = threads.count
                for thread in threads where !Self.seenThreadIds.contains(thread.id) {
                    Self.seenThreadIds.insert(thread.id)
                    if thread.status != "running" {
                        finishedThread = thread
                        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                            onOpenThread(thread.id)
                        }
                    }
                }
            }
        }
    }
}

struct ThreadsScreen: View {
    let api: APIClient
    let deviceId: String
    let workspaceId: String
    var session: RelaySession?
    var onBack: () -> Void
    var onOpenNav: () -> Void
    var onOpenAccount: () -> Void
    var onOpen: (ThreadSummary) -> Void
    var onNew: () -> Void
    @Environment(\.rcColors) private var colors
    @State private var threads: [ThreadSummary] = []
    @State private var workspace: Workspace?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            ProductHeader(
                title: workspace?.label ?? "Workspace",
                backLabel: "Back to workspaces",
                onBack: onBack,
                onOpenNav: onOpenNav,
                onOpenAccount: onOpenAccount,
                accountLabel: session?.user?.username,
                trailing: AnyView(
                    Button(action: onNew) {
                        Image(systemName: "plus")
                            .foregroundStyle(colors.accentSolidFg)
                            .frame(width: 36, height: 36)
                            .background(colors.accentSolid)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .accessibilityIdentifier("New thread")
                )
            )
            ScrollView {
                if !loading && threads.isEmpty {
                    Text("No threads available in this workspace.").foregroundStyle(colors.fgMuted).padding(16)
                }
                VStack(alignment: .leading, spacing: 12) {
                    if !threads.isEmpty {
                        Text("Recent Threads").font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.fg)
                    }
                    ForEach(threads) { thread in
                        Button { onOpen(thread) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(thread.title ?? "Thread").foregroundStyle(colors.fg).font(.system(size: 14, weight: .medium))
                                HStack {
                                    Text(thread.updatedAt ?? "").font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                                    if thread.status != "idle" { Text(thread.status ?? "").font(.system(size: 12)).foregroundStyle(colors.fgMuted) }
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                        }
                        .accessibilityIdentifier("thread-\(thread.id)")
                    }
                }
                .padding(16)
            }
        }
        .background(colors.appBg)
        .task {
            let all = (try? await api.fetchThreads(deviceId: deviceId)) ?? []
            threads = all.filter { $0.workspaceId == workspaceId }
            workspace = ((try? await api.fetchWorkspaces(deviceId: deviceId)) ?? []).first { $0.id == workspaceId }
            loading = false
        }
    }
}

struct WorkspaceNewScreen: View {
    let api: APIClient
    let deviceId: String
    var onBack: () -> Void
    var onCreated: (Workspace) -> Void
    @Environment(\.rcColors) private var colors
    @State private var mode = "folder"
    @State private var value = ""
    @State private var label = ""
    @State private var error: String?
    @State private var busy = false
    @State private var devHome: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: onBack) {
                    Label("Back to workspaces", systemImage: "chevron.left").foregroundStyle(colors.fgSoft)
                }
                .accessibilityIdentifier("floatingBack")
                Text("WORKSPACES").font(.system(size: 11, weight: .semibold)).foregroundStyle(colors.fgMuted)
                Text("Add a workspace").font(.system(size: 24, weight: .semibold)).foregroundStyle(colors.fg)
                Text("Choose a folder, existing path, or Git repository.").foregroundStyle(colors.fgMuted)
                HStack {
                    ForEach([("folder", "New folder"), ("path", "Existing path"), ("git", "Git repository")], id: \.0) { id, title in
                        Button(title) { mode = id }
                            .padding(10)
                            .background(mode == id ? colors.accentSoft : colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityIdentifier("workspaceMode-\(id)")
                            .foregroundStyle(colors.fg)
                    }
                }
                RcField(label: mode == "git" ? "Repository URL" : (mode == "path" ? "Absolute path" : "Folder name"), text: $value, identifier: "workspaceValue")
                RcField(label: "Label (optional)", text: $label, identifier: "workspaceLabel")
                if let error { NoticeView(text: error) }
                RcButton(label: busy ? "Working..." : "Create folder", enabled: !busy && !value.isEmpty, identifier: "createWorkspaceButton") {
                    Task {
                        busy = true
                        var body: [String: Any] = [:]
                        if !label.isEmpty { body["label"] = label }
                        if mode == "git" { body["gitUrl"] = value }
                        else if mode == "folder", let devHome, !devHome.isEmpty {
                            body["absPath"] = devHome.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + value
                        } else { body["absPath"] = value }
                        do { onCreated(try await api.createWorkspace(deviceId: deviceId, body: body)) }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }
            }
            .padding(20)
        }
        .background(colors.appBg)
        .task { devHome = try? await api.fetchWorkspaceSettings(deviceId: deviceId).devHome }
    }
}

struct ThreadNewScreen: View {
    let api: APIClient
    let deviceId: String
    let workspaceId: String?
    var onBack: () -> Void
    var onCreated: (ThreadSummary) -> Void
    @Environment(\.rcColors) private var colors
    @State private var workspaces: [Workspace] = []
    @State private var backends: [AgentBackend] = []
    @State private var models: [ModelOption] = []
    @State private var selectedWorkspace = ""
    @State private var provider = "codex"
    @State private var model = ""
    @State private var title = ""
    @State private var error: String?
    @State private var busy = false
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: onBack) {
                    Label(workspaceId == nil ? "Back to workspaces" : "Back to threads", systemImage: "chevron.left")
                        .foregroundStyle(colors.fgSoft)
                }
                .accessibilityIdentifier("floatingBack")
                Text("NEW THREAD").font(.system(size: 11, weight: .semibold)).foregroundStyle(colors.fgMuted)
                Text("Start a backend session").font(.system(size: 24, weight: .semibold)).foregroundStyle(colors.fg)
                if loading {
                    Text("Loading creation form...").foregroundStyle(colors.fgMuted)
                } else {
                    RcField(label: "Title (optional)", text: $title, identifier: "threadTitleField")
                    ForEach(workspaces) { workspace in
                        Button(workspace.label) { selectedWorkspace = workspace.id }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(selectedWorkspace == workspace.id ? colors.accentSoft : colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(colors.fg)
                            .accessibilityIdentifier("pickWorkspace-\(workspace.id)")
                    }
                    HStack {
                        ForEach(backends) { backend in
                            Button(backend.displayName ?? backend.provider) {
                                provider = backend.provider
                                Task { await loadModels() }
                            }
                            .padding(10)
                            .background(provider == backend.provider ? colors.accentSoft : colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(colors.fg)
                            .accessibilityIdentifier("provider-\(backend.provider)")
                        }
                    }
                    ForEach(models, id: \.model) { option in
                        Button(option.displayName ?? option.model) { model = option.model }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(model == option.model ? colors.accentSoft : colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(colors.fg)
                            .accessibilityIdentifier("model-\(option.model)")
                    }
                    if let error { NoticeView(text: error) }
                    RcButton(label: "Start thread", enabled: !busy && !selectedWorkspace.isEmpty && !model.isEmpty, identifier: "startThreadButton") {
                        Task {
                            busy = true
                            do {
                                onCreated(try await api.createThread(deviceId: deviceId, workspaceId: selectedWorkspace, title: title, provider: provider, model: model))
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(colors.appBg)
        .task {
            workspaces = (try? await api.fetchWorkspaces(deviceId: deviceId)) ?? []
            backends = (try? await api.fetchBackends(deviceId: deviceId)) ?? []
            selectedWorkspace = workspaceId ?? workspaces.first?.id ?? ""
            provider = backends.first(where: { $0.enabled == true })?.provider ?? "codex"
            await loadModels()
            loading = false
        }
    }

    private func loadModels() async {
        models = (try? await api.fetchModels(deviceId: deviceId, provider: provider)) ?? []
        model = models.first(where: { $0.isDefault == true })?.model ?? models.first?.model ?? ""
    }
}

struct ImportScreen: View {
    let api: APIClient
    let deviceId: String
    var onBack: () -> Void
    var onImported: (String) -> Void
    @Environment(\.rcColors) private var colors
    @State private var sessionId = ""
    @State private var provider = "codex"
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ProductHeader(title: "Import threads", backLabel: "Back to workspaces", onBack: onBack)
            VStack(alignment: .leading, spacing: 12) {
                RcField(label: "Session id", text: $sessionId, identifier: "importSessionId")
                RcField(label: "Provider", text: $provider, identifier: "importProvider")
                if let error { NoticeView(text: error) }
                RcButton(label: "Import session", identifier: "importButton") {
                    Task {
                        do {
                            let payload = try await api.importThread(deviceId: deviceId, sessionId: sessionId, provider: provider)
                            if let id = (payload["id"] as? String) ?? ((payload["thread"] as? [String: Any])?["id"] as? String) {
                                onImported(id)
                            } else { error = "Imported, but thread id was missing." }
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .padding(20)
            Spacer()
        }
        .background(colors.appBg)
    }
}

struct AccountScreen: View {
    let api: APIClient
    var onBack: () -> Void
    @Environment(\.rcColors) private var colors
    @State private var session: RelaySession?
    @State private var username = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var profileMessage: String?
    @State private var passwordMessage: String?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ProductHeader(title: "Account", backLabel: "Back", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profile").font(.system(size: 16, weight: .semibold)).foregroundStyle(colors.fg)
                    Text(session?.user?.email ?? "").foregroundStyle(colors.fg)
                    RcField(label: "Username", text: $username, identifier: "accountUsername")
                    if let profileMessage { NoticeView(text: profileMessage, tone: .success) }
                    RcButton(label: "Save profile", identifier: "saveProfile") {
                        Task {
                            if let user = try? await api.updateAccount(username: username) {
                                session?.user = user
                                profileMessage = "Profile saved."
                            }
                        }
                    }
                    Text("Password").font(.system(size: 16, weight: .semibold)).foregroundStyle(colors.fg)
                    RcField(label: "Current password", text: $currentPassword, secure: true, identifier: "currentPassword")
                    RcField(label: "New password", text: $newPassword, secure: true, identifier: "newPassword")
                    RcField(label: "Confirm new password", text: $confirmPassword, secure: true, identifier: "confirmPassword")
                    if let error { NoticeView(text: error) }
                    if let passwordMessage { NoticeView(text: passwordMessage, tone: .success) }
                    RcButton(label: "Change password", identifier: "changePassword") {
                        if newPassword != confirmPassword { error = "New passwords do not match."; return }
                        Task {
                            do {
                                _ = try await api.updatePassword(current: currentPassword, new: newPassword)
                                passwordMessage = "Password changed."
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(colors.appBg)
        .task {
            session = try? await api.fetchSession()
            username = session?.user?.username ?? ""
        }
    }
}
