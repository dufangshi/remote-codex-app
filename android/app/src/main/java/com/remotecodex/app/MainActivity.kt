package com.remotecodex.app

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.webkit.CookieManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.core.view.WindowCompat
import com.remotecodex.app.data.SessionStore
import com.remotecodex.app.notify.*
import com.remotecodex.app.theme.RemoteCodexTheme
import com.remotecodex.app.ui.screens.ConnectScreen
import com.remotecodex.app.ui.screens.ProductWebScreen
import android.net.Uri

class MainActivity : ComponentActivity() {
    private lateinit var store: SessionStore
    private var target by mutableStateOf("/")
    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        enableEdgeToEdge()
        store = SessionStore(this)
        // Test configuration cannot alter production sessions through exported intents.
        if (BuildConfig.DEBUG) {
            intent.getStringExtra(EXTRA_RELAY_URL)?.let { store.relayUrl = it }
            intent.getStringExtra(EXTRA_TOKEN)?.let { store.token = it }
        }
        handleDeepLink(intent)
        if (Build.VERSION.SDK_INT >= 33) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        if (store.isSignedIn) AgentEventService.start(this)
        setContent {
            var connected by remember { mutableStateOf(store.hasRelayUrl) }
            var theme by remember { mutableStateOf(store.themeMode) }
            val dark = theme == com.remotecodex.app.theme.ThemeMode.Dark || (theme == com.remotecodex.app.theme.ThemeMode.System && isSystemInDarkTheme())
            SideEffect {
                WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
            }
            RemoteCodexTheme(theme) {
                if (!connected) ConnectScreen(store) { connected = true; target = "/" }
                else key(store.relayUrl) {
                    ProductWebScreen(store, target, onChangeRelay = {
                        AgentEventService.stop(this)
                        CookieManager.getInstance().removeAllCookies(null)
                        store.clearSession()
                        store.relayUrl = ""
                        connected = false
                    }, onTheme = { theme = it })
                }
            }
        }
    }

    override fun onStart() { super.onStart(); RemoteCodexForeground.isForeground = true }
    override fun onStop() { RemoteCodexForeground.isForeground = false; super.onStop() }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); handleDeepLink(intent) }

    private fun handleDeepLink(intent: Intent) {
        val relay = intent.getStringExtra(Notifications.EXTRA_RELAY_ORIGIN)
        if (relay != null && relay != store.relayUrl) return
        val uri = intent.data
        val parts = if (uri?.scheme == "remotecodex" && uri.host == "devices") listOf("devices") + uri.pathSegments else emptyList()
        val device = intent.getStringExtra(Notifications.EXTRA_DEVICE_ID) ?: parts.getOrNull(1)
        val thread = intent.getStringExtra(Notifications.EXTRA_THREAD_ID) ?: parts.takeIf { it.getOrNull(2) == "threads" }?.getOrNull(3)
        if (!device.isNullOrBlank() && !thread.isNullOrBlank() && thread !in setOf("new", "import")) {
            store.deviceId = device
            target = "/devices/${Uri.encode(device)}/threads/${Uri.encode(thread)}"
        }
    }

    companion object {
        const val EXTRA_RELAY_URL = "e2eRelayUrl"
        const val EXTRA_TOKEN = "e2eToken"
        const val EXTRA_DEVICE_ID = "e2eDeviceId"
    }
}
