import SwiftUI
import RemoteCodexCore

private struct IgnoredReply: Decodable {}
private struct TokenReply: Decodable { let token: String }
private struct RuntimeInfo: Decodable {
    let workspaceRoot: String; let environment: String; let host: String; let port: Int
    let appName: String; let appVersion: String
}

struct PortalPages: View {
    @EnvironmentObject var state: AppState
    @State private var sharedTab = 0
    @State private var addDevice = false
    @State private var name = ""
    @State private var copied: String?
    @State private var busy = false
    @State private var runtime: RuntimeInfo?
    @State private var runtimeOpen = false
    @State private var editing: Workspace?
    @State private var path: String?
    @State private var sharing: Device?
    @State private var grant: Grant?
    @State private var grantIsShare = false
    @State private var deletingDevice: Device?
    @State private var deletingWorkspace: Workspace?
    @State private var revoking: Grant?
    @State private var rotating: Device?
    @State private var importing = false
    private var isDevices: Bool { state.page == "devices" }
    private var spaces: [Workspace] { state.workspaces.sorted { if $0.isFavorite != $1.isFavorite { return $0.isFavorite == true }; return ($0.lastOpenedAt ?? "") > ($1.lastOpenedAt ?? "") } }
    private var shares: [Grant] {
        switch sharedTab {
        case 0: return state.portal?.sharedWithMe ?? []
        case 1: return state.portal?.sharedDevicesWithMe ?? []
        case 2: return state.portal?.grantsByMe ?? []
        default: return state.portal?.sharedByMe ?? []
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    navigationMenu
                    IconButton(title: isDevices ? "Relay home" : "Back to devices", icon: "arrow.left") { state.page = "devices" }
                    Text(isDevices ? "Devices" : "Workspaces").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if !isDevices {
                        IconButton(title: "Import session", icon: "square.and.arrow.down") { importing = true }
                        IconButton(title: "Add workspace", icon: "plus") { state.showingNewWorkspace = true }
                    }
                    Menu {
                        Button("Settings") { state.showingSettings = true }
                        Button("Sign out") { Task { await state.signOut() } }
                    } label: { Image(systemName: "person.crop.circle").font(.system(size: 20)).frame(width: 40, height: 40) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Account")
                }.padding(6).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                if let error = state.error { InlineError(message: error) { state.error = nil } }
                if isDevices { devicesPage } else { workspacesPage }
            }.frame(maxWidth: 1120).padding(24).frame(maxWidth: .infinity, alignment: .top)
        }.scrollIndicators(.never).background(Palette.background)
            .task(id: state.page + (state.deviceID ?? "")) {
                if isDevices {
                    while !Task.isCancelled { await state.refreshPortal(); do { try await Task.sleep(for: .seconds(3)) } catch { return } }
                } else {
                    guard let api = state.client, let device = state.deviceID else { return }
                    do { runtime = try await api.device(device, "/api/config/runtime") } catch { state.error = error.localizedDescription }
                }
            }
            .sheet(item: $editing) { workspace in
                simpleDialog("Rename workspace") {
                    TextField("Workspace label", text: $name).textFieldStyle(.roundedBorder)
                    Button("Save") { Task { await mutateWorkspace(workspace, body: ["label": name]); if state.error == nil { editing = nil } } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
            .sheet(isPresented: Binding(get: { path != nil }, set: { if !$0 { path = nil } })) {
                simpleDialog("Workspace path") { Text(path ?? "").textSelection(.enabled); Button("Copy path") { copy(path ?? "") } }
            }
            .sheet(item: $sharing) { device in AccessEditor(device: device, grant: nil, isShare: false) }
            .sheet(item: $grant) { value in AccessEditor(device: nil, grant: value, isShare: grantIsShare) }
            .sheet(isPresented: $importing) { ImportSessionView() }
            .confirmationDialog("Delete relay device?", isPresented: Binding(get: { deletingDevice != nil }, set: { if !$0 { deletingDevice = nil } })) {
                Button("Delete device", role: .destructive) { if let device = deletingDevice { Task { await relayAction("/relay/devices/\(device.id)", method: "DELETE") } }; deletingDevice = nil }
            } message: { Text("Its device token will stop working immediately. This cannot be undone.") }
            .confirmationDialog("Delete workspace?", isPresented: Binding(get: { deletingWorkspace != nil }, set: { if !$0 { deletingWorkspace = nil } })) {
                Button("Delete workspace", role: .destructive) {
                    if let workspace = deletingWorkspace { Task { await mutateWorkspace(workspace, body: ["confirmWorkspaceId": workspace.id, "confirmLabel": workspace.label], method: "DELETE") } }; deletingWorkspace = nil
                }
            } message: { Text("Remove this workspace and its threads from the supervisor. Files on disk are not deleted.") }
            .confirmationDialog("Revoke shared access?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } })) {
                Button("Revoke access", role: .destructive) { if let value = revoking { Task { await relayAction("/relay/\(sharedTab == 3 ? "shares" : "grants")/\(value.id)", method: "DELETE") } }; revoking = nil }
            } message: { Text("The recipient's shared access will stop working immediately.") }
            .sheet(item: $rotating) { device in RotateTokenView(device: device) }
    }
    private var navigationMenu: some View {
        Menu {
            Button("Device management") { state.page = "devices" }
            Button("Settings") { state.showingSettings = true }
        } label: { Image(systemName: "line.3.horizontal").font(.system(size: 18)).frame(width: 40, height: 40) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Open Navigation")
    }
    private var devicesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Devices and shared sessions").font(.system(size: 28, weight: .semibold))
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text("Devices").font(.system(size: 18, weight: .semibold)); Text("Your relay supervisors and their current availability.").foregroundStyle(Palette.muted) }
                Spacer()
                Button { addDevice.toggle() } label: { Label(addDevice ? "Close" : "Add device", systemImage: addDevice ? "xmark" : "plus") }.buttonStyle(WorkbenchButton())
            }
            if addDevice {
                HStack { TextField("Device name", text: $name).textFieldStyle(.roundedBorder); Button("Add device") { Task { await relayAction("/relay/devices", method: "POST", body: ["name": name]); if state.error == nil { addDevice = false; name = "" } } }.disabled(name.isEmpty || busy) }.padding(12).composerMenuSurface()
            }
            VStack(spacing: 0) {
                HStack { Text("Device").frame(maxWidth: .infinity, alignment: .leading); Text("Activity").frame(maxWidth: .infinity, alignment: .leading); Text("Action").frame(width: 150, alignment: .trailing) }.font(.system(size: 12)).foregroundStyle(Palette.muted).padding(12)
                ForEach(state.portal?.devices ?? []) { device in
                    Divider().overlay(Palette.border)
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Circle().fill(device.connected == true ? Palette.accent : Palette.muted).frame(width: 7, height: 7); Text(device.name).fontWeight(.medium); Spacer(); Text(device.connected == true ? "Online" : "Offline").font(.caption).foregroundStyle(Palette.muted) }
                            Text(device.tokenPreview ?? "").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(device.connected == true ? "Connected now" : device.lastSeenAt.map { "Last seen " + $0 } ?? "Not connected yet")
                            if copied == device.id { Text("Setup command copied.").foregroundStyle(Palette.accent) }
                        }.font(.system(size: 12)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button("Connect") { state.deviceID = device.id; state.page = "workspaces" }.buttonStyle(WorkbenchButton(selected: true))
                                .disabled(device.connected != true && device.hostedStatus != "stopped")
                                .help(device.connected != true && device.hostedStatus != "stopped" ? "Device is offline. Start the supervisor on that device, then try again." : "Connect to this device")
                            Menu {
                                Button("Copy setup for macOS/Linux") { Task { await setup(device, windows: false) } }
                                Button("Copy setup for Windows") { Task { await setup(device, windows: true) } }
                                Button("Share device") { sharing = device }
                                Button("Replace device token") { rotating = device }.disabled(device.hostedStatus != nil)
                                Divider(); Button("Delete device", role: .destructive) { deletingDevice = device }.disabled(device.hostedStatus != nil)
                            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 36) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More actions for " + device.name)
                        }.frame(width: 150)
                    }.padding(12)
                }
                if state.portal?.devices.isEmpty == true { Text("No devices yet. Add a device to create its permanent supervisor token.").foregroundStyle(Palette.muted).padding(24) }
            }.composerMenuSurface(radius: 8)
            Text("Shared access").font(.system(size: 18, weight: .semibold)).padding(.top, 12)
            HStack {
                ForEach(Array(["Threads with me", "Devices with me", "Devices by me", "Threads by me"].enumerated()), id: \.offset) { index, label in
                    Button(label) { sharedTab = index }.buttonStyle(WorkbenchButton(selected: sharedTab == index))
                }
            }
            ForEach(shares) { value in
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(value.threadTitle ?? value.deviceName ?? value.label ?? "Shared access").fontWeight(.medium)
                        Text([value.workspaceLabel, value.ownerUsername.map { "From " + $0 }, value.targetUsername.map { "To " + $0 }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Palette.muted)
                        Text("Thread: \(value.threadAccess ?? "read") · Workspace: \(value.workspaceAccess ?? "none")").font(.caption).foregroundStyle(Palette.muted)
                    }; Spacer()
                    Button("Open") { if let thread = value.threadId { state.selectReference(value.deviceId, thread) } else { state.deviceID = value.deviceId; state.page = "workspaces" } }.disabled(value.deviceConnected != true)
                    if sharedTab >= 2 {
                        Button("Edit permissions") { grantIsShare = sharedTab == 3; grant = value }
                        Button("Revoke", role: .destructive) { revoking = value }
                    }
                }.padding(16).composerMenuSurface(radius: 8)
            }
            if shares.isEmpty { Text("No shared access in this category.").foregroundStyle(Palette.muted).padding(24) }
        }.buttonStyle(WorkbenchButton())
    }
    private var workspacesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup(isExpanded: $runtimeOpen) {
                if let runtime {
                    HStack(alignment: .top, spacing: 36) {
                        fact("Workspace root", runtime.workspaceRoot); fact("Environment", "\(runtime.environment) | \(runtime.host):\(runtime.port)"); fact("Version", runtime.appName + " " + runtime.appVersion)
                    }.padding(.vertical, 14)
                }
            } label: {
                HStack { Circle().fill(runtime == nil ? Palette.muted : Palette.accent).frame(width: 8, height: 8); Text("Supervisor").fontWeight(.medium); Text(runtime?.workspaceRoot ?? "Loading supervisor…").font(.system(size: 12, design: .monospaced)).lineLimit(1).foregroundStyle(Palette.muted); Spacer(); Text("\(state.workspaces.count) workspaces").font(.caption).foregroundStyle(Palette.muted) }.padding(.vertical, 12)
            }
            VStack(spacing: 0) {
                ForEach(spaces) { workspace in
                    HStack(spacing: 0) {
                        Button { state.workspaceID = workspace.id; state.selectWorkspace(); state.threadID = state.threads.first { $0.workspaceId == workspace.id }?.id; state.page = "conversation"; state.contentMode = "chat" } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(workspace.label).font(.system(size: 16, weight: .semibold))
                                Text(workspace.absPath).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1)
                                Text(workspace.lastOpenedAt.map { "Last opened " + $0 } ?? "Not opened yet").font(.caption).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        IconButton(title: (workspace.isFavorite == true ? "Unpin " : "Pin ") + workspace.label, icon: "pin", selected: workspace.isFavorite == true) { Task { await mutateWorkspace(workspace, body: ["isFavorite": workspace.isFavorite != true], suffix: "/favorite", method: "POST") } }
                        Menu {
                            Button("View path") { path = workspace.absPath }
                            Button("Rename workspace") { name = workspace.label; editing = workspace }
                            Button("Delete workspace", role: .destructive) { deletingWorkspace = workspace }
                        } label: { Image(systemName: "ellipsis").frame(width: 32, height: 40) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.trailing, 12).accessibilityLabel("More actions for " + workspace.label)
                    }
                    Divider().overlay(Palette.border)
                }
                if state.deviceLoading { ProgressView("Loading workspaces…").padding(24) }
                else if spaces.isEmpty { Text("No workspaces yet").font(.headline).padding(24); Button("Add workspace") { state.showingNewWorkspace = true }.padding(.bottom, 20) }
            }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
        }
    }
    private func fact(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(label).font(.caption).foregroundStyle(Palette.muted); Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func simpleDialog<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 18) { Text(title).font(.headline); content(); if let error = state.error { Text(error).foregroundStyle(.red) }; Button("Close") { editing = nil; path = nil } }.padding(24).frame(width: 500).background(Palette.panel) }
    private func relayAction(_ path: String, method: String, body: [String: Any]? = nil) async {
        guard let api = state.client else { return }; busy = true; state.error = nil; defer { busy = false }
        do { let _: IgnoredReply = try await api.relay(path, method: method, body: body); await state.refreshPortal() } catch { state.error = error.localizedDescription }
    }
    private func mutateWorkspace(_ workspace: Workspace, body: [String: Any], suffix: String = "", method: String = "PATCH") async {
        guard let api = state.client, let device = state.deviceID else { return }; busy = true; state.error = nil; defer { busy = false }
        do { _ = try await api.deviceData(device, "/api/workspaces/" + workspace.id + suffix, method: method, body: JSONSerialization.data(withJSONObject: body)); await state.refreshLists() } catch { state.error = error.localizedDescription }
    }
    private func setup(_ device: Device, windows: Bool) async {
        guard let api = state.client else { return }
        do { let result: TokenReply = try await api.relay("/relay/devices/\(device.id)/setup-token", method: "POST"); copy(SetupCommand.make(origin: api.origin, token: result.token, windows: windows)); copied = device.id } catch { state.error = error.localizedDescription }
    }
}

enum SetupCommand {
    static func make(origin: URL, token: String, windows: Bool) -> String {
        func shell(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        func ps(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
        if windows {
            let relay = origin.absoluteString.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
            return "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force\n$env:REMOTE_CODEX_RELAY_SERVER_URL=\(ps(relay))\n$env:REMOTE_CODEX_RELAY_AGENT_TOKEN=\(ps(token))\n$env:REMOTE_CODEX_RELAY_SUPERVISOR_PORT='45680'\nremote-codex relay-supervisor"
        }
        return "curl -fsSL \(shell(origin.absoluteString + "/setup.sh")) | sh -s -- --relay \(shell(origin.absoluteString)) --token \(shell(token)) --port 45679"
    }
}
