package com.remotecodex.app.notify

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.remotecodex.app.data.ApiClient
import com.remotecodex.app.data.SessionStore
import com.remotecodex.app.data.ThreadEvent
import com.remotecodex.app.data.error
import com.remotecodex.app.data.status
import com.remotecodex.app.data.title
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.resume

class AgentEventService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private var watchJob: Job? = null
    private val socketJobs = ConcurrentHashMap<String, Job>()
    private val sockets = ConcurrentHashMap<String, WebSocket>()
    private val knownStatus = mutableMapOf<String, String>()
    private val recentlyNotified = mutableMapOf<String, Long>()
    private val primedDevices = mutableSetOf<String>()
    private val titles = mutableMapOf<String, String>()
    private val deviceNames = mutableMapOf<String, String>()
    private val lock = Any()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannel(this)
        val notification = Notifications.watchNotification(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(Notifications.WATCH_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(Notifications.WATCH_ID, notification)
        }
        startWatching()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_REFRESH) {
            startWatching()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        watchJob?.cancel()
        socketJobs.values.forEach { it.cancel() }
        socketJobs.clear()
        sockets.values.forEach { it.cancel() }
        sockets.clear()
        super.onDestroy()
    }

    private fun startWatching() {
        watchJob?.cancel()
        watchJob = scope.launch {
            val store = SessionStore(this@AgentEventService)
            val api = ApiClient(store)
            while (isActive) {
                if (store.token.isBlank() || store.relayUrl.isBlank()) {
                    delay(2_000)
                    continue
                }
                val deviceIds = loadDeviceIds(api)
                syncSockets(api, deviceIds)
                for (deviceId in deviceIds) {
                    pollDevice(api, deviceId)
                }
                delay(4_000)
            }
        }
    }

    private suspend fun loadDeviceIds(api: ApiClient): List<String> {
        val portal = runCatching { api.fetchPortal() }.getOrNull() ?: return emptyList()
        val ids = LinkedHashSet<String>()
        synchronized(lock) {
            for (device in portal.devices) {
                ids.add(device.id)
                deviceNames[device.id] = device.name
            }
            for (grant in portal.sharedDevicesWithMe) {
                if (ids.add(grant.deviceId)) {
                    deviceNames[grant.deviceId] = grant.deviceName.ifBlank { grant.deviceId }
                }
            }
        }
        return ids.toList()
    }

    private fun syncSockets(api: ApiClient, deviceIds: List<String>) {
        val wanted = deviceIds.toSet()
        val extra = socketJobs.keys - wanted
        for (id in extra) {
            socketJobs.remove(id)?.cancel()
            sockets.remove(id)?.cancel()
        }
        for (deviceId in deviceIds) {
            val existing = socketJobs[deviceId]
            if (existing?.isActive == true) continue
            socketJobs[deviceId] = scope.launch {
                while (isActive) {
                    connectOnce(api, deviceId)
                    delay(2_500)
                }
            }
        }
    }

    private suspend fun pollDevice(api: ApiClient, deviceId: String) {
        val threads = runCatching { api.fetchThreads(deviceId) }.getOrNull() ?: return
        val firstSeen = synchronized(lock) { primedDevices.add(deviceId) }
        if (firstSeen) {
            synchronized(lock) {
                for (thread in threads) {
                    val key = key(deviceId, thread.id)
                    knownStatus[key] = thread.status
                    if (thread.title.isNotBlank()) titles[key] = thread.title
                }
            }
            return
        }
        for (thread in threads) {
            consider(
                deviceId = deviceId,
                threadId = thread.id,
                status = thread.status,
                title = thread.title,
                completedAt = thread.lastTurnCompletedAt ?: thread.updatedAt,
                eventType = null,
            )
        }
    }

    private suspend fun connectOnce(api: ApiClient, deviceId: String) {
        suspendCancellableCoroutine { cont ->
            val ws = api.openDeviceSocket(
                deviceId,
                object : WebSocketListener() {
                    override fun onMessage(webSocket: WebSocket, text: String) {
                        handleEvent(deviceId, text)
                    }

                    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                        if (cont.isActive) cont.resume(Unit)
                    }

                    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                        if (cont.isActive) cont.resume(Unit)
                    }
                },
            )
            sockets[deviceId] = ws
            cont.invokeOnCancellation { ws.cancel() }
        }
    }

    private fun handleEvent(deviceId: String, text: String) {
        val event = runCatching { json.decodeFromString<ThreadEvent>(text) }.getOrNull() ?: return
        consider(
            deviceId = deviceId,
            threadId = event.threadId,
            status = event.status(),
            title = event.title(),
            completedAt = null,
            eventType = event.type,
        )
    }

    private fun consider(
        deviceId: String,
        threadId: String,
        status: String?,
        title: String?,
        completedAt: String?,
        eventType: String?,
    ) {
        val key = key(deviceId, threadId)
        val turnDone = eventType == "thread.turn.completed" || eventType == "thread.turn.failed"
        val failed = eventType == "thread.turn.failed" || status == "failed"
        val finishedStatuses = setOf("idle", "failed", "interrupted", "system_error")
        val running = status == "running"
        val previous: String?
        val resolvedTitle: String
        val deviceName: String?
        synchronized(lock) {
            if (!title.isNullOrBlank()) titles[key] = title
            previous = knownStatus[key]
            if (running) {
                knownStatus[key] = "running"
                return
            }
            val finished = turnDone || (status != null && status in finishedStatuses)
            if (!finished) {
                if (status != null) knownStatus[key] = status
                return
            }
            knownStatus[key] = if (failed) "failed" else status?.takeIf { it in finishedStatuses } ?: "idle"
            resolvedTitle = titles[key] ?: "Thread"
            deviceName = deviceNames[deviceId]
        }
        val wasRunning = previous == "running"
        val appearedFinished = previous == null && eventType == null && isRecent(completedAt)
        if (!turnDone && !wasRunning && !appearedFinished) return
        if (isDuplicate(key)) return
        val current = ActiveThreadTracker.current
        if (current?.deviceId == deviceId && current.threadId == threadId && RemoteCodexForeground.isForeground) {
            return
        }
        val prefix = deviceName?.takeIf { it.isNotBlank() }?.let { "$it · " } ?: ""
        val body = if (failed) "${prefix}Agent run failed." else "${prefix}Agent run finished."
        Notifications.agentFinished(
            this,
            deviceId,
            threadId,
            resolvedTitle,
            body,
            (deviceId + threadId + System.currentTimeMillis()).hashCode(),
        )
    }

    private fun isDuplicate(key: String): Boolean {
        val now = System.currentTimeMillis()
        synchronized(lock) {
            val last = recentlyNotified[key]
            if (last != null && now - last < 10_000) return true
            recentlyNotified[key] = now
            return false
        }
    }

    private fun isRecent(value: String?): Boolean {
        if (value.isNullOrBlank()) return false
        val instant = runCatching { Instant.parse(value) }.getOrNull() ?: return false
        return Instant.now().epochSecond - instant.epochSecond < 30
    }

    companion object {
        const val ACTION_REFRESH = "com.remotecodex.app.REFRESH_WATCH"

        fun start(context: Context) {
            val intent = Intent(context, AgentEventService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun refresh(context: Context) {
            val intent = Intent(context, AgentEventService::class.java).setAction(ACTION_REFRESH)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AgentEventService::class.java))
        }

        fun key(deviceId: String, threadId: String) = "$deviceId/$threadId"
    }
}

data class OpenThreadRef(val deviceId: String, val threadId: String)

object ActiveThreadTracker {
    @Volatile
    var current: OpenThreadRef? = null
}

object RemoteCodexForeground {
    @Volatile
    var isForeground: Boolean = false
}
