import SwiftUI
import RemoteCodexCore

@MainActor final class TerminalSession: ObservableObject {
    @Published var screen = TerminalBuffer()
    @Published var outputRevision = 0
    private var columns = 100
    private var rows = 32
    @Published var error: String?
    @Published var connected = false
    @Published var input = ""
    private var socket: DeviceSocket?
    private var shell = ""
    private var viewer = ""
    private var connectionID = UUID()
    var forceNew = false
    func connect(client: RelayClient, device: String, thread: String) async {
        let generation = UUID(); connectionID = generation
        socket?.close(); socket = nil; connected = false
        struct Shell: Decodable { let id: String; let status: String? }
        struct Shells: Decodable { let shells: [Shell]?; let activeShellId: String? }
        defer { if connectionID == generation { socket?.close(); socket = nil; connected = false } }
        do {
            var list: Shells = try await client.device(device, "/api/threads/\(thread)/shell")
            if forceNew || !(list.shells ?? []).contains(where: { !["exited", "not_found"].contains($0.status ?? "") }) {
                list = try await client.device(device, "/api/threads/\(thread)/shell", method: "POST", body: ["cols": columns, "rows": rows, "label": "Mac terminal"])
                forceNew = false
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
                if ["shell.exited", "shell.detached"].contains(event["type"] as? String ?? "") { connected = false; break }
                if event["type"] as? String == "shell.connected" { viewer = payload["viewerId"] as? String ?? ""; connected = !viewer.isEmpty }
                if event["type"] as? String == "shell.error" { throw APIError(payload["message"] as? String ?? "Terminal request failed.") }
                if let text = payload["data"] as? String {
                    if payload["replace"] as? Bool == true { screen.clear() }
                    screen.feed(text); outputRevision += 1
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
    func resize(_ size: CGSize) async {
        let cols = max(20, Int((size.width - 36) / 7.83)), count = max(8, Int((size.height - 36) / 18))
        columns = cols; rows = count; screen.columns = cols; screen.rows = count
        if connected, let socket {
            do { try await socket.send(["type": "shell.resize", "shellId": shell, "viewerId": viewer, "cols": cols, "rows": count]) }
            catch { self.error = error.localizedDescription }
        }
    }
    func paste(_ value: String) async { await send(screen.bracketedPaste ? "\u{1b}[200~" + value + "\u{1b}[201~" : value) }
    func disconnect() { socket?.close() }
}

struct NativeTerminalView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var terminal = TerminalSession()
    @State private var revision = UUID()
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Terminal", systemImage: "terminal").font(.headline)
                Text(terminal.connected ? "Connected · encrypted" : "Disconnected").font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                Button("New terminal") { terminal.forceNew = true; revision = UUID() }
                Button("Reconnect") { revision = UUID() }
                Button("Interrupt") { Task { await terminal.send("\u{0003}") } }.disabled(!terminal.connected)
                Button("Clear") { terminal.screen.clear(); terminal.outputRevision += 1 }
            }.padding(16).background(Palette.chrome)
            if let error = terminal.error { InlineError(message: error) { terminal.error = nil } }
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(renderScreen()).font(.system(size: 13, design: .monospaced)).lineSpacing(2)
                                .fixedSize(horizontal: true, vertical: true)
                            Color.clear.frame(height: 1).id("end")
                        }.frame(minWidth: max(0, geometry.size.width - 36), minHeight: max(0, geometry.size.height - 36), alignment: .topLeading).padding(18)
                    }.scrollIndicators(.never)
                        .onChange(of: terminal.outputRevision) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                }
                .contentShape(Rectangle()).onTapGesture { focused = true }
                .focusable().focused($focused).focusEffectDisabled()
                .onKeyPress(phases: [.down, .repeat]) { press in
                    guard terminal.connected else { return .ignored }
                    if press.modifiers.contains(.command) {
                        if press.characters.lowercased() == "v", let text = NSPasteboard.general.string(forType: .string) {
                            Task { await terminal.paste(text) }; return .handled
                        }
                        return .ignored
                    }
                    let special: [KeyEquivalent: String] = [.return: "\r", .delete: "\u{7f}", .escape: "\u{1b}", .tab: "\t",
                        .upArrow: "\u{1b}[A", .downArrow: "\u{1b}[B", .rightArrow: "\u{1b}[C", .leftArrow: "\u{1b}[D",
                        .home: "\u{1b}[H", .end: "\u{1b}[F", .pageUp: "\u{1b}[5~", .pageDown: "\u{1b}[6~"]
                    var value = special[press.key] ?? press.characters
                    if press.modifiers.contains(.control), let scalar = press.characters.lowercased().unicodeScalars.first, scalar.value >= 64, scalar.value < 128 {
                        value = String(UnicodeScalar(scalar.value & 31)!)
                    } else if press.modifiers.contains(.option) { value = "\u{1b}" + value }
                    guard !value.isEmpty else { return .ignored }
                    Task { await terminal.send(value) }; return .handled
                }
                .accessibilityLabel("Interactive terminal")
                .task(id: geometry.size) { await terminal.resize(geometry.size) }
                .onAppear { focused = true }
            }
            HStack { Text(focused ? "Keyboard connected to remote shell" : "Click terminal to type"); Spacer(); Text("⌃C interrupt · ⇥ completion · ⌘V paste") }
                .font(.caption).foregroundStyle(Palette.muted).padding(10).background(Palette.chrome)

        }.background(Palette.background).buttonStyle(WorkbenchButton())
            .task(id: "\(state.threadID ?? "")/\(revision)") {
                guard let client = state.client, let device = state.deviceID, let thread = state.threadID else { terminal.error = "Select a conversation first."; return }
                await terminal.connect(client: client, device: device, thread: thread)
            }.onDisappear { terminal.disconnect() }
    }
    private func renderScreen() -> AttributedString {
        var result = AttributedString()
        for (index, line) in terminal.screen.lines.enumerated() {
            var text = AttributedString(String(line))
            text.foregroundColor = Palette.text
            if index == terminal.screen.row, focused, terminal.screen.cursorVisible {
                let cursor = terminal.screen.column
                if cursor >= line.count { text.append(AttributedString(String(repeating: " ", count: max(0, cursor - line.count)) + "▏")) }
            }
            result.append(text)
            if index < terminal.screen.lines.count - 1 { result.append(AttributedString("\n")) }
        }
        return result
    }
}
