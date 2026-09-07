import SwiftUI

struct RootView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var nav: NavController
    let api: APIClient

    @Environment(\.colorScheme) private var colorScheme
    @State private var session: RelaySession?
    @State private var navOpen = false
    @State private var accountOpen = false
    @State private var settingsOpen = false
    @State private var agentBanner: (deviceId: String, threadId: String, title: String, body: String)?

    private var colors: RcColors {
        switch store.themeMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return colorScheme == .dark ? .dark : .light
        }
    }

    var body: some View {
        ZStack {
            colors.appBg.ignoresSafeArea()
            screen
            if let banner = agentBanner {
                VStack {
                    Button {
                        openThread(deviceId: banner.deviceId, threadId: banner.threadId)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(banner.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.fg)
                            Text(banner.body).font(.system(size: 13)).foregroundStyle(colors.fgMuted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.accentBorder, lineWidth: 1))
                        .padding(.horizontal, 16)
                    }
                    .accessibilityIdentifier("agentNotificationBanner")
                    Spacer().allowsHitTesting(false)
                }
                .padding(.top, 56)
            }
            if navOpen { navMenu }
            if accountOpen { accountMenu }
            if settingsOpen { settingsSheet }
            ScreenEdgeBackSwipe(enabled: nav.canSwipeBack) {
                nav.back()
            }
            .allowsHitTesting(false)
        }
        .environment(\.rcColors, colors)
        .preferredColorScheme(store.themeMode == .system ? nil : (store.themeMode == .dark ? .dark : .light))
        .onAppear {
            EventWatcher.shared.store = store
            EventWatcher.shared.onBanner = { deviceId, threadId, title, body in
                if ProcessInfo.processInfo.arguments.contains("--uitesting") { return }
                agentBanner = (deviceId, threadId, title, body)
            }
            EventWatcher.shared.requestPermission()
            if store.isSignedIn { EventWatcher.shared.start() }
        }
        .onChange(of: store.deviceId) { _, _ in
            EventWatcher.shared.store = store
            EventWatcher.shared.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentRunFinished)) { note in
            let deviceId = note.userInfo?["deviceId"] as? String ?? store.deviceId
            let threadId = note.userInfo?["threadId"] as? String ?? ""
            let title = note.userInfo?["title"] as? String ?? "Thread"
            let body = note.userInfo?["body"] as? String ?? "Agent run finished."
            guard !threadId.isEmpty else { return }
            if ProcessInfo.processInfo.arguments.contains("--uitesting") { return }
            agentBanner = (deviceId, threadId, title, body)
        }
        .onChange(of: nav.current) { _, route in
            if case .threadDetail(let deviceId, let threadId, _) = route {
                EventWatcher.shared.openThread = (deviceId, threadId)
            } else {
                EventWatcher.shared.openThread = nil
            }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch nav.current {
        case .connect:
            ConnectScreen(store: store) { nav.reset(.home) }
        case .home:
            HomeScreen(store: store, api: api, session: $session, onSignIn: { nav.push(.portal) }, onDevices: { nav.push(.devices) }, onGuide: { nav.push(.guide) }, onChangeRelay: {
                store.clearSession()
                EventWatcher.shared.stop()
                nav.reset(.connect)
            })
        case .guide:
            GuideScreen { nav.back() }
        case .portal:
            PortalScreen(store: store, api: api, onBack: { nav.back() }, onGuide: { nav.push(.guide) }, onAuthenticated: {
                Task { session = try? await api.fetchSession() }
                nav.reset(.devices)
                EventWatcher.shared.requestPermission()
                EventWatcher.shared.start()
            })
        case .devices:
            DevicesScreen(store: store, api: api, session: session, onBack: { nav.back() }, onOpenNav: { navOpen = true }, onOpenAccount: { accountOpen = true }, onConnect: { device in
                store.deviceId = device.id
                EventWatcher.shared.refresh()
                nav.push(.workspaces(deviceId: device.id))
            }, onOpenThread: { deviceId, threadId, workspaceId in
                store.deviceId = deviceId
                EventWatcher.shared.refresh()
                nav.push(.threadDetail(deviceId: deviceId, threadId: threadId, workspaceId: workspaceId))
            }, onOpenDevice: { deviceId in
                store.deviceId = deviceId
                EventWatcher.shared.refresh()
                nav.push(.workspaces(deviceId: deviceId))
            })
        case .workspaces(let deviceId):
            WorkspacesScreen(api: api, deviceId: deviceId, session: session, onBack: { nav.back() }, onOpenNav: { navOpen = true }, onOpenAccount: { accountOpen = true }, onOpen: { nav.push(.threads(deviceId: deviceId, workspaceId: $0.id)) }, onNew: { nav.push(.workspaceNew(deviceId: deviceId)) }, onImport: { nav.push(.threadImport(deviceId: deviceId)) }, onOpenThread: { openThread(deviceId: deviceId, threadId: $0) })
        case .workspaceNew(let deviceId):
            WorkspaceNewScreen(api: api, deviceId: deviceId, onBack: { nav.back() }, onCreated: { workspace in
                nav.pop()
                nav.push(.threads(deviceId: deviceId, workspaceId: workspace.id))
            })
        case .threads(let deviceId, let workspaceId):
            ThreadsScreen(api: api, deviceId: deviceId, workspaceId: workspaceId, session: session, onBack: { nav.back() }, onOpenNav: { navOpen = true }, onOpenAccount: { accountOpen = true }, onOpen: { nav.push(.threadDetail(deviceId: deviceId, threadId: $0.id, workspaceId: workspaceId)) }, onNew: { nav.push(.threadNew(deviceId: deviceId, workspaceId: workspaceId)) })
        case .threadNew(let deviceId, let workspaceId):
            ThreadNewScreen(api: api, deviceId: deviceId, workspaceId: workspaceId, onBack: { nav.back() }, onCreated: { thread in
                nav.pop()
                nav.push(.threadDetail(deviceId: deviceId, threadId: thread.id, workspaceId: thread.workspaceId ?? workspaceId))
            })
        case .threadImport(let deviceId):
            ImportScreen(api: api, deviceId: deviceId, onBack: { nav.back() }, onImported: { nav.push(.threadDetail(deviceId: deviceId, threadId: $0, workspaceId: nil)) })
        case .threadDetail(let deviceId, let threadId, _):
            ThreadScreen(
                store: store,
                deviceId: deviceId,
                threadId: threadId,
                themeMode: store.themeMode,
                sessionName: session?.user?.username,
                onBack: { nav.back() },
                onOpenNav: { navOpen = true },
                onOpenAccount: { accountOpen = true },
                onLeave: { next in
                    if case .threadDetail = next {
                        nav.replace(next)
                    } else {
                        nav.pop()
                        nav.push(next)
                    }
                }
            )
        case .account:
            AccountScreen(api: api, onBack: { nav.back() })
        }
    }

    private var navMenu: some View {
        let colors = colors
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.01).ignoresSafeArea().onTapGesture { navOpen = false }
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading) {
                    Text("Remote Codex").font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.fg)
                    Text("Supervisor controls").font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                }.padding(12)
                menuRow("Device management", selected: {
                    if case .devices = nav.current { return true }
                    return false
                }()) {
                    nav.push(.devices)
                    navOpen = false
                }
                menuRow("Settings", selected: false) {
                    navOpen = false
                    settingsOpen = true
                }
            }
            .padding(8)
            .frame(width: 256, alignment: .leading)
            .background(colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
            .padding(.top, 64)
            .padding(.leading, 12)
            .accessibilityIdentifier("navMenu")
        }
    }

    private var accountMenu: some View {
        let colors = colors
        return ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.01).ignoresSafeArea().onTapGesture { accountOpen = false }
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading) {
                    Text(session?.user?.username ?? "").font(.system(size: 14, weight: .medium)).foregroundStyle(colors.fg)
                    Text(session?.user?.email ?? "").font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                }.padding(12)
                menuRow("Account settings", selected: false) { accountOpen = false; nav.push(.account) }
                menuRow("Log out", selected: false) {
                    accountOpen = false
                    Task {
                        await api.logout()
                        EventWatcher.shared.stop()
                        nav.reset(.home)
                    }
                }
            }
            .padding(8)
            .frame(width: 256, alignment: .leading)
            .background(colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
            .padding(.top, 64)
            .padding(.trailing, 12)
            .accessibilityIdentifier("accountMenu")
        }
    }

    private var settingsSheet: some View {
        let colors = colors
        return ZStack {
            colors.overlay.ignoresSafeArea().onTapGesture { settingsOpen = false }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Settings").font(.system(size: 18, weight: .semibold)).foregroundStyle(colors.fg)
                    Spacer()
                    Button("Close settings") { settingsOpen = false }.foregroundStyle(colors.fgMuted)
                }
                Text("Completed turns").font(.system(size: 14, weight: .medium)).foregroundStyle(colors.fg)
                Button {
                    store.autoCollapseCompletedTurns.toggle()
                } label: {
                    VStack(alignment: .leading) {
                        Text("Auto-collapse completed turns").foregroundStyle(colors.fg)
                        Text(store.autoCollapseCompletedTurns
                             ? "Completed turns collapse after they finish."
                             : "Completed turns stay expanded.")
                            .font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(store.autoCollapseCompletedTurns ? colors.accentSoft : colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(store.autoCollapseCompletedTurns ? colors.accentBorder : colors.border, lineWidth: 1))
                }
                .accessibilityIdentifier("autoCollapseCompletedTurns")
                Text("Appearance").font(.system(size: 14, weight: .medium)).foregroundStyle(colors.fg)
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        store.themeMode = mode
                    } label: {
                        VStack(alignment: .leading) {
                            Text(mode.title).foregroundStyle(colors.fg)
                            Text(mode.subtitle).font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(store.themeMode == mode ? colors.accentSoft : colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(store.themeMode == mode ? colors.accentBorder : colors.border, lineWidth: 1))
                    }
                    .accessibilityIdentifier("theme-\(mode.rawValue)")
                }
            }
            .padding(20)
            .background(colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(24)
            .accessibilityIdentifier("settingsDialog")
        }
    }

    private func openThread(deviceId: String, threadId: String) {
        guard !threadId.isEmpty else { return }
        store.deviceId = deviceId
        agentBanner = nil
        nav.push(.threadDetail(deviceId: deviceId, threadId: threadId, workspaceId: nil))
    }

    private func menuRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? colors.accentStrong : colors.fgSoft)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .background(selected ? colors.accentSoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityIdentifier(title)
    }
}
