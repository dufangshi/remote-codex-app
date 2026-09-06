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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
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
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                WebView(context).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.databaseEnabled = true
                    settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                    settings.cacheMode = WebSettings.LOAD_DEFAULT
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    webChromeClient = WebChromeClient()
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView,
                            request: WebResourceRequest,
                        ): Boolean {
                            val uri = request.url
                            val path = uri.path.orEmpty()
                            val leave = nativeRouteForWebPath(deviceId, path, uri.query)
                            if (leave != null && leave !is AppRoute.ThreadDetail) {
                                onLeaveThread(leave)
                                return true
                            }
                            if (leave is AppRoute.ThreadDetail && leave.threadId != threadId) {
                                onLeaveThread(leave)
                                return true
                            }
                            return false
                        }

                        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                            injectSession(view, store, deviceId, themeMode)
                        }

                        override fun onPageFinished(view: WebView, url: String) {
                            injectSession(view, store, deviceId, themeMode)
                            val path = android.net.Uri.parse(url).path.orEmpty()
                            val leave = nativeRouteForWebPath(deviceId, path, android.net.Uri.parse(url).query)
                            if (leave != null && leave !is AppRoute.ThreadDetail) {
                                onLeaveThread(leave)
                            }
                        }

                        override fun onReceivedError(
                            view: WebView,
                            request: WebResourceRequest,
                            errorResult: android.webkit.WebResourceError,
                        ) {
                            if (request.isForMainFrame) {
                                error = errorResult.description?.toString() ?: "Unable to load thread."
                            }
                        }
                    }
                    val bootstrap = bootstrapHtml(
                        origin = store.relayUrl,
                        token = store.token,
                        deviceId = deviceId,
                        threadId = threadId,
                        theme = when (themeMode) {
                            ThemeMode.Light -> "light"
                            ThemeMode.Dark -> "dark"
                            ThemeMode.System -> "system"
                        },
                    )
                    loadDataWithBaseURL(store.relayUrl.trimEnd('/') + "/", bootstrap, "text/html", "utf-8", null)
                }
            },
            update = { view ->
                // Keep the existing document; token injection is handled on page events.
            },
        )
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

private fun injectSession(view: WebView, store: SessionStore, deviceId: String, themeMode: ThemeMode) {
    val theme = when (themeMode) {
        ThemeMode.Light -> "light"
        ThemeMode.Dark -> "dark"
        ThemeMode.System -> "system"
    }
    val script = """
        try {
          localStorage.setItem('remote-codex-relay-mode', 'true');
          localStorage.setItem('remote-codex-relay-token', ${jsString(store.token)});
          localStorage.setItem('remote-codex-relay-device-id', ${jsString(deviceId)});
          localStorage.setItem('remote-codex-theme-mode', ${jsString(theme)});
        } catch (e) {}
    """.trimIndent()
    view.evaluateJavascript(script, null)
}

private fun bootstrapHtml(
    origin: String,
    token: String,
    deviceId: String,
    threadId: String,
    theme: String,
): String {
    val target = "$origin/devices/${java.net.URLEncoder.encode(deviceId, "UTF-8")}/threads/${java.net.URLEncoder.encode(threadId, "UTF-8")}?nativeApp=1"
    return """
        <!doctype html>
        <meta charset="utf-8">
        <title>Remote Codex</title>
        <script>
          try {
            localStorage.setItem('remote-codex-relay-mode', 'true');
            localStorage.setItem('remote-codex-relay-token', ${jsString(token)});
            localStorage.setItem('remote-codex-relay-device-id', ${jsString(deviceId)});
            localStorage.setItem('remote-codex-theme-mode', ${jsString(theme)});
          } catch (e) {}
          location.replace(${jsString(target)});
        </script>
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
