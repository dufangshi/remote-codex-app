package com.remotecodex.app.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.Power
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.remotecodex.app.data.RelayDevice
import com.remotecodex.app.data.RelayGrant
import com.remotecodex.app.data.RelayShare
import com.remotecodex.app.theme.rcColors
import com.remotecodex.app.ui.components.IconButton
import com.remotecodex.app.ui.components.Mono
import com.remotecodex.app.ui.components.PrimaryButton
import com.remotecodex.app.ui.components.RcField
import com.remotecodex.app.ui.components.RcRadius
import com.remotecodex.app.ui.components.SecondaryButton
import com.remotecodex.app.ui.components.StatusDot
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun DeviceCard(
    device: RelayDevice,
    relayHttps: Boolean,
    copied: Boolean,
    copyError: String?,
    menuOpen: Boolean,
    onToggleMenu: () -> Unit,
    onConnect: () -> Unit,
    onCopyUnix: () -> Unit,
    onCopyWindows: () -> Unit,
    onShare: () -> Unit,
    onRotate: () -> Unit,
    onDelete: () -> Unit,
) {
    val colors = rcColors
    val hosted = device.hostedStatus
    val canConnect = device.connected || (hosted != null && hosted != "stopping" && hosted != "deleting")
    val canCopySetup = hosted == null
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 16.dp)
            .testTag("device-${device.id}"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StatusDot(device.connected)
            Spacer(Modifier.width(8.dp))
            Text(
                device.name,
                color = colors.fg,
                fontWeight = FontWeight.Medium,
                fontSize = 14.sp,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (hosted != null) {
                Text(
                    "Hosted: ${hostedStatusLabel(hosted)}",
                    color = colors.fgMuted,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(colors.muted)
                        .padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
        }
        Spacer(Modifier.height(4.dp))
        Mono(device.tokenPreview)
        Spacer(Modifier.height(6.dp))
        Text(deviceActivityText(device), color = colors.fgMuted, fontSize = 12.sp)
        Text(
            if (relayHttps) "Device connection uses HTTPS" else "Connection is not end-to-end encrypted",
            color = if (relayHttps) colors.successFg else colors.fgMuted,
            fontSize = 11.sp,
        )
        if (copied) {
            Text("Setup command copied.", color = colors.successFg, fontSize = 12.sp)
        }
        if (copyError != null) {
            Text(copyError, color = colors.dangerFg, fontSize = 12.sp)
        }
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            PrimaryButton(
                if (hosted == "stopped") "Start & connect" else "Connect",
                enabled = canConnect,
                modifier = Modifier.weight(1f),
                tag = "connectDeviceButton",
                leading = { Icon(Icons.Filled.Power, null, tint = rcColors.accentSolidFg, modifier = Modifier.size(16.dp)) },
                onClick = onConnect,
            )
            Box {
                val menuOffsetY = with(LocalDensity.current) { 44.dp.roundToPx() }
                IconButton("More actions for ${device.name}", onClick = onToggleMenu) {
                    Icon(Icons.Filled.MoreHoriz, null, tint = colors.fgMuted)
                }
                if (menuOpen) {
                    Popup(
                        alignment = Alignment.TopEnd,
                        offset = IntOffset(0, menuOffsetY),
                        onDismissRequest = onToggleMenu,
                        properties = PopupProperties(focusable = true),
                    ) {
                        Column(
                            Modifier
                                .width(256.dp)
                                .clip(RoundedCornerShape(8.dp))
                                .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                                .background(colors.panel)
                                .padding(4.dp),
                        ) {
                            DeviceMenuRow("Copy setup for macOS/Linux", enabled = canCopySetup, icon = Icons.Filled.ContentCopy, onClick = onCopyUnix)
                            DeviceMenuRow("Copy setup for Windows", enabled = canCopySetup, icon = Icons.Filled.ContentCopy, onClick = onCopyWindows)
                            DeviceMenuRow("Share device", icon = Icons.Filled.Share, onClick = onShare)
                            if (hosted == null) {
                                DeviceMenuRow("Replace device token", onClick = onRotate)
                            }
                            Box(Modifier.fillMaxWidth().padding(vertical = 4.dp).height(1.dp).background(colors.border))
                            DeviceMenuRow(
                                "Delete device",
                                enabled = hosted == null,
                                icon = Icons.Filled.Delete,
                                danger = true,
                                onClick = onDelete,
                            )
                        }
                    }
                }
            }
        }
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
}

@Composable
private fun DeviceMenuRow(
    label: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
    danger: Boolean = false,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
) {
    val colors = rcColors
    val fg = when {
        !enabled -> colors.fgMuted
        danger -> colors.dangerFg
        else -> colors.fg
    }
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RcRadius)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp)
            .testTag(label),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = fg, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(label, color = fg, fontSize = 14.sp)
    }
}

@Composable
fun SharedAccessTabs(
    tabs: List<Pair<String, Int>>,
    selected: Int,
    onSelect: (Int) -> Unit,
) {
    val colors = rcColors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .border(1.dp, colors.border, RoundedCornerShape(8.dp))
            .background(colors.surface)
            .padding(3.dp),
    ) {
        tabs.chunked(2).forEachIndexed { rowIndex, row ->
            Row(Modifier.fillMaxWidth()) {
                row.forEachIndexed { col, (label, count) ->
                    val index = rowIndex * 2 + col
                    val selectedTab = selected == index
                    Row(
                        Modifier
                            .weight(1f)
                            .clip(RcRadius)
                            .background(if (selectedTab) colors.panel else colors.surface)
                            .clickable { onSelect(index) }
                            .padding(horizontal = 10.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            label,
                            color = if (selectedTab) colors.fg else colors.fgMuted,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.weight(1f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            "$count",
                            color = colors.fgMuted,
                            fontSize = 11.sp,
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(colors.muted)
                                .padding(horizontal = 8.dp, vertical = 2.dp),
                        )
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SharedAccessCard(
    title: String,
    subtitle: String,
    username: String,
    incoming: Boolean,
    permissions: List<String>,
    lastAccessedAt: String?,
    events: List<Pair<String, String>>,
    expanded: Boolean,
    onOpen: () -> Unit,
    onEdit: (() -> Unit)? = null,
    onRevoke: (() -> Unit)? = null,
    onToggleHistory: (() -> Unit)? = null,
) {
    val colors = rcColors
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 18.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(4.dp))
                Text(subtitle, color = colors.fgMuted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Row(
                Modifier
                    .clip(RoundedCornerShape(9.dp))
                    .background(colors.accentSoft)
                    .clickable(onClick = onOpen)
                    .padding(horizontal = 10.dp, vertical = 8.dp)
                    .testTag("Open"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Open", color = colors.accentStrong, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                Spacer(Modifier.width(4.dp))
                Icon(Icons.AutoMirrored.Filled.OpenInNew, null, tint = colors.accentStrong, modifier = Modifier.size(15.dp))
            }
        }
        Spacer(Modifier.height(18.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(colors.muted),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(username.take(2).uppercase(), color = colors.fgSoft, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                }
                Spacer(Modifier.width(9.dp))
                Column {
                    Text(if (incoming) "Shared by" else "Shared with", color = colors.fgMuted, fontSize = 10.sp)
                    Text(username, color = colors.fg, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            if (!incoming) {
                Row {
                    if (onEdit != null) {
                        IconButton("Permissions", onClick = onEdit) {
                            Icon(Icons.Filled.Tune, null, tint = colors.fgMuted, modifier = Modifier.size(16.dp))
                        }
                    }
                    if (onToggleHistory != null) {
                        IconButton("Access history", onClick = onToggleHistory) {
                            Icon(Icons.Filled.History, null, tint = colors.fgMuted, modifier = Modifier.size(16.dp))
                        }
                    }
                    if (onRevoke != null) {
                        IconButton("Revoke", onClick = onRevoke) {
                            Icon(Icons.Filled.PersonRemove, null, tint = colors.dangerFg, modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        Row(verticalAlignment = Alignment.Top) {
            FlowRow(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                permissions.forEach { permission ->
                    Text(
                        permission,
                        color = colors.fgMuted,
                        fontSize = 10.sp,
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(colors.muted)
                            .padding(horizontal = 7.dp, vertical = 3.dp),
                    )
                }
            }
            if (!incoming) {
                Text(
                    lastAccessedAt?.let { "Visited ${formatRelayTime(it)}" } ?: "No visits yet",
                    color = colors.fgMuted,
                    fontSize = 10.sp,
                )
            }
        }
        if (!incoming && expanded) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(top = 16.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .border(1.dp, colors.border, RoundedCornerShape(10.dp))
                    .background(colors.surface)
                    .padding(12.dp),
            ) {
                Text("Recent access", color = colors.fg, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(8.dp))
                if (events.isEmpty()) {
                    Text("No access events yet.", color = colors.fgMuted, fontSize = 12.sp)
                } else {
                    events.take(8).forEach { (who, whenText) ->
                        Text("$who · $whenText", color = colors.fgMuted, fontSize = 12.sp, modifier = Modifier.padding(vertical = 2.dp))
                    }
                }
            }
        }
    }
}

@Composable
fun ShareDeviceDialog(
    deviceName: String,
    busy: Boolean,
    error: String?,
    onShare: (target: String, label: String, threadAccess: String, workspaceAccess: String, canCreate: Boolean) -> Unit,
    onClose: () -> Unit,
) {
    val colors = rcColors
    var target by remember { mutableStateOf("") }
    var label by remember { mutableStateOf("") }
    var threadAccess by remember { mutableStateOf("read") }
    var workspaceAccess by remember { mutableStateOf("read") }
    var canCreate by remember { mutableStateOf(false) }
    Box(
        Modifier
            .fillMaxSize()
            .background(colors.overlay)
            .clickable(onClick = onClose),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .padding(24.dp)
                .widthIn(max = 420.dp)
                .clip(RoundedCornerShape(8.dp))
                .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                .background(colors.panel)
                .clickable(enabled = false, onClick = {})
                .padding(20.dp),
        ) {
            Text("Share $deviceName", color = colors.fg, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            Text("Give another relay account access to this device and its workspaces.", color = colors.fgMuted, fontSize = 13.sp)
            Spacer(Modifier.height(12.dp))
            RcField("Relay account", target, { target = it }, placeholder = "username or email", tag = "shareTarget")
            Spacer(Modifier.height(10.dp))
            RcField("Label", label, { label = it }, placeholder = "Optional note shown in Shared devices by me", tag = "shareLabel")
            Spacer(Modifier.height(10.dp))
            AccessPicker("Thread access", threadAccess, listOf("read" to "View only", "control" to "Collaborator")) { threadAccess = it }
            Spacer(Modifier.height(8.dp))
            AccessPicker("Workspace access", workspaceAccess, listOf("none" to "No workspace", "read" to "Workspace read", "write" to "Workspace write")) { workspaceAccess = it }
            Spacer(Modifier.height(8.dp))
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RcRadius)
                    .clickable { canCreate = !canCreate }
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Can create new threads", color = colors.fgSoft, fontSize = 14.sp, modifier = Modifier.weight(1f))
                Text(if (canCreate) "On" else "Off", color = colors.fgMuted, fontSize = 13.sp)
            }
            if (error != null) {
                Spacer(Modifier.height(8.dp))
                Text(error, color = colors.dangerFg, fontSize = 13.sp)
            }
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                SecondaryButton("Cancel", modifier = Modifier.weight(1f), onClick = onClose)
                PrimaryButton(
                    if (busy) "Sharing..." else "Share device",
                    enabled = !busy && target.isNotBlank(),
                    modifier = Modifier.weight(1f),
                    leading = { Icon(Icons.Filled.Share, null, tint = rcColors.accentSolidFg, modifier = Modifier.size(16.dp)) },
                    onClick = { onShare(target.trim(), label.trim(), threadAccess, workspaceAccess, canCreate) },
                )
            }
        }
    }
}

@Composable
fun PermissionDialog(
    title: String,
    initialThread: String,
    initialWorkspace: String,
    initialCanCreate: Boolean,
    showCanCreate: Boolean,
    busy: Boolean,
    error: String?,
    onSave: (threadAccess: String, workspaceAccess: String, canCreate: Boolean) -> Unit,
    onClose: () -> Unit,
) {
    var threadAccess by remember { mutableStateOf(initialThread) }
    var workspaceAccess by remember { mutableStateOf(initialWorkspace) }
    var canCreate by remember { mutableStateOf(initialCanCreate) }
    val colors = rcColors
    Box(
        Modifier
            .fillMaxSize()
            .background(colors.overlay)
            .clickable(onClick = onClose),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .padding(24.dp)
                .widthIn(max = 420.dp)
                .clip(RoundedCornerShape(8.dp))
                .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                .background(colors.panel)
                .clickable(enabled = false, onClick = {})
                .padding(20.dp),
        ) {
            Text(title, color = colors.fg, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(12.dp))
            AccessPicker("Thread access", threadAccess, listOf("read" to "View only", "control" to "Collaborator")) { threadAccess = it }
            Spacer(Modifier.height(8.dp))
            AccessPicker("Workspace access", workspaceAccess, listOf("none" to "No workspace", "read" to "Workspace read", "write" to "Workspace write")) { workspaceAccess = it }
            if (showCanCreate) {
                Spacer(Modifier.height(8.dp))
                Row(
                    Modifier.fillMaxWidth().clickable { canCreate = !canCreate }.padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Can create new threads", color = colors.fgSoft, fontSize = 14.sp, modifier = Modifier.weight(1f))
                    Text(if (canCreate) "On" else "Off", color = colors.fgMuted, fontSize = 13.sp)
                }
            }
            if (error != null) {
                Spacer(Modifier.height(8.dp))
                Text(error, color = colors.dangerFg, fontSize = 13.sp)
            }
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                SecondaryButton("Cancel", modifier = Modifier.weight(1f), onClick = onClose)
                PrimaryButton(if (busy) "Saving..." else "Save", enabled = !busy, modifier = Modifier.weight(1f), onClick = {
                    onSave(threadAccess, workspaceAccess, canCreate)
                })
            }
        }
    }
}

@Composable
private fun AccessPicker(label: String, value: String, options: List<Pair<String, String>>, onChange: (String) -> Unit) {
    val colors = rcColors
    Column {
        Text(label, color = colors.fgSoft, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            options.forEach { (id, title) ->
                val selected = value == id
                Text(
                    title,
                    color = if (selected) colors.fg else colors.fgMuted,
                    fontSize = 12.sp,
                    modifier = Modifier
                        .clip(RcRadius)
                        .background(if (selected) colors.accentSoft else colors.surface)
                        .border(1.dp, if (selected) colors.accentBorder else colors.border, RcRadius)
                        .clickable { onChange(id) }
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                )
            }
        }
    }
}

@Composable
fun EmptyAccess(text: String) {
    val colors = rcColors
    Box(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .border(1.dp, colors.border, RoundedCornerShape(8.dp))
            .background(colors.panel)
            .padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = colors.fgMuted, fontSize = 14.sp)
    }
}

fun deviceActivityText(device: RelayDevice): String {
    val hosted = device.hostedStatus
    return when {
        hosted == "stopped" -> "Stopped. Connect to wake this VM."
        hosted != null && hosted != "online" -> "${hostedStatusLabel(hosted)}. The hosted supervisor is not ready yet."
        device.connected && !device.connectedAt.isNullOrBlank() -> "Online since ${formatRelayTime(device.connectedAt)}"
        device.connected -> "Online. Connected time unavailable."
        !device.lastHeartbeatAt.isNullOrBlank() -> "Last heartbeat ${formatRelayTime(device.lastHeartbeatAt)}"
        else -> "No heartbeat recorded."
    }
}

fun hostedStatusLabel(status: String): String =
    status.replace('_', ' ').replaceFirstChar { it.uppercase() }

fun formatRelayTime(value: String): String =
    runCatching {
        DateTimeFormatter.ofPattern("MMM d, h:mm a").withZone(ZoneId.systemDefault()).format(Instant.parse(value))
    }.getOrElse { value }

fun supervisorSetup(relayUrl: String, token: String, windows: Boolean): String {
    val ws = if (relayUrl.startsWith("https://")) "wss://${relayUrl.removePrefix("https://")}"
    else "ws://${relayUrl.removePrefix("http://")}"
    val port = if (windows) 45680 else 45679
    return if (windows) {
        """
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
${'$'}env:REMOTE_CODEX_RELAY_SERVER_URL='$ws'
${'$'}env:REMOTE_CODEX_RELAY_AGENT_TOKEN='$token'
${'$'}env:REMOTE_CODEX_RELAY_SUPERVISOR_PORT='$port'
remote-codex relay-supervisor
        """.trimIndent()
    } else {
        """
REMOTE_CODEX_RELAY_SERVER_URL=$ws \
REMOTE_CODEX_RELAY_AGENT_TOKEN=$token \
REMOTE_CODEX_RELAY_SUPERVISOR_PORT=$port \
remote-codex relay-supervisor
        """.trimIndent()
    }
}

fun copyText(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("Remote Codex", text))
}

fun permissionLabels(threadAccess: String?, workspaceAccess: String?, canCreate: Boolean = false): List<String> {
    val items = mutableListOf(if (threadAccess == "control") "Collaborator" else "View only")
    items += when (workspaceAccess) {
        "write" -> "Workspace write"
        "read" -> "Workspace read"
        else -> "No workspace"
    }
    if (canCreate) items += "Can create threads"
    return items
}

fun groupGrants(grants: List<RelayGrant>): List<Pair<String, List<RelayGrant>>> =
    grants.groupBy { it.deviceId }.map { (id, list) ->
        id to list.sortedWith(compareBy({ it.scope }, { it.workspaceLabel.orEmpty() }, { it.threadTitle.orEmpty() }))
    }

@Composable
fun SharedThreadList(
    shares: List<RelayShare>,
    incoming: Boolean,
    empty: String,
    expandedId: String?,
    onOpen: (RelayShare) -> Unit,
    onToggle: (RelayShare) -> Unit,
    onEdit: ((RelayShare) -> Unit)? = null,
    onRevoke: ((RelayShare) -> Unit)? = null,
) {
    if (shares.isEmpty()) {
        EmptyAccess(empty)
        return
    }
    val colors = rcColors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .border(1.dp, colors.border, RoundedCornerShape(8.dp))
            .background(colors.panel),
    ) {
        shares.forEachIndexed { index, share ->
            SharedAccessCard(
                title = share.threadTitle?.ifBlank { null } ?: "Thread",
                subtitle = listOfNotNull(share.workspaceLabel, share.deviceName).joinToString(" · "),
                username = if (incoming) share.ownerUsername else share.targetUsername,
                incoming = incoming,
                permissions = permissionLabels(share.threadAccess, share.workspaceAccess),
                lastAccessedAt = share.lastAccessedAt,
                events = share.accessEvents.map { "${it.username} ${it.kind}" to formatRelayTime(it.accessedAt) },
                expanded = expandedId == share.id,
                onOpen = { onOpen(share) },
                onEdit = onEdit?.let { { it(share) } },
                onRevoke = onRevoke?.let { { it(share) } },
                onToggleHistory = { onToggle(share) },
            )
            if (index != shares.lastIndex) {
                Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
            }
        }
    }
}

@Composable
fun SharedGrantList(
    groups: List<Pair<String, List<RelayGrant>>>,
    incoming: Boolean,
    empty: String,
    expandedId: String?,
    onOpen: (RelayGrant) -> Unit,
    onToggle: (RelayGrant) -> Unit,
    onEdit: ((RelayGrant) -> Unit)? = null,
    onRevoke: ((RelayGrant) -> Unit)? = null,
) {
    if (groups.isEmpty()) {
        EmptyAccess(empty)
        return
    }
    val colors = rcColors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .border(1.dp, colors.border, RoundedCornerShape(8.dp))
            .background(colors.panel),
    ) {
        groups.forEach { (_, grants) ->
            val first = grants.first()
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    first.deviceName.ifBlank { "Device" },
                    color = colors.fg,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "${grants.size} ${if (grants.size == 1) "share" else "shares"}",
                    color = colors.fgMuted,
                    fontSize = 11.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(colors.muted)
                        .padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
            grants.forEachIndexed { index, grant ->
                SharedAccessCard(
                    title = grant.label?.ifBlank { null }
                        ?: grant.threadTitle?.ifBlank { null }
                        ?: grant.workspaceLabel?.ifBlank { null }
                        ?: grant.deviceName.ifBlank { "Device" },
                    subtitle = listOfNotNull(
                        grant.scope.replaceFirstChar { it.uppercase() },
                        grant.workspaceLabel ?: grant.deviceName,
                    ).joinToString(" · "),
                    username = if (incoming) grant.ownerUsername else grant.targetUsername,
                    incoming = incoming,
                    permissions = permissionLabels(grant.threadAccess, grant.workspaceAccess, grant.canCreateThreads),
                    lastAccessedAt = grant.lastAccessedAt,
                    events = grant.accessEvents.map { "${it.username} ${it.kind}" to formatRelayTime(it.accessedAt) },
                    expanded = expandedId == grant.id,
                    onOpen = { onOpen(grant) },
                    onEdit = onEdit?.let { { it(grant) } },
                    onRevoke = onRevoke?.let { { it(grant) } },
                    onToggleHistory = { onToggle(grant) },
                )
                if (index != grants.lastIndex) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
        }
    }
}
