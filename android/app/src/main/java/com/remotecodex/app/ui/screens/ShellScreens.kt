package com.remotecodex.app.ui.screens

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FolderCopy
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Power
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.remotecodex.app.data.ApiClient
import com.remotecodex.app.data.AuthenticatorEnrollment
import com.remotecodex.app.data.RelayDevice
import com.remotecodex.app.data.SecurityStatus
import com.remotecodex.app.data.RelayPortal
import com.remotecodex.app.data.RelaySession
import com.remotecodex.app.data.RelayGrant
import com.remotecodex.app.data.RelayShare
import com.remotecodex.app.data.RuntimeConfig
import com.remotecodex.app.data.SessionStore
import com.remotecodex.app.data.ThreadSummary
import com.remotecodex.app.data.Workspace
import com.remotecodex.app.theme.ThemeMode
import com.remotecodex.app.theme.rcColors
import com.remotecodex.app.ui.components.BrandMark
import com.remotecodex.app.ui.components.ConfirmDialog
import com.remotecodex.app.ui.components.FloatingPanel
import com.remotecodex.app.ui.components.IconButton
import com.remotecodex.app.ui.components.MenuItem
import com.remotecodex.app.ui.components.MenuSheet
import com.remotecodex.app.ui.components.Mono
import com.remotecodex.app.ui.components.Notice
import com.remotecodex.app.ui.components.NoticeTone
import com.remotecodex.app.ui.components.PrimaryButton
import com.remotecodex.app.ui.components.ProductHeader
import com.remotecodex.app.ui.components.PromptDialog
import com.remotecodex.app.ui.components.RcField
import com.remotecodex.app.ui.components.RcPage
import com.remotecodex.app.ui.components.RcRadius
import com.remotecodex.app.ui.components.SecondaryButton
import com.remotecodex.app.ui.components.StatusDot
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun DevicesScreen(
    store: SessionStore,
    api: ApiClient,
    session: RelaySession?,
    onBack: () -> Unit,
    onOpenNav: () -> Unit,
    onOpenAccount: () -> Unit,
    onConnectDevice: (RelayDevice) -> Unit,
    onOpenSharedThread: (deviceId: String, threadId: String, workspaceId: String?) -> Unit,
    onOpenSharedDevice: (deviceId: String) -> Unit,
) {
    val colors = rcColors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var portal by remember { mutableStateOf<RelayPortal?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var addOpen by remember { mutableStateOf(false) }
    var deviceName by remember { mutableStateOf("") }
    var createdToken by remember { mutableStateOf<Pair<String, String>?>(null) }
    var deleting by remember { mutableStateOf<RelayDevice?>(null) }
    var rotating by remember { mutableStateOf<RelayDevice?>(null) }
    var sharing by remember { mutableStateOf<RelayDevice?>(null) }
    var editingGrant by remember { mutableStateOf<RelayGrant?>(null) }
    var editingShare by remember { mutableStateOf<RelayShare?>(null) }
    var revokingGrant by remember { mutableStateOf<RelayGrant?>(null) }
    var revokingShare by remember { mutableStateOf<RelayShare?>(null) }
    var expandedId by remember { mutableStateOf<String?>(null) }
    var menuId by remember { mutableStateOf<String?>(null) }
    var copiedDeviceId by remember { mutableStateOf<String?>(null) }
    var copyError by remember { mutableStateOf<Pair<String, String>?>(null) }
    var dialogError by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var sharedTab by remember { mutableStateOf(0) }

    fun load(show: Boolean = true) {
        if (show) loading = true
        scope.launch {
            runCatching { api.fetchPortal() }
                .onSuccess { portal = it; error = null }
                .onFailure { if (show || portal == null) error = it.message ?: "Unable to load devices." }
            loading = false
        }
    }

    LaunchedEffect(store.token) {
        load()
        while (true) {
            delay(3_000)
            load(show = false)
        }
    }

    Box(Modifier.fillMaxSize()) {
        RcPage {
            ProductHeader(
                title = "Devices",
                backLabel = "Relay home",
                onBack = onBack,
                onOpenNav = onOpenNav,
                onOpenAccount = onOpenAccount,
                accountLabel = session?.user?.username,
            )
            Column(Modifier.padding(20.dp)) {
                Text("Devices and shared sessions", color = colors.fg, fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(16.dp))
                Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
                Spacer(Modifier.height(16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Devices", color = colors.fg, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                        Text("Your relay supervisors and their current availability.", color = colors.fgMuted, fontSize = 13.sp)
                    }
                    SecondaryButton(
                        if (addOpen) "Close" else "Add device",
                        onClick = { addOpen = !addOpen },
                        tag = "addDeviceButton",
                        leading = {
                            Icon(if (addOpen) Icons.Filled.Close else Icons.Filled.Add, null, tint = colors.fg, modifier = Modifier.size(16.dp))
                        },
                    )
                }
                if (error != null) {
                    Spacer(Modifier.height(12.dp))
                    Notice(error!!)
                }
                if (addOpen) {
                    Spacer(Modifier.height(12.dp))
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                            .background(colors.panel)
                            .padding(16.dp),
                    ) {
                        RcField("Device name", deviceName, { deviceName = it }, tag = "deviceNameField")
                        Spacer(Modifier.height(12.dp))
                        PrimaryButton("Create device", enabled = !busy && deviceName.isNotBlank(), tag = "createDeviceButton") {
                            busy = true
                            scope.launch {
                                runCatching { api.createDevice(deviceName.trim()) }
                                    .onSuccess {
                                        createdToken = it.device.name to it.token
                                        deviceName = ""
                                        addOpen = false
                                        load(false)
                                    }
                                    .onFailure { error = it.message }
                                busy = false
                            }
                        }
                    }
                }
                createdToken?.let { (name, token) ->
                    Spacer(Modifier.height(12.dp))
                    Notice("Device “$name” created. Copy the one-time token now; it will not be shown again.\n$token", NoticeTone.Accent)
                }
                Spacer(Modifier.height(16.dp))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                        .background(colors.panel)
                        .testTag("deviceList"),
                ) {
                    if (loading && portal == null) {
                        Text("Loading devices...", color = colors.fgMuted, modifier = Modifier.padding(16.dp))
                    } else {
                        val devices = portal?.devices.orEmpty()
                        if (devices.isEmpty()) {
                            Text(
                                "No devices yet. Add a device to create its one-time supervisor token.",
                                color = colors.fgMuted,
                                modifier = Modifier.padding(24.dp).fillMaxWidth(),
                            )
                        } else {
                            devices.forEach { device ->
                                DeviceCard(
                                    device = device,
                                    relayHttps = store.relayUrl.startsWith("https://"),
                                    copied = copiedDeviceId == device.id,
                                    copyError = copyError?.takeIf { it.first == device.id }?.second,
                                    menuOpen = menuId == device.id,
                                    onToggleMenu = { menuId = if (menuId == device.id) null else device.id },
                                    onConnect = { onConnectDevice(device) },
                                    onCopyUnix = {
                                        menuId = null
                                        scope.launch {
                                            runCatching { api.fetchSetupToken(device.id) }
                                                .onSuccess {
                                                    copyText(context, supervisorSetup(store.relayUrl, it.token, windows = false))
                                                    copiedDeviceId = device.id
                                                    copyError = null
                                                }
                                                .onFailure {
                                                    copyError = device.id to (it.message ?: "Unable to copy the setup command.")
                                                    copiedDeviceId = null
                                                }
                                        }
                                    },
                                    onCopyWindows = {
                                        menuId = null
                                        scope.launch {
                                            runCatching { api.fetchSetupToken(device.id) }
                                                .onSuccess {
                                                    copyText(context, supervisorSetup(store.relayUrl, it.token, windows = true))
                                                    copiedDeviceId = device.id
                                                    copyError = null
                                                }
                                                .onFailure {
                                                    copyError = device.id to (it.message ?: "Unable to copy the setup command.")
                                                    copiedDeviceId = null
                                                }
                                        }
                                    },
                                    onShare = { menuId = null; dialogError = null; sharing = device },
                                    onRotate = { menuId = null; rotating = device },
                                    onDelete = { menuId = null; deleting = device },
                                )
                            }
                        }
                    }
                }
                Spacer(Modifier.height(28.dp))
                Text("Shared access", color = colors.fg, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                Text("Access you received and access you granted.", color = colors.fgMuted, fontSize = 13.sp)
                Spacer(Modifier.height(12.dp))
                val incomingDevices = groupGrants(portal?.sharedDevicesWithMe.orEmpty())
                val outgoingDevices = groupGrants(portal?.grantsByMe.orEmpty())
                val tabs = listOf(
                    "Threads with me" to (portal?.sharedWithMe?.size ?: 0),
                    "Devices with me" to incomingDevices.size,
                    "Devices by me" to outgoingDevices.size,
                    "Threads by me" to (portal?.sharedByMe?.size ?: 0),
                )
                SharedAccessTabs(tabs, sharedTab) { sharedTab = it }
                Spacer(Modifier.height(12.dp))
                when (sharedTab) {
                    0 -> SharedThreadList(
                        shares = portal?.sharedWithMe.orEmpty(),
                        incoming = true,
                        empty = "No sessions have been shared with this account yet.",
                        expandedId = expandedId,
                        onOpen = { onOpenSharedThread(it.deviceId, it.threadId, it.workspaceId) },
                        onToggle = { expandedId = if (expandedId == it.id) null else it.id },
                    )
                    1 -> SharedGrantList(
                        groups = incomingDevices,
                        incoming = true,
                        empty = "No devices have been shared with this account yet.",
                        expandedId = expandedId,
                        onOpen = { onOpenSharedDevice(it.deviceId) },
                        onToggle = { expandedId = if (expandedId == it.id) null else it.id },
                    )
                    2 -> SharedGrantList(
                        groups = outgoingDevices,
                        incoming = false,
                        empty = "No devices have been shared by this account yet.",
                        expandedId = expandedId,
                        onOpen = { onOpenSharedDevice(it.deviceId) },
                        onToggle = { expandedId = if (expandedId == it.id) null else it.id },
                        onEdit = { editingGrant = it },
                        onRevoke = { revokingGrant = it },
                    )
                    else -> SharedThreadList(
                        shares = portal?.sharedByMe.orEmpty(),
                        incoming = false,
                        empty = "No threads have been shared by this account yet.",
                        expandedId = expandedId,
                        onOpen = { onOpenSharedThread(it.deviceId, it.threadId, it.workspaceId) },
                        onToggle = { expandedId = if (expandedId == it.id) null else it.id },
                        onEdit = { editingShare = it },
                        onRevoke = { revokingShare = it },
                    )
                }
            }
        }
        deleting?.let { device ->
            ConfirmDialog(
                title = "Delete relay device",
                description = "Delete ${device.name}? Its device token will stop working immediately. This cannot be undone.",
                confirmLabel = "Delete device",
                busy = busy,
                onCancel = { deleting = null },
                onConfirm = {
                    busy = true
                    scope.launch {
                        runCatching { api.deleteDevice(device.id) }
                            .onSuccess { deleting = null; load(false) }
                            .onFailure { error = it.message }
                        busy = false
                    }
                },
            )
        }
        rotating?.let { device ->
            ConfirmDialog(
                title = "Replace device token?",
                description = "The current connection will close. Update the device setup with the new token to reconnect. Existing workspaces and threads are kept.",
                confirmLabel = "Replace token",
                busy = busy,
                onCancel = { rotating = null },
                onConfirm = {
                    busy = true
                    scope.launch {
                        runCatching { api.rotateDeviceToken(device.id) }
                            .onSuccess {
                                createdToken = it.device.name to it.token
                                rotating = null
                                load(false)
                            }
                            .onFailure { error = it.message }
                        busy = false
                    }
                },
            )
        }
        sharing?.let { device ->
            ShareDeviceDialog(
                deviceName = device.name,
                busy = busy,
                error = dialogError,
                onClose = { sharing = null; dialogError = null },
                onShare = { target, label, threadAccess, workspaceAccess, canCreate ->
                    busy = true
                    dialogError = null
                    scope.launch {
                        runCatching {
                            api.createGrant(device.id, target, label, threadAccess, workspaceAccess, canCreate)
                        }.onSuccess {
                            sharing = null
                            load(false)
                        }.onFailure { dialogError = it.message }
                        busy = false
                    }
                },
            )
        }
        editingGrant?.let { grant ->
            PermissionDialog(
                title = "Permissions",
                initialThread = grant.threadAccess,
                initialWorkspace = grant.workspaceAccess,
                initialCanCreate = grant.canCreateThreads,
                showCanCreate = true,
                busy = busy,
                error = dialogError,
                onClose = { editingGrant = null; dialogError = null },
                onSave = { threadAccess, workspaceAccess, canCreate ->
                    busy = true
                    scope.launch {
                        runCatching { api.updateGrant(grant.id, threadAccess, workspaceAccess, canCreate, grant.label) }
                            .onSuccess { editingGrant = null; load(false) }
                            .onFailure { dialogError = it.message }
                        busy = false
                    }
                },
            )
        }
        editingShare?.let { share ->
            PermissionDialog(
                title = "Permissions",
                initialThread = share.threadAccess,
                initialWorkspace = share.workspaceAccess,
                initialCanCreate = false,
                showCanCreate = false,
                busy = busy,
                error = dialogError,
                onClose = { editingShare = null; dialogError = null },
                onSave = { threadAccess, workspaceAccess, _ ->
                    busy = true
                    scope.launch {
                        runCatching { api.updateShare(share.id, threadAccess, workspaceAccess, share.label) }
                            .onSuccess { editingShare = null; load(false) }
                            .onFailure { dialogError = it.message }
                        busy = false
                    }
                },
            )
        }
        revokingGrant?.let { grant ->
            ConfirmDialog(
                title = "Revoke shared device access",
                description = "Revoke access for ${grant.targetUsername.ifBlank { "this user" }} on ${grant.deviceName.ifBlank { "this device" }}?",
                confirmLabel = "Revoke",
                busy = busy,
                onCancel = { revokingGrant = null },
                onConfirm = {
                    busy = true
                    scope.launch {
                        runCatching { api.revokeGrant(grant.id) }
                            .onSuccess { revokingGrant = null; load(false) }
                            .onFailure { error = it.message }
                        busy = false
                    }
                },
            )
        }
        revokingShare?.let { share ->
            ConfirmDialog(
                title = "Revoke shared thread access",
                description = "Revoke access for ${share.targetUsername.ifBlank { "this user" }} on ${share.threadTitle ?: "this thread"}?",
                confirmLabel = "Revoke",
                busy = busy,
                onCancel = { revokingShare = null },
                onConfirm = {
                    busy = true
                    scope.launch {
                        runCatching { api.revokeShare(share.id) }
                            .onSuccess { revokingShare = null; load(false) }
                            .onFailure { error = it.message }
                        busy = false
                    }
                },
            )
        }
    }
}

@Composable
fun WorkspacesScreen(
    store: SessionStore,
    api: ApiClient,
    deviceId: String,
    session: RelaySession?,
    onBack: () -> Unit,
    onOpenNav: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenWorkspace: (Workspace) -> Unit,
    onNewWorkspace: () -> Unit,
    onImport: () -> Unit,
) {
    val colors = rcColors
    val scope = rememberCoroutineScope()
    var workspaces by remember { mutableStateOf<List<Workspace>>(emptyList()) }
    var runtime by remember { mutableStateOf<RuntimeConfig?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var runtimeError by remember { mutableStateOf<String?>(null) }
    var renaming by remember { mutableStateOf<Workspace?>(null) }
    var renameValue by remember { mutableStateOf("") }
    var deleting by remember { mutableStateOf<Workspace?>(null) }
    var menuId by remember { mutableStateOf<String?>(null) }

    fun load() {
        loading = true
        scope.launch {
            val ws = runCatching { api.fetchWorkspaces(deviceId) }
            val rt = runCatching { api.fetchRuntime(deviceId) }
            ws.onSuccess { workspaces = it.sortedWith(compareByDescending<Workspace> { it.isFavorite }.thenByDescending { it.lastOpenedAt ?: it.createdAt }) }
                .onFailure { error = it.message }
            rt.onSuccess { runtime = it; runtimeError = null }
                .onFailure { runtimeError = it.message }
            loading = false
        }
    }

    LaunchedEffect(deviceId) { load() }

    Box(Modifier.fillMaxSize()) {
        RcPage {
            ProductHeader(
                title = "Workspaces",
                backLabel = "Back to devices",
                onBack = onBack,
                onOpenNav = onOpenNav,
                onOpenAccount = onOpenAccount,
                accountLabel = session?.user?.username,
                actions = {
                    IconButton("Import session", onImport) {
                        Icon(Icons.Filled.FileDownload, null, tint = colors.fgMuted, modifier = Modifier.size(18.dp))
                    }
                    IconButton("Add workspace", onNewWorkspace) {
                        Box(
                            Modifier
                                .size(36.dp)
                                .clip(RcRadius)
                                .background(colors.accentSolid),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Filled.Add, null, tint = colors.accentSolidFg, modifier = Modifier.size(18.dp))
                        }
                    }
                },
            )
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                StatusDot(runtime != null && runtimeError == null)
                Spacer(Modifier.width(8.dp))
                Text("Supervisor", color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                Spacer(Modifier.width(8.dp))
                Mono(runtime?.workspaceRoot ?: runtimeError ?: "Checking runtime...", Modifier.weight(1f))
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
            if (error != null) {
                Notice(error!!, modifier = Modifier.padding(16.dp))
            }
            if (!loading && workspaces.isEmpty() && error == null) {
                Column(
                    Modifier.fillMaxWidth().padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("No workspaces yet", color = colors.fg, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    Text("Add a folder on this device, connect an existing path, or clone a Git repository.", color = colors.fgMuted, fontSize = 14.sp)
                    Spacer(Modifier.height(16.dp))
                    PrimaryButton("Add workspace", tag = "emptyAddWorkspace", onClick = onNewWorkspace)
                }
            }
            Column(
                Modifier
                    .padding(16.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                    .background(colors.panel)
                    .testTag("workspaceList"),
            ) {
                workspaces.forEach { workspace ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable { onOpenWorkspace(workspace) }
                            .padding(start = 16.dp, end = 8.dp, top = 14.dp, bottom = 14.dp)
                            .testTag("workspace-${workspace.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(workspace.label, color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Mono(workspace.absPath)
                            Text(lastOpenedLabel(workspace.lastOpenedAt), color = colors.fgMuted, fontSize = 12.sp)
                        }
                        IconButton(
                            if (workspace.isFavorite) "Unpin ${workspace.label}" else "Pin ${workspace.label}",
                            onClick = {
                                scope.launch {
                                    runCatching { api.favoriteWorkspace(deviceId, workspace.id, !workspace.isFavorite) }
                                        .onSuccess { updated ->
                                            workspaces = workspaces.map { if (it.id == updated.id) updated else it }
                                        }
                                }
                            },
                        ) {
                            Icon(
                                Icons.Filled.PushPin,
                                null,
                                tint = if (workspace.isFavorite) colors.warningFg else colors.fgMuted,
                                modifier = Modifier.size(16.dp).rotate(if (workspace.isFavorite) 18f else 8f),
                            )
                        }
                        IconButton("Workspace actions", onClick = { menuId = if (menuId == workspace.id) null else workspace.id }) {
                            Icon(Icons.Filled.MoreHoriz, null, tint = colors.fgMuted)
                        }
                    }
                    if (menuId == workspace.id) {
                        Column(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) {
                            MenuItem("Rename", onClick = { renaming = workspace; renameValue = workspace.label; menuId = null })
                            MenuItem("Delete", onClick = { deleting = workspace; menuId = null })
                        }
                    }
                    Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
                }
            }
        }
        renaming?.let { workspace ->
            PromptDialog(
                title = "Rename workspace",
                label = "Label",
                value = renameValue,
                onValueChange = { renameValue = it },
                onCancel = { renaming = null },
                onSubmit = {
                    scope.launch {
                        runCatching { api.renameWorkspace(deviceId, workspace.id, renameValue.trim()) }
                            .onSuccess { updated ->
                                workspaces = workspaces.map { if (it.id == updated.id) updated else it }
                                renaming = null
                            }
                    }
                },
            )
        }
        deleting?.let { workspace ->
            ConfirmDialog(
                title = "Delete workspace",
                description = "Delete ${workspace.label}? Threads in this workspace will also be removed from the supervisor list.",
                confirmLabel = "Delete workspace",
                onCancel = { deleting = null },
                onConfirm = {
                    scope.launch {
                        runCatching { api.deleteWorkspace(deviceId, workspace) }
                            .onSuccess {
                                workspaces = workspaces.filter { it.id != workspace.id }
                                deleting = null
                            }
                    }
                },
            )
        }
    }
}

@Composable
fun ThreadsScreen(
    api: ApiClient,
    deviceId: String,
    workspaceId: String,
    session: RelaySession?,
    onBack: () -> Unit,
    onOpenNav: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenThread: (ThreadSummary) -> Unit,
    onNewThread: () -> Unit,
) {
    val colors = rcColors
    val scope = rememberCoroutineScope()
    var threads by remember { mutableStateOf<List<ThreadSummary>>(emptyList()) }
    var workspaces by remember { mutableStateOf<List<Workspace>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var renaming by remember { mutableStateOf<ThreadSummary?>(null) }
    var renameValue by remember { mutableStateOf("") }
    var deleting by remember { mutableStateOf<ThreadSummary?>(null) }

    fun load() {
        loading = true
        scope.launch {
            val result = runCatching {
                Pair(api.fetchThreads(deviceId), api.fetchWorkspaces(deviceId))
            }
            result.onSuccess { (t, w) ->
                threads = t.filter { it.workspaceId == workspaceId }
                workspaces = w
                error = null
            }.onFailure { error = it.message }
            loading = false
        }
    }

    LaunchedEffect(deviceId, workspaceId) { load() }

    val workspace = workspaces.find { it.id == workspaceId }
    Box(Modifier.fillMaxSize()) {
        RcPage {
            ProductHeader(
                title = workspace?.label ?: "Workspace",
                backLabel = "Back to workspaces",
                onBack = onBack,
                onOpenNav = onOpenNav,
                onOpenAccount = onOpenAccount,
                accountLabel = session?.user?.username,
                actions = {
                    IconButton("New thread", onNewThread) {
                        Box(
                            Modifier.size(36.dp).clip(RcRadius).background(colors.accentSolid),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Filled.Add, null, tint = colors.accentSolidFg, modifier = Modifier.size(18.dp))
                        }
                    }
                },
            )
            if (error != null) Notice(error!!, modifier = Modifier.padding(16.dp))
            if (loading) Text("Loading threads…", color = colors.fgMuted, modifier = Modifier.padding(16.dp))
            val running = threads.count { it.status == "running" }
            Column(Modifier.padding(16.dp)) {
                if (!loading && threads.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Recent Threads", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                        Spacer(Modifier.width(8.dp))
                        Text("${threads.size} total", color = colors.fgMuted, fontSize = 12.sp)
                        if (running > 0) {
                            Spacer(Modifier.width(8.dp))
                            Text("$running running", color = colors.fgMuted, fontSize = 12.sp)
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }
                if (!loading && threads.isEmpty() && error == null) {
                    Text("No threads available in this workspace.", color = colors.fgMuted, fontSize = 14.sp)
                }
                threads.forEach { thread ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .border(1.dp, colors.border, RoundedCornerShape(12.dp))
                            .background(colors.panel)
                            .clickable { onOpenThread(thread) }
                            .padding(16.dp)
                            .testTag("thread-${thread.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            Modifier
                                .size(36.dp)
                                .clip(RoundedCornerShape(8.dp))
                                .background(colors.hover),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Filled.FolderCopy, null, tint = colors.fgMuted, modifier = Modifier.size(18.dp))
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(thread.title, color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Row {
                                Text(formatStamp(thread.updatedAt), color = colors.fgMuted, fontSize = 12.sp)
                                if (thread.status != "idle") {
                                    Spacer(Modifier.width(8.dp))
                                    Text(thread.status, color = colors.fgMuted, fontSize = 12.sp)
                                }
                            }
                        }
                        IconButton("Rename thread ${thread.title}", onClick = { renaming = thread; renameValue = thread.title }) {
                            Text("✎", color = colors.fgMuted)
                        }
                        IconButton("Delete thread ${thread.title}", onClick = { deleting = thread }) {
                            Icon(Icons.Filled.Delete, null, tint = colors.fgMuted, modifier = Modifier.size(16.dp))
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }
            }
        }
        renaming?.let { thread ->
            PromptDialog(
                title = "Rename Thread",
                label = "Thread Title",
                value = renameValue,
                onValueChange = { renameValue = it },
                onCancel = { renaming = null },
                onSubmit = {
                    scope.launch {
                        runCatching { api.renameThread(deviceId, thread.id, renameValue.trim()) }
                            .onSuccess { updated ->
                                threads = threads.map { if (it.id == updated.id) updated else it }
                                renaming = null
                            }
                    }
                },
            )
        }
        deleting?.let { thread ->
            ConfirmDialog(
                title = "Delete Thread",
                description = "Delete ${thread.title} from supervisor. The backend session id will no longer appear in this workspace list.",
                confirmLabel = "Delete Thread",
                onCancel = { deleting = null },
                onConfirm = {
                    scope.launch {
                        runCatching { api.deleteThread(deviceId, thread.id) }
                            .onSuccess {
                                threads = threads.filter { it.id != thread.id }
                                deleting = null
                            }
                    }
                },
            )
        }
    }
}

private fun lastOpenedLabel(value: String?): String {
    if (value.isNullOrBlank()) return "Not opened yet"
    return "Opened ${formatStamp(value)}"
}

private fun formatStamp(value: String): String {
    return runCatching {
        val instant = Instant.parse(value)
        DateTimeFormatter.ofPattern("MMM d, h:mm a").withZone(ZoneId.systemDefault()).format(instant)
    }.getOrElse { value }
}

@Composable
fun WorkspaceNewScreen(
    api: ApiClient,
    deviceId: String,
    onBack: () -> Unit,
    onCreated: (Workspace) -> Unit,
) {
    val colors = rcColors
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf("folder") }
    var value by remember { mutableStateOf("") }
    var label by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var devHome by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(deviceId) {
        runCatching { api.fetchWorkspaceSettings(deviceId) }.onSuccess { devHome = it.devHome }
    }
    val field = when (mode) {
        "git" -> Triple("Repository URL", "https://github.com/owner/repo.git", "Clone repository")
        "path" -> Triple("Absolute path", "/Users/name/project", "Add workspace")
        else -> Triple("Folder name", "my-project", "Create folder")
    }
    FloatingPanel(
        eyebrow = "Workspaces",
        title = "Add a workspace",
        description = "Choose a folder, existing path, or Git repository.",
        backLabel = "Back to workspaces",
        onBack = onBack,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("folder" to "New folder", "path" to "Existing path", "git" to "Git repository").forEach { (id, title) ->
                val selected = mode == id
                Box(
                    Modifier
                        .clip(RcRadius)
                        .border(1.dp, if (selected) colors.accentBorder else colors.border, RcRadius)
                        .background(if (selected) colors.accentSoft else colors.surface)
                        .clickable { mode = id }
                        .padding(horizontal = 12.dp, vertical = 10.dp)
                        .testTag("workspaceMode-$id"),
                ) {
                    Text(title, color = colors.fg, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        RcField(field.first, value, { value = it; error = null }, placeholder = field.second, tag = "workspaceValue")
        Spacer(Modifier.height(12.dp))
        RcField("Label (optional)", label, { label = it }, tag = "workspaceLabel")
        if (error != null) {
            Spacer(Modifier.height(12.dp))
            Notice(error!!)
        }
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SecondaryButton("Cancel", onClick = onBack)
            PrimaryButton(if (busy) "Working..." else field.third, enabled = !busy && value.isNotBlank(), tag = "createWorkspaceButton") {
                busy = true
                scope.launch {
                    val payload = buildJsonObject {
                        if (label.isNotBlank()) put("label", label.trim())
                        if (mode == "git") put("gitUrl", value.trim())
                        else {
                            val abs = if (mode == "folder" && !devHome.isNullOrBlank()) {
                                devHome!!.trimEnd('/', '\\') + "/" + value.trim()
                            } else value.trim()
                            put("absPath", abs)
                        }
                    }
                    runCatching { api.createWorkspace(deviceId, payload) }
                        .onSuccess(onCreated)
                        .onFailure { error = it.message }
                    busy = false
                }
            }
        }
    }
}

@Composable
fun ThreadNewScreen(
    api: ApiClient,
    deviceId: String,
    workspaceId: String?,
    onBack: () -> Unit,
    onCreated: (ThreadSummary) -> Unit,
) {
    val colors = rcColors
    val scope = rememberCoroutineScope()
    var workspaces by remember { mutableStateOf<List<Workspace>>(emptyList()) }
    var backends by remember { mutableStateOf<List<com.remotecodex.app.data.AgentBackend>>(emptyList()) }
    var models by remember { mutableStateOf<List<com.remotecodex.app.data.ModelOption>>(emptyList()) }
    var selectedWorkspace by remember { mutableStateOf(workspaceId.orEmpty()) }
    var provider by remember { mutableStateOf("codex") }
    var model by remember { mutableStateOf("") }
    var title by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(deviceId) {
        loading = true
        runCatching {
            val w = api.fetchWorkspaces(deviceId)
            val b = api.fetchBackends(deviceId)
            workspaces = w
            backends = b
            if (selectedWorkspace.isBlank()) selectedWorkspace = w.firstOrNull()?.id.orEmpty()
            val chosen = b.firstOrNull { it.enabled }?.provider ?: "codex"
            provider = chosen
            val m = api.fetchModels(deviceId, chosen)
            models = m
            model = m.firstOrNull { it.isDefault }?.model ?: m.firstOrNull()?.model.orEmpty()
        }.onFailure { error = it.message }
        loading = false
    }

    FloatingPanel(
        eyebrow = "New Thread",
        title = "Start a backend session",
        description = "Choose a workspace, backend, and model.",
        backLabel = if (workspaceId != null) "Back to threads" else "Back to workspaces",
        onBack = onBack,
    ) {
        if (loading) {
            Text("Loading creation form...", color = colors.fgMuted)
            return@FloatingPanel
        }
        RcField("Title (optional)", title, { title = it }, tag = "threadTitleField")
        Spacer(Modifier.height(12.dp))
        Text("Workspace", color = colors.fgSoft, fontSize = 14.sp)
        Spacer(Modifier.height(8.dp))
        workspaces.forEach { workspace ->
            val selected = workspace.id == selectedWorkspace
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RcRadius)
                    .border(1.dp, if (selected) colors.accentBorder else colors.border, RcRadius)
                    .background(if (selected) colors.accentSoft else colors.surface)
                    .clickable { selectedWorkspace = workspace.id }
                    .padding(12.dp)
                    .testTag("pickWorkspace-${workspace.id}"),
            ) {
                Text(workspace.label, color = colors.fg, fontSize = 14.sp)
            }
            Spacer(Modifier.height(6.dp))
        }
        Spacer(Modifier.height(8.dp))
        Text("Backend", color = colors.fgSoft, fontSize = 14.sp)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            backends.forEach { backend ->
                val selected = backend.provider == provider
                Box(
                    Modifier
                        .clip(RcRadius)
                        .border(1.dp, if (selected) colors.accentBorder else colors.border, RcRadius)
                        .background(if (selected) colors.accentSoft else colors.surface)
                        .clickable {
                            provider = backend.provider
                            scope.launch {
                                runCatching { api.fetchModels(deviceId, backend.provider) }
                                    .onSuccess {
                                        models = it
                                        model = it.firstOrNull { option -> option.isDefault }?.model ?: it.firstOrNull()?.model.orEmpty()
                                    }
                            }
                        }
                        .padding(10.dp)
                        .testTag("provider-${backend.provider}"),
                ) {
                    Text(backend.displayName.ifBlank { backend.provider }, color = colors.fg, fontSize = 13.sp)
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Text("Model", color = colors.fgSoft, fontSize = 14.sp)
        Spacer(Modifier.height(8.dp))
        models.forEach { option ->
            val selected = option.model == model
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RcRadius)
                    .border(1.dp, if (selected) colors.accentBorder else colors.border, RcRadius)
                    .clickable { model = option.model }
                    .padding(10.dp)
                    .testTag("model-${option.model}"),
            ) {
                Text(option.displayName.ifBlank { option.model }, color = colors.fg, fontSize = 13.sp)
            }
            Spacer(Modifier.height(4.dp))
        }
        if (error != null) {
            Spacer(Modifier.height(12.dp))
            Notice(error!!)
        }
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SecondaryButton("Cancel", onClick = onBack)
            PrimaryButton("Start thread", enabled = !busy && selectedWorkspace.isNotBlank() && model.isNotBlank(), tag = "startThreadButton") {
                busy = true
                scope.launch {
                    runCatching {
                        api.createThread(
                            deviceId = deviceId,
                            workspaceId = selectedWorkspace,
                            title = title.ifBlank { null },
                            provider = provider,
                            model = model,
                        )
                    }.onSuccess(onCreated).onFailure { error = it.message }
                    busy = false
                }
            }
        }
    }
}

@Composable
fun ImportScreen(
    api: ApiClient,
    deviceId: String,
    onBack: () -> Unit,
    onImported: (String) -> Unit,
) {
    val colors = rcColors
    val scope = rememberCoroutineScope()
    var sessionId by remember { mutableStateOf("") }
    var provider by remember { mutableStateOf("codex") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    RcPage {
        ProductHeader(title = "Import threads", backLabel = "Back to workspaces", onBack = onBack)
        Column(Modifier.padding(20.dp)) {
            RcField("Session id", sessionId, { sessionId = it; error = null }, tag = "importSessionId")
            Spacer(Modifier.height(12.dp))
            RcField("Provider", provider, { provider = it }, tag = "importProvider")
            if (error != null) {
                Spacer(Modifier.height(12.dp))
                Notice(error!!)
            }
            Spacer(Modifier.height(16.dp))
            PrimaryButton("Import session", enabled = !busy && sessionId.isNotBlank(), tag = "importButton") {
                busy = true
                scope.launch {
                    runCatching { api.importThread(deviceId, sessionId.trim(), provider, null) }
                        .onSuccess { payload ->
                            val id = payload["thread"]?.toString()
                                ?.let { runCatching { kotlinx.serialization.json.Json.parseToJsonElement(it) }.getOrNull() }
                            val threadId = payload["id"]?.toString()?.trim('"')
                                ?: Regex("\"id\"\\s*:\\s*\"([^\"]+)\"").find(payload.toString())?.groupValues?.getOrNull(1)
                            if (threadId != null) onImported(threadId) else error = "Imported, but thread id was missing."
                        }
                        .onFailure { error = it.message }
                    busy = false
                }
            }
        }
    }
}

@Composable
fun AccountScreen(
    api: ApiClient,
    onBack: () -> Unit,
) {
    val colors = rcColors
    val scope = rememberCoroutineScope()
    var session by remember { mutableStateOf<RelaySession?>(null) }
    var username by remember { mutableStateOf("") }
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var profileMessage by remember { mutableStateOf<String?>(null) }
    var profileError by remember { mutableStateOf<String?>(null) }
    var passwordMessage by remember { mutableStateOf<String?>(null) }
    var passwordError by remember { mutableStateOf<String?>(null) }
    var savingProfile by remember { mutableStateOf(false) }
    var savingPassword by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        runCatching { api.fetchSession() }.onSuccess {
            session = it
            username = it.user?.username.orEmpty()
        }
        loading = false
    }

    RcPage {
        ProductHeader(title = "Account settings", backLabel = "Devices", onBack = onBack)
        if (loading) {
            Text("Loading account...", color = colors.fgMuted, modifier = Modifier.padding(20.dp))
            return@RcPage
        }
        Column(Modifier.padding(20.dp)) {
            Text("Profile", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Text("Your relay identity.", color = colors.fgMuted, fontSize = 13.sp)
            Spacer(Modifier.height(12.dp))
            Text("Email", color = colors.fgSoft, fontSize = 14.sp)
            Text(session?.user?.email.orEmpty(), color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
            Spacer(Modifier.height(12.dp))
            RcField("Username", username, { username = it; profileError = null; profileMessage = null }, tag = "accountUsername")
            if (profileError != null) Notice(profileError!!)
            if (profileMessage != null) Notice(profileMessage!!, NoticeTone.Success)
            Spacer(Modifier.height(12.dp))
            PrimaryButton("Save profile", enabled = !savingProfile && username.trim() != session?.user?.username, tag = "saveProfile") {
                savingProfile = true
                scope.launch {
                    runCatching { api.updateAccount(username.trim()) }
                        .onSuccess { profileMessage = "Profile saved."; session = session?.copy(user = it) }
                        .onFailure { profileError = it.message }
                    savingProfile = false
                }
            }
            Spacer(Modifier.height(28.dp))
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
            Spacer(Modifier.height(20.dp))
            Text("Password", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Text("Use at least 8 characters.", color = colors.fgMuted, fontSize = 13.sp)
            Spacer(Modifier.height(12.dp))
            RcField("Current password", currentPassword, { currentPassword = it }, password = true, tag = "currentPassword")
            Spacer(Modifier.height(12.dp))
            RcField("New password", newPassword, { newPassword = it }, password = true, tag = "newPassword")
            Spacer(Modifier.height(12.dp))
            RcField("Confirm new password", confirmPassword, { confirmPassword = it }, password = true, tag = "confirmPassword")
            if (passwordError != null) {
                Spacer(Modifier.height(12.dp))
                Notice(passwordError!!)
            }
            if (passwordMessage != null) {
                Spacer(Modifier.height(12.dp))
                Notice(passwordMessage!!, NoticeTone.Success)
            }
            Spacer(Modifier.height(12.dp))
            PrimaryButton("Change password", enabled = !savingPassword, tag = "changePassword") {
                if (newPassword != confirmPassword) {
                    passwordError = "New passwords do not match."
                    return@PrimaryButton
                }
                savingPassword = true
                scope.launch {
                    runCatching { api.updatePassword(currentPassword, newPassword) }
                        .onSuccess {
                            passwordMessage = "Password changed."
                            currentPassword = ""; newPassword = ""; confirmPassword = ""
                        }
                        .onFailure { passwordError = it.message }
                    savingPassword = false
                }
            }
            Spacer(Modifier.height(28.dp))
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
            Spacer(Modifier.height(20.dp))
            Text("Security", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Text("Protect your account and devices.", color = colors.fgMuted, fontSize = 13.sp)
            Spacer(Modifier.height(12.dp))
            AccountSecurityPanel(api = api)
        }
    }
}

@Composable
private fun AccountSecurityPanel(api: ApiClient) {
    val colors = rcColors
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<SecurityStatus?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var enrollment by remember { mutableStateOf<AuthenticatorEnrollment?>(null) }
    var code by remember { mutableStateOf("") }
    var recovery by remember { mutableStateOf<List<String>?>(null) }
    var busy by remember { mutableStateOf(false) }
    fun refresh() {
        scope.launch {
            runCatching { api.fetchSecurity() }
                .onSuccess { status = it; error = null }
                .onFailure { error = it.message }
        }
    }
    LaunchedEffect(Unit) { refresh() }
    if (error != null) Notice(error!!)
    val current = status
    if (current == null && error == null) {
        Text("Loading security settings…", color = colors.fgMuted, fontSize = 14.sp)
        return
    }
    if (current != null) {
        Text("Authenticator app", color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
        Text("Google Authenticator and compatible apps.", color = colors.fgMuted, fontSize = 13.sp)
        Spacer(Modifier.height(8.dp))
        SecondaryButton(if (current.authenticatorEnabled) "Disable" else "Set up", enabled = !busy) {
            busy = true
            scope.launch {
                if (current.authenticatorEnabled) {
                    runCatching { api.disableAuthenticator() }.onSuccess { refresh() }.onFailure { error = it.message }
                } else {
                    runCatching { api.enrollAuthenticator() }.onSuccess { enrollment = it }.onFailure { error = it.message }
                }
                busy = false
            }
        }
        enrollment?.let { enroll ->
            Spacer(Modifier.height(12.dp))
            Text("Scan this code in your authenticator, then enter its six-digit code.", color = colors.fgMuted, fontSize = 13.sp)
            Text(enroll.secret, color = colors.fg, fontFamily = FontFamily.Monospace, fontSize = 13.sp)
            Spacer(Modifier.height(8.dp))
            RcField("Setup verification code", code, { code = it }, tag = "authenticatorSetupCode")
            Spacer(Modifier.height(8.dp))
            PrimaryButton("Enable authenticator", enabled = !busy && code.length == 6) {
                busy = true
                scope.launch {
                    runCatching { api.confirmAuthenticator(code) }
                        .onSuccess {
                            recovery = it.recoveryCodes
                            enrollment = null
                            code = ""
                            refresh()
                        }
                        .onFailure { error = it.message }
                    busy = false
                }
            }
        }
        recovery?.let { codes ->
            Spacer(Modifier.height(12.dp))
            Text("Recovery codes", color = colors.fg, fontWeight = FontWeight.Medium)
            codes.forEach { Text(it, fontFamily = FontFamily.Monospace, color = colors.fg, fontSize = 13.sp) }
        }
        Spacer(Modifier.height(16.dp))
        Text("Sessions", color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
        current.sessions.forEach { session ->
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(session.name.ifBlank { "Session" }, color = colors.fg, fontSize = 14.sp)
                    if (session.current) Text("Current session", color = colors.successFg, fontSize = 12.sp)
                }
                if (!session.current) {
                    Text("Revoke", color = colors.dangerFg, fontSize = 13.sp, modifier = Modifier.clickable {
                        scope.launch { runCatching { api.revokeSecuritySession(session.id) }.onSuccess { refresh() } }
                    })
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Text("Trusted browsers", color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
        if (current.trustedBrowsers.isEmpty()) {
            Text("No trusted browsers.", color = colors.fgMuted, fontSize = 13.sp)
        }
        current.trustedBrowsers.forEach { browser ->
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(browser.name.ifBlank { "Browser" }, color = colors.fg, fontSize = 14.sp, modifier = Modifier.weight(1f))
                Text("Revoke", color = colors.dangerFg, fontSize = 13.sp, modifier = Modifier.clickable {
                    scope.launch { runCatching { api.revokeTrustedBrowser(browser.id) }.onSuccess { refresh() } }
                })
            }
        }
    }
}

@Composable
fun SettingsSheet(
    themeMode: ThemeMode,
    autoCollapseCompletedTurns: Boolean,
    onThemeMode: (ThemeMode) -> Unit,
    onAutoCollapse: (Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = rcColors
    Box(
        Modifier
            .fillMaxSize()
            .background(colors.overlay)
            .clickable(onClick = onDismiss),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .padding(24.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                .background(colors.panel)
                .clickable(enabled = false) {}
                .padding(20.dp)
                .testTag("settingsDialog"),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Settings", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, modifier = Modifier.weight(1f))
                IconButton("Close settings", onDismiss) {
                    Icon(Icons.Filled.Close, null, tint = colors.fgMuted)
                }
            }
            Spacer(Modifier.height(12.dp))
            Text("Completed turns", color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
            Spacer(Modifier.height(8.dp))
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RcRadius)
                    .border(1.dp, if (autoCollapseCompletedTurns) colors.accentBorder else colors.border, RcRadius)
                    .background(if (autoCollapseCompletedTurns) colors.accentSoft else colors.surface)
                    .clickable { onAutoCollapse(!autoCollapseCompletedTurns) }
                    .padding(12.dp)
                    .testTag("autoCollapseCompletedTurns"),
            ) {
                Text("Auto-collapse completed turns", color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                Text(
                    if (autoCollapseCompletedTurns) "Completed turns collapse after they finish."
                    else "Completed turns stay expanded.",
                    color = colors.fgMuted,
                    fontSize = 12.sp,
                )
            }
            Spacer(Modifier.height(16.dp))
            Text("Appearance", color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
            Spacer(Modifier.height(8.dp))
            listOf(
                ThemeMode.Light to ("Light" to "Always use the bright theme."),
                ThemeMode.Dark to ("Dark" to "Always use the dark theme."),
                ThemeMode.System to ("System" to "Follow the operating system appearance."),
            ).forEach { (mode, copy) ->
                val selected = themeMode == mode
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RcRadius)
                        .border(1.dp, if (selected) colors.accentBorder else colors.border, RcRadius)
                        .background(if (selected) colors.accentSoft else colors.surface)
                        .clickable { onThemeMode(mode) }
                        .padding(12.dp)
                        .testTag("theme-${mode.name.lowercase()}"),
                ) {
                    Text(copy.first, color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                    Text(copy.second, color = colors.fgMuted, fontSize = 12.sp)
                }
                Spacer(Modifier.height(8.dp))
            }
        }
    }
}

@Composable
fun AccountMenu(
    session: RelaySession?,
    onAccount: () -> Unit,
    onLogout: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = rcColors
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().clickable(onClick = onDismiss))
        Column(
            Modifier
                .align(Alignment.TopEnd)
                .padding(top = 64.dp, end = 12.dp)
                .width(256.dp)
                .clip(RoundedCornerShape(8.dp))
                .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                .background(colors.panel)
                .padding(6.dp)
                .testTag("accountMenu"),
        ) {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                Text(session?.user?.username.orEmpty(), color = colors.fg, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                Text(session?.user?.email.orEmpty(), color = colors.fgMuted, fontSize = 12.sp)
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
            MenuItem("Account settings", onClick = onAccount, leading = {
                Icon(Icons.Filled.Settings, null, tint = colors.fgMuted, modifier = Modifier.size(16.dp))
            })
            MenuItem("Log out", onClick = onLogout, leading = {
                Icon(Icons.Filled.Logout, null, tint = colors.dangerFg, modifier = Modifier.size(16.dp))
            })
        }
    }
}

@Composable
fun NavMenu(
    devicesSelected: Boolean,
    onDevices: () -> Unit,
    onSettings: () -> Unit,
    onDismiss: () -> Unit,
) {
    MenuSheet("Remote Codex", "Supervisor controls", onDismiss) {
        MenuItem("Device management", selected = devicesSelected, onClick = onDevices, leading = {
            Icon(Icons.Filled.Smartphone, null, tint = rcColors.fgMuted, modifier = Modifier.size(16.dp))
        })
        MenuItem("Settings", onClick = onSettings, leading = {
            Icon(Icons.Filled.Settings, null, tint = rcColors.fgMuted, modifier = Modifier.size(16.dp))
        })
    }
}
