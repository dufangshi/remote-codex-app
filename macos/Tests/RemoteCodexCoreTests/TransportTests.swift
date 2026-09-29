import XCTest
import CryptoKit
@testable import RemoteCodexCore

final class MemoryVault: SecretStore {
    var values: [String: String] = [:]
    func read(_ key: String) async throws -> String? { values[key] }
    func write(_ value: String?, for key: String) async throws { values[key] = value }
}

final class TransportTests: XCTestCase {
    func testRemoteFileLinksNeverTargetTheLocalHost() throws {
        XCTAssertEqual(try RemoteFileLink.path("file:///home/device/project/docs/guide.md#L12", root: "/home/device/project"), "docs/guide.md")
        XCTAssertEqual(try RemoteFileLink.path("../README.md", root: "/home/device/project", document: "docs/start.md"), "README.md")
        XCTAssertEqual(try RemoteFileLink.path("/home/device/project/a%20b.md:12", root: "/home/device/project"), "a b.md")
        XCTAssertEqual(try RemoteFileLink.path("C:/work/project/docs/a.md", root: "C:\\work\\project"), "docs/a.md")
        for path in ["../../etc/passwd", "file://other/home/key", "/Users/mac/.ssh/id_rsa", "https://evil.test/a", "//evil.test/a"] {
            XCTAssertThrowsError(try RemoteFileLink.path(path, root: "/home/device/project"))
        }
    }
    func testTerminalPreservesEscapeStateCursorAndAlternateScreen() {
        var terminal = TerminalBuffer()
        terminal.feed("hello\rHELLO\r\nnext")
        XCTAssertEqual(terminal.text, "HELLO\nnext")
        terminal.feed("\u{1b}["); terminal.feed("2K\rreplaced")
        XCTAssertEqual(terminal.text, "HELLO\nreplaced")
        terminal.feed("\u{1b}[?2004h"); XCTAssertTrue(terminal.bracketedPaste)
        terminal.feed("\u{1b}[?1049hTUI\u{1b}[2;1Hrow two")
        XCTAssertEqual(terminal.text, "TUI\nrow two")
        terminal.feed("\u{1b}[?1049l")
        XCTAssertEqual(terminal.text, "HELLO\nreplaced")
        terminal.feed("\u{1b}]0;private title"); terminal.feed("\u{7}")
        XCTAssertFalse(terminal.text.contains("private"))
    }
    func testNativeMarkdownBlocks() {
        let input = "# Title\n\nText **bold**.\n\n| Feature | State |\n| --- | :---: |\n| Chat | Ready |\n| Files | |\n\n~~~swift\nlet n = 1\n~~~\n\n- [x] tested\n> Quote\n---"
        XCTAssertEqual(MarkdownParser.blocks(input), [.heading(1, "Title"), .paragraph("Text **bold**."),
            .table(["Feature", "State"], [["Chat", "Ready"], ["Files", ""]]),
            .code("swift", "let n = 1"), .list("☑", "tested"), .quote("Quote"), .rule])
        XCTAssertEqual(MarkdownParser.cells("| escaped\\|pipe | \u{60}a|b\u{60} |"), ["escaped|pipe", "\u{60}a|b\u{60}"])
        XCTAssertEqual(MarkdownParser.blocks("~~~txt\nstreaming code"), [.code("txt", "streaming code")])
        XCTAssertEqual(MarkdownParser.blocks("a | b\nnot a separator"), [.paragraph("a | b\nnot a separator")])
        XCTAssertEqual(MarkdownParser.blocks("Title\n===\n\n> first\n> second\n\n~~~~text\n~~~\n~~~~"), [.heading(1, "Title"), .quote("first\nsecond"), .code("text", "~~~")])
    }
    func testSocketCipherRejectsReplayTamperAndPlaintext() throws {
        let a = SymmetricKey(size: .bits256), b = SymmetricKey(size: .bits256)
        var client = SocketCipher(channel: "one", send: a, receive: b)
        var server = SocketCipher(channel: "one", send: b, receive: a)
        let request: [String: Any] = ["type": "shell.input", "shellId": "shell", "data": "echo secure"]
        let frame = try client.seal(request)
        XCTAssertEqual(try server.open(frame)["data"] as? String, "echo secure")
        XCTAssertThrowsError(try server.open(frame))
        let response = try server.seal(["type": "shell.output", "shellId": "shell", "payload": ["data": "secure"]])
        var changed = try JSONSerialization.jsonObject(with: response) as! [String: Any]
        changed["shellId"] = "other"
        XCTAssertThrowsError(try client.open(JSONSerialization.data(withJSONObject: changed)))
        XCTAssertEqual(try client.open(response)["type"] as? String, "shell.output")
        XCTAssertThrowsError(try client.open(Data(#"{"type":"shell.output","payload":{"data":"plaintext"}}"#.utf8)))
        var wrong = SocketCipher(channel: "wrong", send: b, receive: a)
        XCTAssertThrowsError(try wrong.open(try client.seal(request)))
    }
    @MainActor func testBrowserSessionAndNativePinsStayInVault() async throws {
        let vault = MemoryVault()
        let origin = "https://relay.example.com"
        let device = "89b047e5-6e45-45d8-90f6-99607cb1fe16"
        vault.values["identity:\(origin):\(device)"] = "existing-pin"
        let client = try await RelayClient(origin: origin, vault: vault)
        try await client.syncBrowserSession("synthetic-session")
        XCTAssertEqual(vault.values["session:" + origin], "synthetic-session")
        XCTAssertTrue(client.signedIn)
        let cookie = try XCTUnwrap(client.browserCookies().first)
        XCTAssertTrue(cookie.isHTTPOnly)
        XCTAssertTrue(cookie.isSecure)
        let pins = try await client.pinnedIdentities([device])
        XCTAssertEqual(pins[device], "existing-pin")
        try await client.syncBrowserSession(nil)
        XCTAssertFalse(client.signedIn)
        XCTAssertNil(vault.values["session:" + origin])
        XCTAssertEqual(vault.values["identity:\(origin):\(device)"], "existing-pin")
    }
    func testBrowserRoutesStayOnRelayAndDoNotPersistSecrets() throws {
        let origin = URL(string: "https://relay.example.com")!
        XCTAssertTrue(BrowserPolicy.sameOrigin(URL(string: "https://relay.example.com:443/devices")!, origin))
        for raw in ["http://relay.example.com", "https://relay.example.com.evil.test", "https://relay.example.com:444", "https://user@relay.example.com"] {
            XCTAssertFalse(BrowserPolicy.sameOrigin(URL(string: raw)!, origin))
        }
        XCTAssertEqual(BrowserPolicy.restoredURL("//evil.test/a", origin: origin).path, "/relay-devices")
        let url = URL(string: "https://relay.example.com/devices/one/workspaces?token=secret#private")!
        XCTAssertEqual(BrowserPolicy.rememberedPath(url, origin: origin), "/devices/one/workspaces")
        XCTAssertNil(BrowserPolicy.rememberedPath(URL(string: "https://relay.example.com/login?code=secret")!, origin: origin))
    }
    func testContinuationAcceptsOnlyScopedSequentialChunks() throws {
        let id = "89b047e5-6e45-45d8-90f6-99607cb1fe16"
        let prefix = "/api/threads/\(id)/transport/stream/"
        var stream = Continuation(path: "/api/threads/\(id)?limit=20")
        try stream.accept(prefix + "opaque_token-1?chunk=1")
        try stream.accept(prefix + "opaque_token-1?chunk=2")
        for bad in [prefix + "opaque_token-1?chunk=2", prefix + "opaque_token-1?chunk=4", prefix + "other?chunk=3",
                    prefix + "opaque_token-1?chunk=3&url=https://example.com", prefix + "opaque_token-1?chunk=3#fragment",
                    "/api/transport/stream/opaque_token-1?chunk=3", prefix + "../escape?chunk=3",
                    prefix + "%2e%2e?chunk=3", "https://example.com" + prefix + "opaque_token-1?chunk=3"] {
            XCTAssertThrowsError(try stream.accept(bad), bad)
        }
        try stream.accept(prefix + "opaque_token-1?chunk=3")
        var workspace = Continuation(path: "/api/workspaces/\(id)/files/raw?path=test.txt")
        try workspace.accept("/api/workspaces/\(id)/transport/stream/file-token?chunk=1")
        var collection = Continuation(path: "/api/threads")
        try collection.accept("/api/transport/stream/list-token?chunk=1")
    }
    @MainActor func testOriginsAreBoundAndSecure() throws {
        XCTAssertEqual(try RelayClient.normalizedOrigin("relay.example.com/").absoluteString, "https://relay.example.com")
        XCTAssertEqual(try RelayClient.normalizedOrigin("http://127.0.0.1:18790").port, 18790)
        for bad in ["http://example.com", "https://user:pass@example.com", "https://example.com/path", "https://example.com?token=secret", "file:///tmp", "https://example.com/#foo"] {
            XCTAssertThrowsError(try RelayClient.normalizedOrigin(bad), bad)
        }
    }
    func testPacketRoundtripAndTruncation() throws {
        let body = Data("原生附件\u{0}body".utf8)
        let packet = try Packet.pack(["status": 200, "headers": ["content-type": "text/plain"]], body: body)
        let decoded = try Packet.unpack(packet)
        XCTAssertEqual(decoded.metadata["status"] as? Int, 200)
        XCTAssertEqual(decoded.body, body)
        for bad in [Data(), Data([0, 0, 0]), Data([0, 1, 0, 1]), Data([0, 0, 0, 90, 123])] {
            XCTAssertThrowsError(try Packet.unpack(bad))
        }
        XCTAssertThrowsError(try Packet.pack(["text": String(repeating: "x", count: 65536)], body: Data()))
    }
    func testBase64URLRoundtrip() throws {
        let data = Data((0...255).map(UInt8.init))
        XCTAssertFalse(data.base64URL.contains("="))
        XCTAssertEqual(try Data(base64URL: data.base64URL), data)
        XCTAssertThrowsError(try Data(base64URL: "not@base64"))
    }
    func testPhotoTokenizationAndMultipartLimits() throws {
        let segments = MessageSegment.parse("你好 [PHOTO ./.temp/image 1.png] after [PHOTO ./second.png]")
        XCTAssertEqual(segments.compactMap(\.photoPath), ["./.temp/image 1.png", "./second.png"])
        XCTAssertEqual(segments.compactMap(\.text).joined(), "你好  after ")
        XCTAssertEqual(Set(segments.map(\.id)).count, segments.count)
        let payload = try PromptBody.build(text: "look", requestID: "id", images: [ImageAttachment(data: Data([1, 2, 3]), mimeType: "image/png")])
        XCTAssertTrue(payload.contentType.hasPrefix("multipart/form-data; boundary="))
        XCTAssertTrue(String(decoding: payload.body, as: UTF8.self).contains("attachmentManifest"))
        XCTAssertThrowsError(try PromptBody.build(text: "", requestID: "id", images: [ImageAttachment(data: Data(), mimeType: "image/png\r\nInjected: yes")]))
        XCTAssertThrowsError(try PromptBody.build(text: "", requestID: "id", images: Array(repeating: ImageAttachment(data: Data(), mimeType: "image/png"), count: 9)))
    }
    func testDescriptorSignatureAndChallenge() throws {
        let identity = P256.Signing.PrivateKey()
        let recipient = P256.KeyAgreement.PrivateKey()
        let publicKey = recipient.publicKey.x963Representation.base64URL
        let signed = "rcd-key-v1\nchallenge\nkey\n3600001\n1\n\(publicKey)"
        let signature = try identity.signature(for: Data(signed.utf8)).rawRepresentation.base64URL
        let descriptor = KeyDescriptor(version: 1, challenge: "challenge", keyId: "key", expiresAt: 3600001, serverTime: 1,
                                       publicKey: publicKey, identityKey: identity.publicKey.x963Representation.base64URL, signature: signature)
        try descriptor.verify(challenge: "challenge")
        XCTAssertThrowsError(try descriptor.verify(challenge: "replayed"))
        let invalid = KeyDescriptor(version: 1, challenge: "challenge", keyId: "tampered", expiresAt: 3600001, serverTime: 1,
                                    publicKey: publicKey, identityKey: identity.publicKey.x963Representation.base64URL, signature: signature)
        XCTAssertThrowsError(try invalid.verify(challenge: "challenge"))
    }
    func testHPKERequestAndExportedResponse() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let info = Data("remote-codex/relay/v1".utf8), aad = Data("request aad".utf8)
        var sender = try HPKE.Sender(recipientKey: key.publicKey, ciphersuite: .P256_SHA256_AES_GCM_256, info: info)
        var recipient = try HPKE.Recipient(privateKey: key, ciphersuite: .P256_SHA256_AES_GCM_256, info: info, encapsulatedKey: sender.encapsulatedKey)
        let clear = Data("hello encrypted device".utf8)
        let sealed = try sender.seal(clear, authenticating: aad)
        XCTAssertEqual(try recipient.open(sealed, authenticating: aad), clear)
        let context = Data("remote-codex/http-response/v1".utf8)
        let response = try AES.GCM.seal(clear, using: recipient.exportSecret(context: context, outputByteCount: 32), nonce: AES.GCM.Nonce(data: Data(repeating: 0, count: 12)), authenticating: aad)
        XCTAssertEqual(try AES.GCM.open(response, using: sender.exportSecret(context: context, outputByteCount: 32), authenticating: aad), clear)
        XCTAssertThrowsError(try AES.GCM.open(response, using: sender.exportSecret(context: context, outputByteCount: 32), authenticating: Data("tampered".utf8)))
    }
    @MainActor func testSeededTraceSummaryAndDetail() async throws {
        guard ProcessInfo.processInfo.environment["REMOTE_CODEX_MAC_TRACE_E2E"] == "1", let file = ProcessInfo.processInfo.environment["REMOTE_CODEX_MAC_E2E_ENV"] else { throw XCTSkip("Run seed-parity and seed-native-trace in the isolated fixture.") }
        struct Fixture: Decodable { let relayUrl: String; let username: String; let password: String; let deviceId: String }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        guard URL(string: fixture.relayUrl)?.host == "127.0.0.1" else { throw APIError("Loopback fixture required.") }
        let client = try await RelayClient(origin: fixture.relayUrl, vault: MemoryVault())
        _ = try await client.login(identifier: fixture.username, password: fixture.password)
        let threads: [ThreadSummary] = try await client.device(fixture.deviceId, "/api/threads")
        let thread = try XCTUnwrap(threads.first { $0.title == "Mac parity checklist" })
        let summary: ThreadDetail = try await client.device(fixture.deviceId, "/api/threads/\(thread.id)?limit=3&view=summary")
        let turn = try XCTUnwrap(summary.turns.first { $0.hasDeferredItems == true })
        XCTAssertFalse(turn.items.contains { $0.kind == "commandExecution" })
        let full: Turn = try await client.device(fixture.deviceId, "/api/threads/\(thread.id)/turns/\(turn.id)/detail")
        XCTAssertTrue(full.items.contains { $0.text == "First intermediate checkpoint is retained." })
        XCTAssertTrue(full.items.contains { $0.text == "Second intermediate checkpoint is retained." })
        let commands = full.items.filter { $0.kind == "commandExecution" }
        XCTAssertEqual(commands.map(\.text), ["printf trace-one", "printf trace-two"])
        let detail: HistoryItem = try await client.device(fixture.deviceId, "/api/threads/\(thread.id)/items/\(commands[0].id)/detail")
        XCTAssertTrue(detail.text.contains("literal asterisks"))
    }
    @MainActor func testIsolatedRustRelayInterop() async throws {
        guard let file = ProcessInfo.processInfo.environment["REMOTE_CODEX_MAC_E2E_ENV"] else {
            throw XCTSkip("Set REMOTE_CODEX_MAC_E2E_ENV to the isolated backend fixture JSON.")
        }
        struct Fixture: Decodable { let relayUrl: String; let username: String; let password: String; let deviceId: String; let workspaceId: String }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        guard URL(string: fixture.relayUrl)?.host == "127.0.0.1" else { throw APIError("Integration test must target the isolated loopback relay.") }
        let vault = MemoryVault()
        let client = try await RelayClient(origin: fixture.relayUrl, vault: vault)
        let signedIn = try await client.login(identifier: fixture.username, password: fixture.password)
        XCTAssertTrue(signedIn)
        let portal: Portal = try await client.relay("/relay/portal")
        XCTAssertTrue(portal.allDevices.contains { $0.id == fixture.deviceId })
        let workspaces: [Workspace] = try await client.device(fixture.deviceId, "/api/workspaces")
        XCTAssertTrue(workspaces.contains { $0.id == fixture.workspaceId })
        let _: [ModelOption] = try await client.device(fixture.deviceId, "/api/agent-runtimes/acp/agents")
        let models: [ModelOption] = try await client.device(fixture.deviceId, "/api/agent-runtimes/acp/models?agentId=codex")
        XCTAssertFalse(models.isEmpty)
        let created: ThreadSummary = try await client.device(fixture.deviceId, "/api/threads/start", method: "POST", body: ["workspaceId": fixture.workspaceId, "provider": "acp", "agentId": "codex", "model": models[0].model, "title": "Native Mac transport regression", "approvalMode": "yolo"])
        let prompt: [String: Any] = ["prompt": "Reply exactly native-ok", "clientRequestId": UUID().uuidString]
        _ = try await client.deviceData(fixture.deviceId, "/api/threads/\(created.id)/prompt", method: "POST", body: JSONSerialization.data(withJSONObject: prompt))
        var detail: ThreadDetail = try await client.device(fixture.deviceId, "/api/threads/\(created.id)")
        for _ in 0..<30 where detail.turns.isEmpty || detail.thread.activeTurnId != nil {
            try await Task.sleep(for: .milliseconds(200))
            detail = try await client.device(fixture.deviceId, "/api/threads/\(created.id)")
        }
        XCTAssertFalse(detail.turns.isEmpty)
        XCTAssertTrue(detail.turns.flatMap(\.items).contains { $0.kind == "agentMessage" && !$0.text.isEmpty })
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1kAAAAASUVORK5CYII=")!
        let attachment = try PromptBody.build(text: "Inspect this image", requestID: UUID().uuidString, images: [ImageAttachment(data: png, mimeType: "image/png")])
        _ = try await client.deviceData(fixture.deviceId, "/api/threads/\(created.id)/prompt", method: "POST", body: attachment.body, contentType: attachment.contentType)
        detail = try await client.device(fixture.deviceId, "/api/threads/\(created.id)")
        for _ in 0..<30 where detail.thread.activeTurnId != nil {
            try await Task.sleep(for: .milliseconds(200))
            detail = try await client.device(fixture.deviceId, "/api/threads/\(created.id)")
        }
        let photos = detail.turns.flatMap(\.items).flatMap { MessageSegment.parse($0.text) }.compactMap(\.photoPath)
        let photo = try XCTUnwrap(photos.first)
        var imageQuery = URLComponents()
        imageQuery.queryItems = [URLQueryItem(name: "path", value: photo)]
        let returned = try await client.deviceData(fixture.deviceId, "/api/threads/\(created.id)/assets/image?" + (imageQuery.percentEncodedQuery ?? ""))
        XCTAssertEqual(returned, png)
        // Exercise actual multi-chunk encrypted responses, not just tiny synthetic transcripts.
        let files = WorkspaceAPI(client: client, deviceID: fixture.deviceId, workspaceID: fixture.workspaceId)
        let filename = "native-\(UUID().uuidString)-中文..txt"
        let largeText = String(repeating: "Encrypted native workspace regression.\n", count: 70_000)
        try await files.create(filename, content: largeText)
        let downloaded = try await files.read(filename)
        XCTAssertEqual(downloaded, Data(largeText.utf8))
        let tree = try await files.tree()
        XCTAssertTrue(tree.children?.contains { $0.name == filename } == true)
        let edited = try await files.save(filename, content: "saved from native editor\n", original: downloaded)
        XCTAssertEqual(edited, Data("saved from native editor\n".utf8))
        do { _ = try await files.save(filename, content: "stale overwrite", original: downloaded); XCTFail("Conflicting edit was accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("changed on the device")) }
        let stillSaved = try await files.read(filename)
        XCTAssertEqual(stillSaved, edited)
        do { try await files.create(filename); XCTFail("Existing file was overwritten") }
        catch { XCTAssertTrue(error.localizedDescription.contains("already exists")) }

        let longPrompt = String(repeating: "long history line\n", count: 70_000)
        let longBody = try PromptBody.build(text: longPrompt, requestID: UUID().uuidString, images: [])
        _ = try await client.deviceData(fixture.deviceId, "/api/threads/\(created.id)/prompt", method: "POST", body: longBody.body)
        for _ in 0..<40 {
            detail = try await client.device(fixture.deviceId, "/api/threads/\(created.id)?limit=1&view=full")
            if detail.thread.activeTurnId == nil, detail.turns.last?.items.contains(where: { $0.text == longPrompt }) == true { break }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTAssertTrue(detail.turns.flatMap(\.items).contains { $0.text == longPrompt })
        let lastTurn = try XCTUnwrap(detail.turns.first)
        let earlier: ThreadDetail = try await client.device(fixture.deviceId, "/api/threads/\(created.id)?limit=1&beforeTurnId=\(lastTurn.id)&view=full")
        XCTAssertEqual(earlier.turns.count, 1)
        XCTAssertNotEqual(earlier.turns.first?.id, lastTurn.id)
        XCTAssertGreaterThanOrEqual(earlier.totalTurnCount ?? 0, 3)
        let modelChanged: ThreadSummary = try await client.device(fixture.deviceId, "/api/threads/\(created.id)/settings", method: "PATCH", body: ["reasoningEffort": "high"])
        XCTAssertEqual(modelChanged.reasoningEffort, "high")
        let auto: ThreadSummary = try await client.device(fixture.deviceId, "/api/threads/\(created.id)/settings", method: "PATCH", body: ["reasoningEffort": "auto"])
        XCTAssertEqual(auto.reasoningEffort, "auto")
        let navigation: WorkbenchSnapshot = try await client.relay("/relay/account/workbench", method: "POST", body: [
            "deviceId": fixture.deviceId, "threadId": created.id, "title": created.title,
            "workspaceId": fixture.workspaceId, "workspaceLabel": "mobile-ws", "favorite": true
        ])
        XCTAssertTrue(navigation.threads.contains { $0.threadId == created.id && $0.deviceId == fixture.deviceId && $0.favorite })
        let export = try await client.deviceData(fixture.deviceId, "/api/threads/\(created.id)/exports/html?limit=100")
        XCTAssertTrue(String(decoding: export, as: UTF8.self).contains("Native Mac transport regression"))
        // A real encrypted WebSocket, not a mocked UI terminal.
        struct ShellResponse: Decodable { let activeShellId: String }
        let shell: ShellResponse = try await client.device(fixture.deviceId, "/api/threads/\(created.id)/shell", method: "POST", body: ["cols": 100, "rows": 32])
        let socket = try await client.socket(device: fixture.deviceId, thread: created.id)
        let deadline = Task { try await Task.sleep(for: .seconds(12)); socket.close() }
        defer { deadline.cancel(); socket.close() }
        try await socket.send(["type": "shell.attach", "shellId": shell.activeShellId, "cols": 100, "rows": 32])
        var viewer: String?
        for _ in 0..<20 {
            let event = try await socket.receive()
            if event["type"] as? String == "shell.connected" { viewer = (event["payload"] as? [String: Any])?["viewerId"] as? String; break }
        }
        let viewerID = try XCTUnwrap(viewer)
        try await socket.send(["type": "shell.input", "shellId": shell.activeShellId, "viewerId": viewerID, "data": "printf '\\156\\141\\164\\151\\166\\145-socket-ok\\n'\n"])
        var output = ""
        while !output.contains("native-socket-ok") {
            let event = try await socket.receive()
            output += (event["payload"] as? [String: Any])?["data"] as? String ?? ""
        }
        XCTAssertTrue(output.contains("native-socket-ok"))
        try await socket.send(["type": "shell.input", "shellId": shell.activeShellId, "viewerId": viewerID, "data": "exit\n"])
        _ = try await client.deviceData(fixture.deviceId, "/api/shells/\(shell.activeShellId)/terminate", method: "POST", body: Data("{}".utf8))
        socket.close(); deadline.cancel()
        let pin = "identity:\(client.origin.absoluteString):\(fixture.deviceId)"
        XCTAssertNotNil(vault.values[pin])
        vault.values[pin] = "changed-identity"
        let freshClient = try await RelayClient(origin: fixture.relayUrl, vault: vault)
        do {
            let _: [Workspace] = try await freshClient.device(fixture.deviceId, "/api/workspaces")
            XCTFail("Changed device identity was accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("identity changed")) }
        try await client.logout()
        XCTAssertFalse(client.signedIn)
        XCTAssertNil(vault.values["session:" + client.origin.absoluteString])
    }
}
