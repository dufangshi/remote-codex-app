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
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
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
import com.remotecodex.app.ui.components.ProductHeader

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun ThreadWebScreen(
    store: SessionStore,
    api: ApiClient,
    deviceId: String,
    threadId: String,
    themeMode: ThemeMode,
    sessionName: String? = null,
    onBack: () -> Unit,
    onOpenNav: () -> Unit,
    onOpenAccount: () -> Unit,
    onLeaveThread: (AppRoute) -> Unit,
) {
    RelayWebScreen(
        store = store,
        deviceId = deviceId,
        themeMode = themeMode,
        pathAndQuery = threadPagePath(deviceId, threadId),
        stayOnPath = { path -> isThreadDocumentPath(path) && path.contains(threadId) },
        title = "Thread",
        backLabel = "Back to workspaces",
        testTag = "threadWebView",
        sessionName = sessionName,
        onBack = onBack,
        onOpenNav = onOpenNav,
        onOpenAccount = onOpenAccount,
        onLeave = onLeaveThread,
        onNativeClose = onBack,
        onAttached = {
            ActiveThreadTracker.current = OpenThreadRef(deviceId, threadId)
        },
        onDetached = {
            if (ActiveThreadTracker.current?.threadId == threadId) {
                ActiveThreadTracker.current = null
            }
        },
    )
}

@Composable
fun SettingsWebScreen(
    store: SessionStore,
    deviceId: String,
    themeMode: ThemeMode,
    sessionName: String? = null,
    onBack: () -> Unit,
    onOpenNav: () -> Unit,
    onOpenAccount: () -> Unit,
    onLeave: (AppRoute) -> Unit,
    onPrefs: (theme: String?, autoCollapse: Boolean?) -> Unit = { _, _ -> },
) {
    RelayWebScreen(
        store = store,
        deviceId = deviceId,
        themeMode = themeMode,
        pathAndQuery = "/relay-settings?nativeApp=1&relay=1",
        stayOnPath = { path -> path == "/relay-settings" },
        title = "Settings",
        backLabel = "Back",
        testTag = "settingsDialog",
        sessionName = sessionName,
        onBack = {
            readRelayWebPrefs(onPrefs)
            onBack()
        },
        onOpenNav = onOpenNav,
        onOpenAccount = onOpenAccount,
        onLeave = {
            readRelayWebPrefs(onPrefs)
            onLeave(it)
        },
        onNativeClose = {
            readRelayWebPrefs(onPrefs)
            onBack()
        },
    )
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun RelayWebScreen(
    store: SessionStore,
    deviceId: String,
    themeMode: ThemeMode,
    pathAndQuery: String,
    stayOnPath: (String) -> Boolean,
    title: String,
    backLabel: String,
    testTag: String,
    sessionName: String?,
    onBack: () -> Unit,
    onOpenNav: () -> Unit,
    onOpenAccount: () -> Unit,
    onLeave: (AppRoute) -> Unit,
    onNativeClose: () -> Unit,
    onAttached: () -> Unit = {},
    onDetached: () -> Unit = {},
) {
    val colors = rcColors
    var error by remember { mutableStateOf<String?>(null) }
    DisposableEffect(pathAndQuery) {
        onAttached()
        onDispose { onDetached() }
    }
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.appBg)
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        ProductHeader(
            title = title,
            backLabel = backLabel,
            onBack = onBack,
            onOpenNav = onOpenNav,
            onOpenAccount = onOpenAccount,
            accountLabel = sessionName,
        )
        Box(
            Modifier
                .weight(1f)
                .fillMaxSize()
                .testTag(testTag),
        ) {
            key(pathAndQuery, store.relayUrl) {
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { context ->
                        WebView(context).apply {
                            layoutParams = ViewGroup.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT,
                            )
                            overScrollMode = View.OVER_SCROLL_NEVER
                            setBackgroundColor(colors.appBg.toArgb())
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            settings.databaseEnabled = true
                            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                            settings.cacheMode = WebSettings.LOAD_DEFAULT
                            CookieManager.getInstance().setAcceptCookie(true)
                            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                            webChromeClient = WebChromeClient()
                            webViewClient = RelayLeaveClient(
                                deviceId = deviceId,
                                stayOnPath = stayOnPath,
                                onLeave = onLeave,
                                onNativeClose = onNativeClose,
                                onError = { error = it },
                                inject = { view -> injectSession(view, store, deviceId, themeMode) },
                            )
                            installDocumentStartScript(this, store, deviceId, themeMode)
                            loadRelayPage(this, store, pathAndQuery)
                            lastWebView = this
                        }
                    },
                    update = { /* Recreated by key() when the target changes. */ },
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
}

private var lastWebView: WebView? = null

internal fun readRelayWebPrefs(onPrefs: (theme: String?, autoCollapse: Boolean?) -> Unit) {
    val view = lastWebView ?: return onPrefs(null, null)
    view.evaluateJavascript(
        """(function(){
          try {
            return JSON.stringify({
              theme: localStorage.getItem('remote-codex-theme-mode'),
              collapse: localStorage.getItem('remote-codex-auto-collapse-completed-turns')
            });
          } catch (e) { return '{}'; }
        })()""",
    ) { raw ->
        val parsed = runCatching {
            val value = org.json.JSONTokener(raw ?: "{}").nextValue()
            when (value) {
                is org.json.JSONObject -> value
                is String -> org.json.JSONObject(value)
                else -> org.json.JSONObject()
            }
        }.getOrNull()
        val theme = parsed?.optString("theme")?.takeIf { it in setOf("light", "dark", "system") }
        val collapse = when (parsed?.optString("collapse")) {
            "true" -> true
            "false" -> false
            else -> null
        }
        onPrefs(theme, collapse)
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
    if (path == "/relay-settings") return AppRoute.Settings
    if (path == "/" || path == "/relay-portal") return AppRoute.Home
    return null
}

private class RelayLeaveClient(
    private val deviceId: String,
    private val stayOnPath: (String) -> Boolean,
    private val onLeave: (AppRoute) -> Unit,
    private val onNativeClose: () -> Unit,
    private val onError: (String) -> Unit,
    private val inject: (WebView) -> Unit,
) : WebViewClient() {
    private var sawTargetPath = false

    override fun shouldOverrideUrlLoading(
        view: WebView,
        request: WebResourceRequest,
    ): Boolean {
        if (!request.isForMainFrame) return false
        return leaveIfNative(request.url.toString())
    }

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
        markTargetPath(url)
        inject(view)
    }

    override fun onPageFinished(view: WebView, url: String) {
        markTargetPath(url)
        inject(view)
    }

    override fun onReceivedError(
        view: WebView,
        request: WebResourceRequest,
        errorResult: android.webkit.WebResourceError,
    ) {
        if (request.isForMainFrame) {
            onError(errorResult.description?.toString() ?: "Unable to load page.")
        }
    }

    private fun markTargetPath(url: String?) {
        val path = android.net.Uri.parse(url ?: return).path.orEmpty()
        if (stayOnPath(path)) {
            sawTargetPath = true
        }
    }

    private fun leaveIfNative(url: String?): Boolean {
        val uri = android.net.Uri.parse(url ?: return false)
        val path = uri.path.orEmpty()
        markTargetPath(url)
        if (path == "/__native/close") {
            onNativeClose()
            return true
        }
        if (!sawTargetPath || path.isEmpty() || path == "/" || path == "/relay-portal") {
            return false
        }
        if (stayOnPath(path)) {
            return false
        }
        val leave = nativeRouteForWebPath(deviceId, path, uri.query) ?: return false
        onLeave(leave)
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

private fun threadPagePath(deviceId: String, threadId: String): String {
    val device = java.net.URLEncoder.encode(deviceId, "UTF-8")
    val thread = java.net.URLEncoder.encode(threadId, "UTF-8")
    return "/devices/$device/threads/$thread?nativeApp=1&relay=1"
}

private fun loadRelayPage(
    view: WebView,
    store: SessionStore,
    pathAndQuery: String,
) {
    val origin = store.relayUrl.trimEnd('/')
    val target = origin + pathAndQuery.let { if (it.startsWith("/")) it else "/$it" }
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
        manager.setCookie(origin, cookie)
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
    val secure = if (store.relayUrl.startsWith("https", ignoreCase = true)) "; Secure" else ""
    return """
        (function () {
          window.__REMOTE_CODEX_BOOTSTRAP__ = Object.assign(
            { mode: 'relay', relayApiBase: '/relay' },
            window.__REMOTE_CODEX_BOOTSTRAP__ || {}
          );
          if (window.__REMOTE_CODEX_NATIVE_SESSION__) return;
          window.__REMOTE_CODEX_NATIVE_SESSION__ = true;
          var token = ${jsString(store.token)};
          try {
            document.cookie = 'remote_codex_relay_session=' + token + '; path=/; SameSite=Lax$secure';
            localStorage.setItem('remote-codex-relay-mode', 'true');
            localStorage.removeItem('remote-codex-relay-token');
            localStorage.setItem('remote-codex-relay-device-id', ${jsString(deviceId)});
            localStorage.setItem('remote-codex-theme-mode', ${jsString(theme)});
            localStorage.setItem('remote-codex-auto-collapse-completed-turns', ${jsString(if (store.autoCollapseCompletedTurns) "true" else "false")});
          } catch (e) {}
          try {
            var origFetch = window.fetch.bind(window);
            window.fetch = function (input, init) {
              try {
                if (token && input instanceof Request) {
                  if (!input.headers.has('Authorization')) {
                    var reqHeaders = new Headers(input.headers);
                    reqHeaders.set('Authorization', 'Bearer ' + token);
                    return origFetch(new Request(input, { headers: reqHeaders }));
                  }
                  return origFetch(input);
                }
                var nextHeaders = new Headers((init && init.headers) || {});
                if (token && !nextHeaders.has('Authorization')) {
                  nextHeaders.set('Authorization', 'Bearer ' + token);
                }
                return origFetch(input, Object.assign({}, init || {}, {
                  headers: nextHeaders,
                  credentials: (init && init.credentials) || 'same-origin'
                }));
              } catch (err) {
                return origFetch(input, init);
              }
            };
          } catch (e) {}
          try {
            var fake = {
              postMessage: function () {},
              scriptURL: (location.origin || '') + '/',
              state: 'activated',
              addEventListener: function () {},
              removeEventListener: function () {},
              onstatechange: null
            };
            var dummyReg = {
              installing: null, waiting: null, active: fake, scope: (location.origin || '') + '/',
              update: function () { return Promise.resolve(); },
              unregister: function () { return Promise.resolve(true); },
              addEventListener: function () {},
              removeEventListener: function () {}
            };
            var swShim = {
              controller: fake,
              ready: Promise.resolve(dummyReg),
              register: function () { return Promise.resolve(dummyReg); },
              getRegistration: function () { return Promise.resolve(dummyReg); },
              getRegistrations: function () { return Promise.resolve([dummyReg]); },
              addEventListener: function () {},
              removeEventListener: function () {},
              startMessages: function () {}
            };
            try {
              Object.defineProperty(navigator, 'serviceWorker', {
                configurable: true,
                enumerable: true,
                value: swShim
              });
            } catch (replaceErr) {
              var sw = navigator.serviceWorker;
              if (sw) {
                try { sw.register = function () { return Promise.resolve(dummyReg); }; } catch (e) {}
                try { Object.defineProperty(sw, 'ready', { configurable: true, get: function () { return Promise.resolve(dummyReg); } }); } catch (e) {}
                try { Object.defineProperty(sw, 'controller', { configurable: true, get: function () { return fake; } }); } catch (e) {}
              }
            }
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
