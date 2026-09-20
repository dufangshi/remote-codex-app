package com.remotecodex.app.ui.screens

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Base64
import android.webkit.*
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.graphics.toArgb
import androidx.core.view.doOnLayout
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.remotecodex.app.data.SessionStore
import com.remotecodex.app.notify.*
import com.remotecodex.app.theme.ThemeMode
import com.remotecodex.app.theme.rcColors
import org.json.JSONObject

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun ProductWebScreen(store: SessionStore, target: String, onChangeRelay: () -> Unit, onTheme: (ThemeMode) -> Unit) {
    val context = LocalContext.current
    val colors = rcColors
    val origin = store.relayUrl.trimEnd('/')
    var web by remember { mutableStateOf<WebView?>(null) }
    var initialized by remember { mutableStateOf(false) }
    val latestTarget by rememberUpdatedState(target)
    var canBack by remember { mutableStateOf(false) }
    var chooser by remember { mutableStateOf<ValueCallback<Array<Uri>>?>(null) }
    var download by remember { mutableStateOf<ByteArray?>(null) }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        chooser?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data))
        chooser = null
    }
    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        val bytes = download
        download = null
        if (uri != null && bytes != null) runCatching {
            context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
        }.onFailure { Toast.makeText(context, "Unable to save file: ${it.message}", Toast.LENGTH_LONG).show() }
    }
    fun syncSession() {
        val token = CookieManager.getInstance().getCookie(origin)?.split(';')
            ?.map { it.trim() }?.firstOrNull { it.startsWith("remote_codex_relay_session=") }
            ?.substringAfter('=').orEmpty()
        if (store.token != token) {
            store.token = token
            if (token.isEmpty()) AgentEventService.stop(context) else AgentEventService.start(context)
        }
    }
    fun external(uri: Uri) {
        if (uri.scheme in setOf("https", "http", "mailto", "tel")) runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, uri))
        }
    }
    BackHandler(canBack) { web?.goBack() }
    DisposableEffect(Unit) {
        onDispose {
            chooser?.onReceiveValue(null)
            ActiveThreadTracker.current = null
            web?.destroy()
        }
    }
    AndroidView(
        modifier = Modifier.fillMaxSize().background(colors.appBg).statusBarsPadding().navigationBarsPadding().imePadding(),
        factory = {
            WebView(context).apply {
                web = this
                setBackgroundColor(colors.appBg.toArgb())
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.useWideViewPort = true
                settings.loadWithOverviewMode = true
                settings.allowFileAccess = false
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                settings.javaScriptCanOpenWindowsAutomatically = true
                settings.setSupportMultipleWindows(true)
                CookieManager.getInstance().setAcceptCookie(true)
                val bridgeSource = context.assets.open("native-bridge.js").bufferedReader().use { it.readText() }
                val earlyScript = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
                if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
                    WebViewCompat.addWebMessageListener(this, "RemoteCodexHost", setOf(origin)) { _, message, _, main, _ ->
                        if (main) runCatching {
                            val value = JSONObject(message.data ?: "{}")
                            when (value.optString("type")) {
                                "state" -> {
                                    syncSession()
                                    canBack = canGoBack()
                                    val route = threadRef(value.optString("path"))
                                    ActiveThreadTracker.current = route
                                    if (route != null) store.deviceId = route.deviceId
                                    val mode = when (value.optString("theme")) { "dark" -> ThemeMode.Dark; "light" -> ThemeMode.Light; else -> ThemeMode.System }
                                    if (store.themeMode != mode) { store.themeMode = mode; onTheme(mode) }
                                }
                                "changeRelay" -> onChangeRelay()
                                "notificationSettings" -> context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
                                "share" -> {
                                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                                        type = "text/plain"
                                        putExtra(Intent.EXTRA_TEXT, listOf(value.optString("text"), value.optString("url")).filter { it.isNotBlank() }.joinToString("\n"))
                                        putExtra(Intent.EXTRA_SUBJECT, value.optString("title"))
                                    }, "Share"))
                                    evaluateJavascript("window.remoteCodexNative.resolve(${value.getInt("id")},null)", null)
                                }
                                "download" -> {
                                    val data = value.getString("data")
                                    require(data.length <= 45 * 1024 * 1024)
                                    download = Base64.decode(data.substringAfter(","), Base64.DEFAULT)
                                    save.launch(value.optString("name", "download").substringAfterLast('/').substringAfterLast('\\'))
                                }
                                "error" -> Toast.makeText(context, value.optString("message"), Toast.LENGTH_LONG).show()
                            }
                        }.onFailure { Toast.makeText(context, "Unable to complete action: ${it.message}", Toast.LENGTH_LONG).show() }
                    }
                    if (earlyScript) WebViewCompat.addDocumentStartJavaScript(this, bridgeSource, setOf(origin))
                }
                webChromeClient = object : WebChromeClient() {
                    override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                        chooser?.onReceiveValue(null)
                        chooser = callback
                        runCatching { files.launch(params.createIntent()) }.onFailure { callback.onReceiveValue(null); chooser = null }
                        return true
                    }
                    override fun onCreateWindow(view: WebView, dialog: Boolean, gesture: Boolean, message: android.os.Message): Boolean {
                        if (!gesture) return false
                        val popup = WebView(context)
                        popup.webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean {
                                external(request.url)
                                popup.destroy()
                                return true
                            }
                        }
                        (message.obj as WebView.WebViewTransport).webView = popup
                        message.sendToTarget()
                        return true
                    }
                }
                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                        if (!earlyScript && sameOrigin(origin, Uri.parse(url))) view.evaluateJavascript(bridgeSource, null)
                    }
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        if (!request.isForMainFrame) return false
                        val url = request.url
                        if (sameOrigin(origin, url)) return false
                        external(url)
                        return true
                    }
                    override fun onPageFinished(view: WebView, url: String) {
                        if (!earlyScript && sameOrigin(origin, Uri.parse(url))) view.evaluateJavascript(bridgeSource, null)
                        syncSession(); canBack = canGoBack()
                    }
                }
                setDownloadListener { url, _, _, _, _ -> external(Uri.parse(url)) }
                val cookie = if (store.token.isNotEmpty()) "remote_codex_relay_session=${store.token}; Path=/; HttpOnly; SameSite=Lax${if (origin.startsWith("https:")) "; Secure" else ""}" else null
                fun start() { doOnLayout { loadUrl(origin + latestTarget); initialized = true } }
                if (cookie != null) CookieManager.getInstance().setCookie(origin, cookie) { start() }
                else start()
            }
        },
    )
    LaunchedEffect(target) {
        if (initialized) web?.let {
            if (it.url?.let(Uri::parse)?.encodedPath != Uri.parse(target).encodedPath) it.loadUrl(origin + target)
        }
    }
}

internal fun sameOrigin(origin: String, uri: Uri): Boolean {
    val expected = Uri.parse(origin)
    fun port(value: Uri) = if (value.port >= 0) value.port else if (value.scheme == "https") 443 else 80
    return uri.scheme == expected.scheme && uri.host == expected.host && port(uri) == port(expected)
}

internal fun threadRef(path: String): OpenThreadRef? {
    val parts = Uri.parse(path).pathSegments ?: return null
    if (parts.size != 4 || parts[0] != "devices" || parts[2] != "threads" || parts[3] in setOf("new", "import")) return null
    return OpenThreadRef(parts[1], parts[3])
}
