import Foundation

final class APIClient {
    let store: SessionStore
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()

    init(store: SessionStore) {
        self.store = store
    }

    func fetchSession() async throws -> RelaySession {
        try await request("/relay/auth/session")
    }

    func login(identifier: String, password: String) async throws -> RelayLoginResult {
        let result: RelayLoginResult = try await request(
            "/relay/auth/login",
            method: "POST",
            body: ["identifier": identifier, "password": password],
            authed: false
        )
        if let token = result.token, !token.isEmpty {
            await MainActor.run { store.token = token }
        }
        return result
    }

    func fetchLoginChallenge() async throws -> LoginChallenge {
        try await request("/relay/auth/challenge", authed: false)
    }

    func verifyLoginCode(code: String, rememberBrowser: Bool) async throws -> RelayLoginResult {
        let result: RelayLoginResult = try await request(
            "/relay/auth/challenge",
            method: "POST",
            body: ["code": code, "rememberBrowser": rememberBrowser],
            authed: false
        )
        if let token = result.token, !token.isEmpty {
            await MainActor.run { store.token = token }
        }
        return result
    }

    func cancelLoginChallenge() async {
        _ = try? await raw("/relay/auth/challenge", method: "DELETE", body: nil, authed: false)
    }

    func fetchSecurity() async throws -> SecurityStatus {
        try await request("/relay/account/security")
    }

    func enrollAuthenticator() async throws -> AuthenticatorEnrollment {
        try await request("/relay/account/security/authenticator/enroll", method: "POST")
    }

    func confirmAuthenticator(code: String) async throws -> RecoveryCodesResult {
        try await request("/relay/account/security/authenticator/confirm", method: "POST", body: ["code": code])
    }

    func disableAuthenticator() async throws {
        let _: [String: String] = try await request("/relay/account/security/authenticator", method: "DELETE")
    }

    func regenerateRecoveryCodes() async throws -> RecoveryCodesResult {
        try await request("/relay/account/security/recovery-codes", method: "POST")
    }

    func revokeSecuritySession(_ id: String) async throws {
        let _: [String: String] = try await request("/relay/account/security/sessions/\(enc(id))", method: "DELETE")
    }

    func revokeTrustedBrowser(_ id: String) async throws {
        let _: [String: String] = try await request("/relay/account/security/browsers/\(enc(id))", method: "DELETE")
    }

    func fetchSetupToken(deviceId: String) async throws -> SetupTokenResult {
        try await request("/relay/devices/\(enc(deviceId))/setup-token", method: "POST")
    }

    func rotateDeviceToken(deviceId: String) async throws -> RelayCreateDeviceResult {
        try await request("/relay/devices/\(enc(deviceId))/token", method: "POST")
    }

    func revokeGrant(_ id: String) async throws {
        let _: [String: String] = try await request("/relay/grants/\(enc(id))", method: "DELETE")
    }

    func revokeShare(_ id: String) async throws {
        let _: [String: String] = try await request("/relay/shares/\(enc(id))", method: "DELETE")
    }

    func createGrant(
        deviceId: String,
        targetIdentifier: String,
        label: String,
        threadAccess: String,
        workspaceAccess: String,
        canCreateThreads: Bool
    ) async throws -> RelayGrant {
        var body: [String: Any] = [
            "targetIdentifier": targetIdentifier,
            "deviceId": deviceId,
            "scope": "device",
            "threadAccess": threadAccess,
            "workspaceAccess": workspaceAccess,
            "canCreateThreads": canCreateThreads,
        ]
        if !label.isEmpty { body["label"] = label }
        return try await request("/relay/grants", method: "POST", body: body)
    }

    func updateGrant(
        id: String,
        threadAccess: String,
        workspaceAccess: String,
        canCreateThreads: Bool,
        label: String?
    ) async throws -> RelayGrant {
        var body: [String: Any] = [
            "threadAccess": threadAccess,
            "workspaceAccess": workspaceAccess,
            "canCreateThreads": canCreateThreads,
        ]
        if let label { body["label"] = label }
        return try await request("/relay/grants/\(enc(id))", method: "PATCH", body: body)
    }

    func updateShare(
        id: String,
        threadAccess: String,
        workspaceAccess: String,
        label: String?
    ) async throws -> RelayShare {
        var body: [String: Any] = [
            "threadAccess": threadAccess,
            "workspaceAccess": workspaceAccess,
        ]
        if let label { body["label"] = label }
        return try await request("/relay/shares/\(enc(id))", method: "PATCH", body: body)
    }

    func register(email: String, username: String, password: String, registrationPassword: String?) async throws -> RelayRegisterResult {
        var body: [String: Any] = ["email": email, "username": username, "password": password]
        if let registrationPassword, !registrationPassword.isEmpty {
            body["registrationPassword"] = registrationPassword
        }
        let result: RelayRegisterResult = try await request("/relay/auth/register", method: "POST", body: body, authed: false)
        if let token = result.token {
            await MainActor.run { store.token = token }
        }
        return result
    }

    func logout() async {
        _ = try? await request("/relay/auth/logout", method: "POST") as RelaySession
        await MainActor.run { store.clearSession() }
    }

    func fetchPortal() async throws -> RelayPortal {
        try await request("/relay/portal")
    }

    func updateAccount(username: String) async throws -> RelayUser {
        try await request("/relay/account", method: "PATCH", body: ["username": username])
    }

    func updatePassword(current: String, new: String) async throws -> RelayUser {
        try await request("/relay/account/password", method: "PATCH", body: [
            "currentPassword": current,
            "newPassword": new,
        ])
    }

    func createDevice(name: String) async throws -> RelayCreateDeviceResult {
        try await request("/relay/devices", method: "POST", body: ["name": name])
    }

    func deleteDevice(_ id: String) async throws {
        let _: [String: String] = try await request("/relay/devices/\(enc(id))", method: "DELETE")
    }

    func fetchWorkspaces(deviceId: String) async throws -> [Workspace] {
        try await request(deviceApi(deviceId, "/api/workspaces"))
    }

    func fetchRuntime(deviceId: String) async throws -> RuntimeConfig {
        try await request(deviceApi(deviceId, "/api/config/runtime"))
    }

    func fetchWorkspaceSettings(deviceId: String) async throws -> WorkspaceSettings {
        try await request(deviceApi(deviceId, "/api/config/workspace-settings"))
    }

    func createWorkspace(deviceId: String, body: [String: Any]) async throws -> Workspace {
        try await request(deviceApi(deviceId, "/api/workspaces"), method: "POST", body: body)
    }

    func renameWorkspace(deviceId: String, workspaceId: String, label: String) async throws -> Workspace {
        try await request(deviceApi(deviceId, "/api/workspaces/\(enc(workspaceId))"), method: "PATCH", body: ["label": label])
    }

    func favoriteWorkspace(deviceId: String, workspaceId: String, favorite: Bool) async throws -> Workspace {
        try await request(deviceApi(deviceId, "/api/workspaces/\(enc(workspaceId))/favorite"), method: "POST", body: ["isFavorite": favorite])
    }

    func deleteWorkspace(deviceId: String, workspace: Workspace) async throws {
        let _: [String: String] = try await request(
            deviceApi(deviceId, "/api/workspaces/\(enc(workspace.id))"),
            method: "DELETE",
            body: ["confirmWorkspaceId": workspace.id, "confirmLabel": workspace.label]
        )
    }

    func fetchThreads(deviceId: String) async throws -> [ThreadSummary] {
        let data = try await raw(deviceApi(deviceId, "/api/threads"), method: "GET", body: nil)
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return ThreadSummary(
                id: id,
                workspaceId: row["workspaceId"] as? String,
                provider: row["provider"] as? String,
                title: row["title"] as? String,
                model: row["model"] as? String,
                status: row["status"] as? String,
                updatedAt: row["updatedAt"] as? String,
                lastTurnCompletedAt: row["lastTurnCompletedAt"] as? String
            )
        }
    }

    func renameThread(deviceId: String, threadId: String, title: String) async throws -> ThreadSummary {
        try await request(deviceApi(deviceId, "/api/threads/\(enc(threadId))"), method: "PATCH", body: ["title": title])
    }

    func deleteThread(deviceId: String, threadId: String) async throws {
        let _: [String: String] = try await request(deviceApi(deviceId, "/api/threads/\(enc(threadId))"), method: "DELETE")
    }

    func fetchBackends(deviceId: String) async throws -> [AgentBackend] {
        try await request(deviceApi(deviceId, "/api/agent-runtimes"))
    }

    func fetchModels(deviceId: String, provider: String) async throws -> [ModelOption] {
        try await request(deviceApi(deviceId, "/api/agent-runtimes/\(enc(provider))/models"))
    }

    func createThread(deviceId: String, workspaceId: String, title: String?, provider: String, model: String) async throws -> ThreadSummary {
        var body: [String: Any] = [
            "workspaceId": workspaceId,
            "provider": provider,
            "model": model,
            "approvalMode": "yolo",
        ]
        if let title, !title.isEmpty { body["title"] = title }
        return try await request(deviceApi(deviceId, "/api/threads/start"), method: "POST", body: body)
    }

    func importThread(deviceId: String, sessionId: String, provider: String) async throws -> [String: Any] {
        let data = try await raw(
            deviceApi(deviceId, "/api/threads/import"),
            method: "POST",
            body: ["sessionId": sessionId, "provider": provider]
        )
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func threadPageURL(deviceId: String, threadId: String) -> URL {
        let origin = store.relayUrl.isEmpty ? "about:blank" : store.relayUrl
        return URL(string: "\(origin)/devices/\(enc(deviceId))/threads/\(enc(threadId))?nativeApp=1")
            ?? URL(string: origin)
            ?? URL(string: "about:blank")!
    }

    func oauthStartURL(provider: String) -> URL {
        URL(string: "\(store.relayUrl)/relay/auth/oauth/\(enc(provider))/start")!
    }

    func socketURL(deviceId: String) -> URL {
        let base = store.relayUrl
        let ws = base.hasPrefix("https://")
            ? "wss://" + base.dropFirst("https://".count)
            : "ws://" + base.dropFirst("http://".count)
        var value = "\(ws)/relay/devices/\(enc(deviceId))/ws"
        if !store.token.isEmpty {
            value += "?relaySession=\(enc(store.token))"
        }
        return URL(string: value)!
    }

    private func deviceApi(_ deviceId: String, _ path: String) -> String {
        "/relay/devices/\(enc(deviceId))\(path)"
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, authed: Bool = true) async throws -> T {
        let data = try await raw(path, method: method, body: body, authed: authed)
        if data.isEmpty, T.self == RelaySession.self {
            throw APIError.message("Empty response")
        }
        do {
            return try decoder.decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            throw APIError.message(String(data: data, encoding: .utf8) ?? error.localizedDescription)
        }
    }

    private func raw(_ path: String, method: String, body: [String: Any]?, authed: Bool = true) async throws -> Data {
        guard let url = URL(string: store.relayUrl + path) else {
            throw APIError.message("Invalid relay URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authed, !store.token.isEmpty {
            request.setValue("Bearer \(store.token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != "GET" && method != "HEAD" {
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        var wakeAttempt = 0
        while true {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status < 400 {
                return data
            }
            let parsed = try? decoder.decode(ApiErrorBody.self, from: data)
            let hostedStarting = status == 503 && parsed?.details?.reason == "hosted_sandbox_starting"
            if !hostedStarting || wakeAttempt >= 60 {
                throw APIError.message(parsed?.message ?? String(data: data, encoding: .utf8) ?? "Request failed (\(status)).")
            }
            wakeAttempt += 1
            try await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private func enc(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
