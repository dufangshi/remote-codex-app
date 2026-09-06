package com.remotecodex.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

class ApiClient(
    private val store: SessionStore,
) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        explicitNulls = false
    }

    private val http = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    private val media = "application/json; charset=utf-8".toMediaType()

    fun websocketClient(): OkHttpClient = http.newBuilder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    suspend fun fetchSession(): RelaySession =
        request("/relay/auth/session")

    suspend fun login(identifier: String, password: String): RelayLoginResult {
        val result: RelayLoginResult = request(
            "/relay/auth/login",
            method = "POST",
            body = json.encodeToString(
                buildJsonObject {
                    put("identifier", identifier)
                    put("password", password)
                },
            ),
            authed = false,
        )
        store.token = result.token
        return result
    }

    suspend fun register(
        email: String,
        username: String,
        password: String,
        registrationPassword: String?,
    ): RelayRegisterResult {
        val result: RelayRegisterResult = request(
            "/relay/auth/register",
            method = "POST",
            body = json.encodeToString(
                buildJsonObject {
                    put("email", email)
                    put("username", username)
                    put("password", password)
                    if (!registrationPassword.isNullOrBlank()) {
                        put("registrationPassword", registrationPassword)
                    }
                },
            ),
            authed = false,
        )
        result.token?.let { store.token = it }
        return result
    }

    suspend fun logout() {
        runCatching {
            request<RelaySession>("/relay/auth/logout", method = "POST")
        }
        store.clearSession()
    }

    suspend fun fetchPortal(): RelayPortal = request("/relay/portal")

    suspend fun updateAccount(username: String): RelayUser = request(
        "/relay/account",
        method = "PATCH",
        body = json.encodeToString(buildJsonObject { put("username", username) }),
    )

    suspend fun updatePassword(currentPassword: String, newPassword: String): RelayUser = request(
        "/relay/account/password",
        method = "PATCH",
        body = json.encodeToString(
            buildJsonObject {
                put("currentPassword", currentPassword)
                put("newPassword", newPassword)
            },
        ),
    )

    suspend fun createDevice(name: String): RelayCreateDeviceResult = request(
        "/relay/devices",
        method = "POST",
        body = json.encodeToString(buildJsonObject { put("name", name) }),
    )

    suspend fun deleteDevice(deviceId: String) {
        request<JsonObject>("/relay/devices/${enc(deviceId)}", method = "DELETE")
    }

    suspend fun fetchWorkspaces(deviceId: String): List<Workspace> =
        request(deviceApi(deviceId, "/api/workspaces"))

    suspend fun fetchRuntime(deviceId: String): RuntimeConfig =
        request(deviceApi(deviceId, "/api/config/runtime"))

    suspend fun fetchWorkspaceSettings(deviceId: String): WorkspaceSettings =
        request(deviceApi(deviceId, "/api/config/workspace-settings"))

    suspend fun createWorkspace(deviceId: String, payload: JsonObject): Workspace = request(
        deviceApi(deviceId, "/api/workspaces"),
        method = "POST",
        body = json.encodeToString(payload),
    )

    suspend fun renameWorkspace(deviceId: String, workspaceId: String, label: String): Workspace =
        request(
            deviceApi(deviceId, "/api/workspaces/${enc(workspaceId)}"),
            method = "PATCH",
            body = json.encodeToString(buildJsonObject { put("label", label) }),
        )

    suspend fun favoriteWorkspace(deviceId: String, workspaceId: String, favorite: Boolean): Workspace =
        request(
            deviceApi(deviceId, "/api/workspaces/${enc(workspaceId)}/favorite"),
            method = "POST",
            body = json.encodeToString(buildJsonObject { put("isFavorite", favorite) }),
        )

    suspend fun deleteWorkspace(deviceId: String, workspace: Workspace) {
        request<JsonObject>(
            deviceApi(deviceId, "/api/workspaces/${enc(workspace.id)}"),
            method = "DELETE",
            body = json.encodeToString(
                buildJsonObject {
                    put("confirmWorkspaceId", workspace.id)
                    put("confirmLabel", workspace.label)
                },
            ),
        )
    }

    suspend fun fetchThreads(deviceId: String): List<ThreadSummary> =
        request(deviceApi(deviceId, "/api/threads"))

    suspend fun renameThread(deviceId: String, threadId: String, title: String): ThreadSummary =
        request(
            deviceApi(deviceId, "/api/threads/${enc(threadId)}"),
            method = "PATCH",
            body = json.encodeToString(buildJsonObject { put("title", title) }),
        )

    suspend fun deleteThread(deviceId: String, threadId: String) {
        request<JsonObject>(
            deviceApi(deviceId, "/api/threads/${enc(threadId)}"),
            method = "DELETE",
        )
    }

    suspend fun fetchBackends(deviceId: String): List<AgentBackend> =
        request(deviceApi(deviceId, "/api/agent-runtimes"))

    suspend fun fetchModels(deviceId: String, provider: String): List<ModelOption> =
        request(deviceApi(deviceId, "/api/agent-runtimes/${enc(provider)}/models"))

    suspend fun fetchAgents(deviceId: String, provider: String): List<ModelOption> =
        request(deviceApi(deviceId, "/api/agent-runtimes/${enc(provider)}/agents"))

    suspend fun createThread(
        deviceId: String,
        workspaceId: String,
        title: String?,
        provider: String,
        model: String,
        agentId: String? = null,
        reasoningEffort: String? = null,
    ): ThreadSummary = request(
        deviceApi(deviceId, "/api/threads/start"),
        method = "POST",
        body = json.encodeToString(
            buildJsonObject {
                put("workspaceId", workspaceId)
                put("provider", provider)
                put("model", model)
                put("approvalMode", "yolo")
                if (!title.isNullOrBlank()) put("title", title)
                if (!agentId.isNullOrBlank()) put("agentId", agentId)
                if (!reasoningEffort.isNullOrBlank()) put("reasoningEffort", reasoningEffort)
            },
        ),
    )

    suspend fun importThread(deviceId: String, sessionId: String, provider: String, agentId: String?): JsonObject =
        request(
            deviceApi(deviceId, "/api/threads/import"),
            method = "POST",
            body = json.encodeToString(
                buildJsonObject {
                    put("sessionId", sessionId)
                    put("provider", provider)
                    if (!agentId.isNullOrBlank()) put("agentId", agentId)
                },
            ),
        )

    suspend fun fetchImportCandidates(deviceId: String, provider: String, agentId: String?): List<ImportCandidate> {
        val query = buildString {
            append("provider=").append(enc(provider))
            if (!agentId.isNullOrBlank()) append("&agentId=").append(enc(agentId))
        }
        return request(deviceApi(deviceId, "/api/threads/import-candidates?$query"))
    }

    fun openDeviceSocket(deviceId: String, listener: WebSocketListener): WebSocket {
        val url = socketUrl(deviceId)
        val request = Request.Builder().url(url).build()
        return websocketClient().newWebSocket(request, listener)
    }

    fun threadPageUrl(deviceId: String, threadId: String): String {
        val base = store.relayUrl.trimEnd('/')
        return "$base/devices/${enc(deviceId)}/threads/${enc(threadId)}?nativeApp=1"
    }

    fun oauthStartUrl(provider: String): String =
        "${store.relayUrl.trimEnd('/')}/relay/auth/oauth/${enc(provider)}/start"

    fun socketUrl(deviceId: String): String {
        val base = store.relayUrl.trimEnd('/')
        val ws = if (base.startsWith("https://")) "wss://" + base.removePrefix("https://")
        else "ws://" + base.removePrefix("http://")
        val builder = StringBuilder("$ws/relay/devices/${enc(deviceId)}/ws")
        val token = store.token
        if (token.isNotBlank()) {
            builder.append("?relaySession=").append(enc(token))
        }
        return builder.toString()
    }

    private fun deviceApi(deviceId: String, path: String) =
        "/relay/devices/${enc(deviceId)}$path"

    private suspend inline fun <reified T> request(
        path: String,
        method: String = "GET",
        body: String? = null,
        authed: Boolean = true,
    ): T = withContext(Dispatchers.IO) {
        val url = store.relayUrl.trimEnd('/') + path
        val builder = Request.Builder().url(url)
        val requestBody = body?.toRequestBody(media)
        builder.method(method, if (method == "GET" || method == "HEAD") null else requestBody ?: "".toRequestBody(media))
        builder.header("Accept", "application/json")
        if (authed && store.token.isNotBlank()) {
            builder.header("Authorization", "Bearer ${store.token}")
        }
        http.newCall(builder.build()).execute().use { response ->
            parse(response)
        }
    }

    private inline fun <reified T> parse(response: Response): T {
        val text = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            val error = runCatching { json.decodeFromString<ApiErrorBody>(text) }.getOrElse {
                ApiErrorBody(message = text.ifBlank { "Request failed (${response.code})." })
            }
            throw ApiException(response.code, error)
        }
        if (text.isBlank() || T::class == Unit::class) {
            @Suppress("UNCHECKED_CAST")
            return Unit as T
        }
        return json.decodeFromString(text)
    }

    private fun enc(value: String) = java.net.URLEncoder.encode(value, Charsets.UTF_8.name())
        .replace("+", "%20")
}
