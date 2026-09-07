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
import kotlinx.serialization.json.Json
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.atomic.AtomicReference

class AgentEventService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private var watchJob: Job? = null
    private val socket = AtomicReference<WebSocket?>(null)

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
        socket.getAndSet(null)?.cancel()
        super.onDestroy()
    }

    private fun startWatching() {
        watchJob?.cancel()
        watchJob = scope.launch {
            val store = SessionStore(this@AgentEventService)
            val api = ApiClient(store)
            while (isActive) {
                val deviceId = store.deviceId
                val token = store.token
                if (deviceId.isBlank() || token.isBlank() || store.relayUrl.isBlank()) {
                    delay(2_000)
                    continue
                }
                pollThreads(api, store, deviceId)
                connect(api, store, deviceId)
                delay(2_500)
            }
        }
    }

    private val knownStatus = mutableMapOf<String, String>()
    private val notified = mutableSetOf<String>()
    private var primed = false
    private var primedDevice: String? = null

    private suspend fun pollThreads(api: ApiClient, store: SessionStore, deviceId: String) {
        if (primedDevice != deviceId) {
            primed = false
            knownStatus.clear()
            notified.clear()
            primedDevice = deviceId
        }
        val threads = runCatching { api.fetchThreads(deviceId) }.getOrDefault(emptyList())
        if (!primed) {
            threads.forEach {
                knownStatus[it.id] = it.status
                notified.add(it.id)
            }
            primed = true
            return
        }
        for (thread in threads) {
            val previous = knownStatus[thread.id]
            knownStatus[thread.id] = thread.status
            val finished = thread.status in setOf("idle", "failed", "interrupted", "system_error")
            if (finished && !notified.contains(thread.id) && (previous == "running" || previous == null)) {
                notified.add(thread.id)
                val current = ActiveThreadTracker.current
                if (current?.deviceId == deviceId && current.threadId == thread.id && RemoteCodexForeground.isForeground) {
                    continue
                }
                val failed = thread.status == "failed"
                Notifications.agentFinished(
                    this,
                    deviceId,
                    thread.id,
                    thread.title.ifBlank { "Thread" },
                    if (failed) "Agent run failed." else "Agent run finished.",
                    thread.id.hashCode(),
                )
            }
        }
    }

    private fun connect(api: ApiClient, store: SessionStore, deviceId: String) {
        val latch = java.util.concurrent.CountDownLatch(1)
        val titles = mutableMapOf<String, String>()
        val ws = api.openDeviceSocket(
            deviceId,
            object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    val event = runCatching { json.decodeFromString<ThreadEvent>(text) }.getOrNull() ?: return
                    if (event.type == "thread.updated") {
                        event.title()?.let { titles[event.threadId] = it }
                    }
                    val completed = event.type == "thread.turn.completed" ||
                        event.type == "thread.turn.failed" ||
                        (event.type == "thread.updated" &&
                            event.status() in setOf("idle", "failed", "interrupted", "system_error"))
                    if (!completed) return
                    val current = ActiveThreadTracker.current
                    val appForeground = RemoteCodexForeground.isForeground
                    if (current?.deviceId == deviceId && current.threadId == event.threadId && appForeground) {
                        return
                    }
                    val failed = event.type == "thread.turn.failed" || event.status() == "failed"
                    val title = titles[event.threadId] ?: "Thread"
                    val body = if (failed) {
                        event.error()?.takeIf { it.isNotBlank() } ?: "Agent run failed."
                    } else {
                        "Agent run finished."
                    }
                    Notifications.agentFinished(
                        this@AgentEventService,
                        deviceId,
                        event.threadId,
                        title,
                        body,
                        event.threadId.hashCode(),
                    )
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    latch.countDown()
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    latch.countDown()
                }
            },
        )
        socket.getAndSet(ws)?.cancel()
        latch.await()
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
