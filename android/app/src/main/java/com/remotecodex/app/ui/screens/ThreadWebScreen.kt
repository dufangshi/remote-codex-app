package com.remotecodex.app.ui.screens

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.remotecodex.app.data.ApiClient
import com.remotecodex.app.data.SessionStore
import com.remotecodex.app.notify.ActiveThreadTracker
import com.remotecodex.app.notify.OpenThreadRef
import com.remotecodex.app.theme.ThemeMode
import com.remotecodex.app.theme.rcColors
import com.remotecodex.app.ui.AppRoute

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun ThreadWebScreen(
    store: SessionStore,
    api: ApiClient,
    deviceId: String,
    threadId: String,
    themeMode: ThemeMode,
    onLeaveThread: (AppRoute) -> Unit,
) {
    val colors = rcColors
    var error by remember { mutableStateOf<String?>(null) }
    DisposableEffect(deviceId, threadId) {
        ActiveThreadTracker.current = OpenThreadRef(deviceId, threadId)
        onDispose {
            if (ActiveThreadTracker.current?.threadId == threadId) {
                ActiveThreadTracker.current = null
            }
        }
    }
    Box(
        Modifier
            .fillMaxSize()
            .background(colors.appBg)
            .testTag("threadWebView"),
    ) {
        key(deviceId, threadId, store.relayUrl) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { context ->
                    WebView(context).apply {
                        layoutParams = ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT,
                        )
                        setBackgroundColor(colors.appBg.toArgb())
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.databaseEnabled = true
                        settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                        settings.cacheMode = WebSettings.LOAD_DEFAULT
                        CookieManager.getInstance().setAcceptCookie(true)
                        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                        webChromeClient = WebChromeClient()
                        webViewClient = ThreadLeaveClient(
                            deviceId = deviceId,
                            threadId = threadId,
                            onLeaveThread = onLeaveThread,
                            onError = { error = it },
                            inject = { view -> injectSession(view, store, deviceId, themeMode) },
                        )
                        installDocumentStartScript(this, store, deviceId, themeMode)
                        loadThreadPage(this, store, deviceId, threadId)
                    }
                },
                update = { /* Recreated by key() when the thread target changes. */ },
            )
        }
        if (error != null) {
            Text(
                error!!,
                color = colors.dangerFg,
                fontSize = 14.sp,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(16.dp),
            )
        }
    }
}

fun nativeRouteForWebPath(deviceId: String, path: String, query: String?): AppRoute? {
    val threads = Regex("^/devices/([^/]+)/threads/?$").find(path)
        ?: Regex("^/threads/?$").find(path)
    if (threads != null) {
        val id = threads.groupValues.getOrNull(1) ?: deviceId
        val workspaceId = query?.split("&")?.firstOrNull { it.startsWith("workspaceId=") }?.substringAfter("=")
        return if (!workspaceId.isNullOrBlank()) AppRoute.Threads(id, java.net.URLDecoder.decode(workspaceId, "UTF-8"))
        else AppRoute.Workspaces(id)
    }
    val thread = Regex("^/devices/([^/]+)/threads/([^/]+)/?$").find(path)
        ?: Regex("^/threads/([^/]+)/?$").find(path)
    if (thread != null) {
        val values = thread.groupValues
        return if (values.size >= 3) AppRoute.ThreadDetail(values[1], values[2])
        else AppRoute.ThreadDetail(deviceId, values[1])
    }
    val newThread = Regex("^/devices/([^/]+)/threads/new/?$").find(path)
        ?: Regex("^/threads/new/?$").find(path)
    if (newThread != null) {
        val id = newThread.groupValues.getOrNull(1) ?: deviceId
        val workspaceId = query?.split("&")?.firstOrNull { it.startsWith("workspaceId=") }?.substringAfter("=")
        return AppRoute.ThreadNew(id, workspaceId)
    }
    if (path.endsWith("/workspaces") || path == "/workspaces") {
        val id = Regex("^/devices/([^/]+)/workspaces").find(path)?.groupValues?.getOrNull(1) ?: deviceId
        return AppRoute.Workspaces(id)
    }
    if (path == "/relay-devices") return AppRoute.Devices
    if (path == "/relay-account") return AppRoute.Account
    if (path == "/" || path == "/relay-portal") return AppRoute.Home
    return null
}

private class ThreadLeaveClient(
    private val deviceId: String,
    private val threadId: String,
    private val onLeaveThread: (AppRoute) -> Unit,
    private val onError: (String) -> Unit,
    private val inject: (WebView) -> Unit,
) : WebViewClient() {
    private var sawThreadPath = false

    override fun shouldOverrideUrlLoading(
        view: WebView,
        request: WebResourceRequest,
    ): Boolean {
        if (!request.isForMainFrame) return false
        return leaveIfNative(request.url.toString())
    }

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
        markThreadPath(url)
        inject(view)
    }

    override fun onPageFinished(view: WebView, url: String) {
        markThreadPath(url)
        inject(view)
    }

    override fun onReceivedError(
        view: WebView,
        request: WebResourceRequest,
        errorResult: android.webkit.WebResourceError,
    ) {
        if (request.isForMainFrame) {
            onError(errorResult.description?.toString() ?: "Unable to load thread.")
        }
    }

    private fun markThreadPath(url: String?) {
        val path = android.net.Uri.parse(url ?: return).path.orEmpty()
        if (isThreadDocumentPath(path)) {
            sawThreadPath = true
        }
    }

    private fun leaveIfNative(url: String?): Boolean {
        val uri = android.net.Uri.parse(url ?: return false)
        val path = uri.path.orEmpty()
        markThreadPath(url)
        // Bootstrap and RelayGate redirects land on `/` or `/relay-portal`. Mapping
        // those to native Home pops the WebView (black screen → Choose a device).
        if (!sawThreadPath || path.isEmpty() || path == "/" || path == "/relay-portal") {
            return false
        }
        val leave = nativeRouteForWebPath(deviceId, path, uri.query) ?: return false
        if (leave is AppRoute.ThreadDetail && leave.threadId == threadId) {
            return false
        }
        onLeaveThread(leave)
        return true
    }
}

private fun isThreadDocumentPath(path: String): Boolean {
    val match = Regex("^/devices/[^/]+/threads/([^/]+)/?$").find(path)
        ?: Regex("^/threads/([^/]+)/?$").find(path)
        ?: return false
    val id = match.groupValues.last()
    return id.isNotBlank() && id != "new" && id != "import"
}

private fun threadPageUrl(origin: String, deviceId: String, threadId: String): String {
    val device = java.net.URLEncoder.encode(deviceId, "UTF-8")
    val thread = java.net.URLEncoder.encode(threadId, "UTF-8")
    return "${origin.trimEnd('/')}/devices/$device/threads/$thread?nativeApp=1&relay=1"
}

private fun loadThreadPage(
    view: WebView,
    store: SessionStore,
    deviceId: String,
    threadId: String,
) {
    val origin = store.relayUrl.trimEnd('/')
    val target = threadPageUrl(origin, deviceId, threadId)
    val manager = CookieManager.getInstance()
    manager.setAcceptCookie(true)
    manager.setAcceptThirdPartyCookies(view, true)
    val started = java.util.concurrent.atomic.AtomicBoolean(false)
    fun start() {
        if (!started.compareAndSet(false, true)) return
        view.post { view.loadUrl(target) }
    }
    val cookie = relaySessionCookie(origin, store.token)
    if (cookie != null) {
        manager.setCookie("$origin/", cookie) { _ ->
            manager.flush()
            start()
        }
        view.postDelayed({ start() }, 750)
    } else {
        start()
    }
}

private fun relaySessionCookie(origin: String, token: String): String? {
    if (token.isBlank()) return null
    val secure = if (origin.startsWith("https", ignoreCase = true)) "; Secure" else ""
    return "remote_codex_relay_session=$token; Path=/; HttpOnly; SameSite=Lax$secure"
}

private fun installDocumentStartScript(
    view: WebView,
    store: SessionStore,
    deviceId: String,
    themeMode: ThemeMode,
) {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
        return
    }
    val origin = store.relayUrl.trimEnd('/')
    WebViewCompat.addDocumentStartJavaScript(
        view,
        sessionScript(store, deviceId, themeMode),
        setOf(origin),
    )
}

private fun injectSession(view: WebView, store: SessionStore, deviceId: String, themeMode: ThemeMode) {
    view.evaluateJavascript(sessionScript(store, deviceId, themeMode), null)
}

private fun sessionScript(store: SessionStore, deviceId: String, themeMode: ThemeMode): String {
    val theme = when (themeMode) {
        ThemeMode.Light -> "light"
        ThemeMode.Dark -> "dark"
        ThemeMode.System -> "system"
    }
    return """
        (function () {
          window.__REMOTE_CODEX_BOOTSTRAP__ = Object.assign(
            { mode: 'relay', relayApiBase: '/relay' },
            window.__REMOTE_CODEX_BOOTSTRAP__ || {}
          );
          try {
            localStorage.setItem('remote-codex-relay-mode', 'true');
            localStorage.removeItem('remote-codex-relay-token');
            localStorage.setItem('remote-codex-relay-device-id', ${jsString(deviceId)});
            localStorage.setItem('remote-codex-theme-mode', ${jsString(theme)});
            localStorage.setItem('remote-codex-auto-collapse-completed-turns', ${jsString(if (store.autoCollapseCompletedTurns) "true" else "false")});
          } catch (e) {}
        })();
    """.trimIndent()
}

private fun jsString(value: String): String =
    buildString {
        append('"')
        value.forEach { ch ->
            when (ch) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                else -> append(ch)
            }
        }
        append('"')
    }
