package com.remotecodex.app.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

@Serializable
data class ApiErrorBody(
    val code: String? = null,
    val message: String = "Request failed.",
    val details: JsonObject? = null,
)

class ApiException(
    val statusCode: Int,
    val body: ApiErrorBody,
) : Exception(body.message)

@Serializable
data class RelayUser(
    val id: String = "",
    val email: String = "",
    val username: String = "",
    val role: String = "user",
    val enabled: Boolean = true,
    val createdAt: String = "",
)

@Serializable
data class RegistrationSettings(
    val enabled: Boolean = false,
    val registrationPasswordConfigured: Boolean = false,
    val approvalRequired: Boolean = false,
    val googleAuthEnabled: Boolean = false,
    val githubAuthEnabled: Boolean = false,
)

@Serializable
data class RelaySession(
    val authenticated: Boolean = false,
    val user: RelayUser? = null,
    val registrationEnabled: Boolean = false,
    val registrationSettings: RegistrationSettings? = null,
)

@Serializable
data class RelayLoginResult(
    val token: String,
    val session: RelaySession,
)

@Serializable
data class RelayRegisterResult(
    val token: String? = null,
    val session: RelaySession? = null,
    val pendingApproval: Boolean = false,
)

@Serializable
data class RelayDevice(
    val id: String,
    val ownerUserId: String = "",
    val name: String,
    val token: String? = null,
    val tokenPreview: String = "",
    val connected: Boolean = false,
    val connectedAt: String? = null,
    val lastHeartbeatAt: String? = null,
    val createdAt: String = "",
    val hostedStatus: String? = null,
)

@Serializable
data class RelayCreateDeviceResult(
    val device: RelayDevice,
    val token: String,
)

@Serializable
data class RelayShare(
    val id: String,
    val ownerUsername: String = "",
    val targetUsername: String = "",
    val deviceId: String,
    val deviceName: String = "",
    val threadId: String,
    val threadTitle: String? = null,
    val workspaceId: String? = null,
    val workspaceLabel: String? = null,
    val threadAccess: String = "read",
    val workspaceAccess: String = "none",
)

@Serializable
data class RelayGrant(
    val id: String,
    val ownerUsername: String = "",
    val targetUsername: String = "",
    val deviceId: String,
    val deviceName: String = "",
    val scope: String = "device",
    val threadId: String? = null,
    val threadTitle: String? = null,
    val workspaceId: String? = null,
    val workspaceLabel: String? = null,
    val threadAccess: String = "read",
    val workspaceAccess: String = "none",
    val canCreateThreads: Boolean = false,
)

@Serializable
data class RelayPortal(
    val user: RelayUser,
    val devices: List<RelayDevice> = emptyList(),
    val sharedWithMe: List<RelayShare> = emptyList(),
    val sharedByMe: List<RelayShare> = emptyList(),
    val sharedDevicesWithMe: List<RelayGrant> = emptyList(),
    val sharedThreadsWithMe: List<RelayGrant> = emptyList(),
    val grantsByMe: List<RelayGrant> = emptyList(),
)

@Serializable
data class Workspace(
    val id: String,
    val hostId: String = "",
    val label: String,
    val absPath: String = "",
    val isFavorite: Boolean = false,
    val createdAt: String = "",
    val lastOpenedAt: String? = null,
)

@Serializable
data class RuntimeConfig(
    val appName: String = "Remote Codex",
    val appVersion: String = "",
    val environment: String = "",
    val host: String = "",
    val port: Int = 0,
    val workspaceRoot: String = "",
)

@Serializable
data class WorkspaceSettings(
    val workspaceRoot: String = "",
    val devHome: String = "",
    val defaultBackend: String = "codex",
)

@Serializable
data class ThreadSummary(
    val id: String,
    val workspaceId: String = "",
    val provider: String = "codex",
    val title: String = "Thread",
    val model: String? = null,
    val status: String = "idle",
    val lastError: String? = null,
    val createdAt: String = "",
    val updatedAt: String = "",
)

@Serializable
data class AgentBackend(
    val provider: String,
    val displayName: String = "",
    val enabled: Boolean = false,
    val isDefault: Boolean = false,
    val capabilities: AgentCapabilities = AgentCapabilities(),
)

@Serializable
data class AgentCapabilities(
    val sessions: CapabilityFlag = CapabilityFlag(),
    val turns: CapabilityFlag = CapabilityFlag(),
)

@Serializable
data class CapabilityFlag(
    val resume: Boolean = false,
    val start: Boolean = false,
    val importLocal: Boolean = false,
)

@Serializable
data class ModelOption(
    val id: String = "",
    val model: String = "",
    val displayName: String = "",
    val isDefault: Boolean = false,
    val defaultReasoningEffort: String? = null,
    val selectionKind: String? = null,
    val availability: String? = null,
)

@Serializable
data class ImportCandidate(
    val provider: String = "",
    val agentId: String? = null,
    val sessionId: String = "",
    val title: String? = null,
    val cwd: String? = null,
)

@Serializable
data class ThreadEvent(
    val type: String,
    val threadId: String,
    val timestamp: String? = null,
    val payload: JsonObject = JsonObject(emptyMap()),
)

fun ThreadEvent.status(): String? =
    payload["status"]?.asString()

fun ThreadEvent.error(): String? =
    payload["error"]?.asString()

fun ThreadEvent.title(): String? =
    payload["title"]?.asString()

private fun JsonElement.asString(): String? =
    runCatching { toString().trim('"') }.getOrNull()?.takeIf { it.isNotBlank() && it != "null" }
