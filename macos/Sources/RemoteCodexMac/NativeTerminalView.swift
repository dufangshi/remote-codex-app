import SwiftUI
import RemoteCodexCore

@MainActor final class TerminalSession: ObservableObject {
    @Published var output = ""
    @Published var error: String?
    @Published var connected = false
    @Published var input = ""
    private var socket: DeviceSocket?
    private var shell = ""
    private var viewer = ""
    private var connectionID = UUID()
    func connect(client: RelayClient, device: String, thread: String) async {
        let generation = UUID(); connectionID = generation
        socket?.close(); socket = nil; connected = false
        struct Shell: Decodable { let id: String; let state: String? }
        struct Shells: Decodable { let shells: [Shell]?; let activeShellId: String? }
        defer { if connectionID == generation { socket?.close(); socket = nil; connected = false } }
        do {
            var list: Shells = try await client.device(device, "/api/threads/\(thread)/shell")
            if list.shells?.isEmpty != false {
                list = try await client.device(device, "/api/threads/\(thread)/shell", method: "POST", body: ["cols": 100, "rows": 32, "label": "Mac terminal"])
            }
            guard let id = list.activeShellId ?? list.shells?.first?.id else { throw APIError("No shell was returned.") }
            shell = id; error = nil
            let channel = try await client.socket(device: device, thread: thread)
            defer { channel.close() }
            guard !Task.isCancelled, connectionID == generation else { return }
            socket = channel
            try await channel.send(["type": "shell.attach", "shellId": id, "cols": 100, "rows": 32])
            while !Task.isCancelled {
                let event = try await channel.receive()
                guard event["shellId"] as? String == id else { continue }
                let payload = event["payload"] as? [String: Any] ?? [:]
                if event["type"] as? String == "shell.connected" { viewer = payload["viewerId"] as? String ?? ""; connected = !viewer.isEmpty }
                if event["type"] as? String == "shell.error" { throw APIError(payload["message"] as? String ?? "Terminal request failed.") }
                if let text = payload["data"] as? String {
                    let clean = text.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\u{001B}\\][^\u{0007}]*\u{0007}", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\r\n", with: "\n")
                    output = String((output + clean).suffix(200_000))
                }
            }
        } catch { if !Task.isCancelled, connectionID == generation { self.error = error.localizedDescription } }
    }
    func send(_ data: String? = nil) async {
        guard connected, let socket else { return }
        do {
            try await socket.send(["type": "shell.input", "shellId": shell, "viewerId": viewer, "data": data ?? (input + "\n")])
            if data == nil { input = "" }
        } catch { self.error = error.localizedDescription }
    }
    func disconnect() { socket?.close() }
}

struct NativeTerminalView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var terminal = TerminalSession()
    @State private var revision = UUID()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Terminal", systemImage: "terminal").font(.headline)
                Text(terminal.connected ? "Connected · encrypted" : "Disconnected").font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                Button("Reconnect") { revision = UUID() }
                Button("Interrupt") { Task { await terminal.send("\u{0003}") } }.disabled(!terminal.connected)
                Button("Clear") { terminal.output = "" }
            }.padding(16).background(Palette.chrome)
            if let error = terminal.error { InlineError(message: error) { terminal.error = nil } }
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading) {
                        Text(terminal.output).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                        Color.clear.frame(height: 1).id("end")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }.onChange(of: terminal.output) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack {
                Text("❯").foregroundStyle(Palette.accent)
                TextField("Shell command", text: $terminal.input).textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .onSubmit { Task { await terminal.send() } }
                Button("Run") { Task { await terminal.send() } }.disabled(!terminal.connected || terminal.input.isEmpty)
            }.padding(16).background(Palette.panel)
            Text("Native command terminal · full-screen TUI rendering is not yet supported").font(.caption).foregroundStyle(Palette.muted).padding(8)
        }.background(Palette.background)
            .task(id: "\(state.threadID ?? "")/\(revision)") {
                guard let client = state.client, let device = state.deviceID, let thread = state.threadID else { terminal.error = "Select a conversation first."; return }
                await terminal.connect(client: client, device: device, thread: thread)
            }.onDisappear { terminal.disconnect() }
    }
}
