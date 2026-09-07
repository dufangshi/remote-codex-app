package com.remotecodex.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.remotecodex.app.data.ApiClient
import com.remotecodex.app.data.RelaySession
import com.remotecodex.app.data.SessionStore
import com.remotecodex.app.notify.AgentEventService
import com.remotecodex.app.notify.Notifications
import com.remotecodex.app.notify.RemoteCodexForeground
import com.remotecodex.app.theme.RemoteCodexTheme
import com.remotecodex.app.theme.rcColors
import com.remotecodex.app.ui.AppRoute
import com.remotecodex.app.ui.InteractiveStackHost
import com.remotecodex.app.ui.NavController
import com.remotecodex.app.ui.screens.AccountMenu
import com.remotecodex.app.ui.screens.AccountScreen
import com.remotecodex.app.ui.screens.ConnectScreen
import com.remotecodex.app.ui.screens.DevicesScreen
import com.remotecodex.app.ui.screens.GuideScreen
import com.remotecodex.app.ui.screens.HomeScreen
import com.remotecodex.app.ui.screens.ImportScreen
import com.remotecodex.app.ui.screens.NavMenu
import com.remotecodex.app.ui.screens.PortalScreen
import com.remotecodex.app.ui.screens.SettingsSheet
import com.remotecodex.app.ui.screens.ThreadNewScreen
import com.remotecodex.app.ui.screens.ThreadWebScreen
import com.remotecodex.app.ui.screens.ThreadsScreen
import com.remotecodex.app.ui.screens.WorkspaceNewScreen
import com.remotecodex.app.ui.screens.WorkspacesScreen
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private lateinit var store: SessionStore
    private lateinit var api: ApiClient
    private val navState = mutableStateOf<AppRoute>(AppRoute.Connect)

    private val notificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* granted or not; watching still works in foreground */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        store = SessionStore(this)
        api = ApiClient(store)
        applyE2eOverrides(intent)
        if (store.hasRelayUrl) {
            navState.value = if (store.isSignedIn) AppRoute.Home else AppRoute.Home
        }
        maybeRequestNotifications()
        handleDeepLink(intent)
        if (store.isSignedIn && store.deviceId.isNotBlank()) {
            AgentEventService.start(this)
        }

        @OptIn(ExperimentalComposeUiApi::class)
        setContent {
            var themeMode by remember { mutableStateOf(store.themeMode) }
            var route by navState
            var session by remember { mutableStateOf<RelaySession?>(null) }
            var navOpen by remember { mutableStateOf(false) }
            var accountOpen by remember { mutableStateOf(false) }
            var settingsOpen by remember { mutableStateOf(false) }
            var navigatingForward by remember { mutableStateOf(true) }
            var popRequest by remember { mutableIntStateOf(0) }
            val scope = rememberCoroutineScope()
            val nav = remember {
                NavController(route).also { controller ->
                    // Keep controller aligned with the first composition route.
                }
            }

            fun go(next: AppRoute, replace: Boolean = false) {
                navigatingForward = true
                if (replace) nav.replace(next) else nav.push(next)
                route = nav.current
                navOpen = false
                accountOpen = false
            }

            fun back() {
                navOpen = false
                accountOpen = false
                val fallback = nav.backFrom(route)
                if (!nav.canGoBack() && fallback == null) return
                navigatingForward = false
                popRequest += 1
            }

            fun commitPop() {
                if (nav.pop()) {
                    route = nav.current
                } else {
                    val fallback = nav.backFrom(route)
                    if (fallback != null) {
                        nav.reset(fallback)
                        route = fallback
                    }
                }
            }

            DisposableEffect(Unit) {
                val observer = LifecycleEventObserver { _, event ->
                    when (event) {
                        Lifecycle.Event.ON_START, Lifecycle.Event.ON_RESUME ->
                            RemoteCodexForeground.isForeground = true
                        Lifecycle.Event.ON_STOP ->
                            RemoteCodexForeground.isForeground = false
                        else -> Unit
                    }
                }
                lifecycle.addObserver(observer)
                onDispose { lifecycle.removeObserver(observer) }
            }

            RemoteCodexTheme(themeMode) {
                val colors = rcColors
                BackHandler(enabled = route !is AppRoute.Connect) { back() }
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(colors.appBg)
                        .semantics { testTagsAsResourceId = true }
                        .testTag("appRoot"),
                ) {
                    InteractiveStackHost(
                        route = route,
                        previous = if (nav.canGoBack()) nav.previous else nav.backFrom(route),
                        canSwipeBack = nav.canGoBack() || nav.backFrom(route) != null,
                        navigatingForward = navigatingForward,
                        popRequest = popRequest,
                        onPopCommitted = { commitPop() },
                    ) { current ->
                    when (current) {
                        AppRoute.Connect -> ConnectScreen(store) {
                            nav.reset(AppRoute.Home)
                            route = AppRoute.Home
                        }
                        AppRoute.Home -> HomeScreen(
                            store = store,
                            api = api,
                            onSignIn = { go(AppRoute.Portal) },
                            onDevices = { go(AppRoute.Devices) },
                            onGuide = { go(AppRoute.Guide) },
                            onChangeRelay = {
                                store.clearSession()
                                AgentEventService.stop(this@MainActivity)
                                nav.reset(AppRoute.Connect)
                                route = AppRoute.Connect
                            },
                        )
                        AppRoute.Guide -> GuideScreen(onBack = { back() })
                        AppRoute.Portal -> PortalScreen(
                            store = store,
                            api = api,
                            onBack = { back() },
                            onGuide = { go(AppRoute.Guide) },
                            onAuthenticated = {
                                scope.launch {
                                    session = runCatching { api.fetchSession() }.getOrNull()
                                }
                                nav.reset(AppRoute.Home)
                                nav.push(AppRoute.Devices)
                                route = AppRoute.Devices
                                AgentEventService.start(this@MainActivity)
                            },
                        )
                        AppRoute.Devices -> DevicesScreen(
                            store = store,
                            api = api,
                            session = session,
                            onBack = { back() },
                            onOpenNav = { navOpen = true },
                            onOpenAccount = { accountOpen = true },
                            onConnectDevice = { device ->
                                store.deviceId = device.id
                                AgentEventService.refresh(this@MainActivity)
                                go(AppRoute.Workspaces(device.id))
                            },
                            onOpenSharedThread = { deviceId, threadId, workspaceId ->
                                store.deviceId = deviceId
                                AgentEventService.refresh(this@MainActivity)
                                go(AppRoute.ThreadDetail(deviceId, threadId, workspaceId))
                            },
                            onOpenSharedDevice = { deviceId ->
                                store.deviceId = deviceId
                                AgentEventService.refresh(this@MainActivity)
                                go(AppRoute.Workspaces(deviceId))
                            },
                        )
                        is AppRoute.Workspaces -> WorkspacesScreen(
                            store = store,
                            api = api,
                            deviceId = current.deviceId,
                            session = session,
                            onBack = { back() },
                            onOpenNav = { navOpen = true },
                            onOpenAccount = { accountOpen = true },
                            onOpenWorkspace = { workspace ->
                                go(AppRoute.Threads(current.deviceId, workspace.id))
                            },
                            onNewWorkspace = { go(AppRoute.WorkspaceNew(current.deviceId)) },
                            onImport = { go(AppRoute.ThreadImport(current.deviceId)) },
                        )
                        is AppRoute.WorkspaceNew -> WorkspaceNewScreen(
                            api = api,
                            deviceId = current.deviceId,
                            onBack = { back() },
                            onCreated = { workspace ->
                                nav.pop()
                                go(AppRoute.Threads(current.deviceId, workspace.id))
                            },
                        )
                        is AppRoute.Threads -> ThreadsScreen(
                            api = api,
                            deviceId = current.deviceId,
                            workspaceId = current.workspaceId,
                            session = session,
                            onBack = { back() },
                            onOpenNav = { navOpen = true },
                            onOpenAccount = { accountOpen = true },
                            onOpenThread = { thread ->
                                go(AppRoute.ThreadDetail(current.deviceId, thread.id, current.workspaceId))
                            },
                            onNewThread = { go(AppRoute.ThreadNew(current.deviceId, current.workspaceId)) },
                        )
                        is AppRoute.ThreadNew -> ThreadNewScreen(
                            api = api,
                            deviceId = current.deviceId,
                            workspaceId = current.workspaceId,
                            onBack = { back() },
                            onCreated = { thread ->
                                nav.pop()
                                go(AppRoute.ThreadDetail(current.deviceId, thread.id, thread.workspaceId.ifBlank { current.workspaceId }))
                            },
                        )
                        is AppRoute.ThreadImport -> ImportScreen(
                            api = api,
                            deviceId = current.deviceId,
                            onBack = { back() },
                            onImported = { threadId ->
                                go(AppRoute.ThreadDetail(current.deviceId, threadId, null))
                            },
                        )
                        is AppRoute.ThreadDetail -> ThreadWebScreen(
                            store = store,
                            api = api,
                            deviceId = current.deviceId,
                            threadId = current.threadId,
                            themeMode = themeMode,
                            onLeaveThread = { next ->
                                when (next) {
                                    is AppRoute.ThreadDetail -> go(next, replace = true)
                                    else -> {
                                        nav.pop()
                                        go(next)
                                    }
                                }
                            },
                        )
                        AppRoute.Account -> AccountScreen(api = api, onBack = { back() })
                    }
                    }

                    if (navOpen) {
                        NavMenu(
                            devicesSelected = route is AppRoute.Devices,
                            onDevices = { go(AppRoute.Devices) },
                            onSettings = {
                                navOpen = false
                                settingsOpen = true
                            },
                            onDismiss = { navOpen = false },
                        )
                    }
                    if (accountOpen) {
                        AccountMenu(
                            session = session,
                            onAccount = { go(AppRoute.Account) },
                            onLogout = {
                                scope.launch {
                                    api.logout()
                                    AgentEventService.stop(this@MainActivity)
                                    nav.reset(AppRoute.Home)
                                    route = AppRoute.Home
                                    session = null
                                }
                            },
                            onDismiss = { accountOpen = false },
                        )
                    }
                    if (settingsOpen) {
                        SettingsSheet(
                            themeMode = themeMode,
                            autoCollapseCompletedTurns = store.autoCollapseCompletedTurns,
                            onThemeMode = {
                                themeMode = it
                                store.themeMode = it
                            },
                            onAutoCollapse = { store.autoCollapseCompletedTurns = it },
                            onDismiss = { settingsOpen = false },
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    private fun maybeRequestNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    private fun applyE2eOverrides(intent: Intent) {
        intent.getStringExtra(EXTRA_RELAY_URL)?.takeIf { it.isNotBlank() }?.let { store.relayUrl = it }
        intent.getStringExtra(EXTRA_TOKEN)?.takeIf { it.isNotBlank() }?.let { store.token = it }
        intent.getStringExtra(EXTRA_DEVICE_ID)?.takeIf { it.isNotBlank() }?.let { store.deviceId = it }
    }

    private fun handleDeepLink(intent: Intent?) {
        if (intent == null) return
        val extrasDevice = intent.getStringExtra(Notifications.EXTRA_DEVICE_ID)
        val extrasThread = intent.getStringExtra(Notifications.EXTRA_THREAD_ID)
        val data = intent.data
        val pathDevice = data?.pathSegments?.getOrNull(0)?.takeIf { data.pathSegments.getOrNull(0) != "devices" }
            ?: data?.pathSegments?.getOrNull(1)
        val threadFromPath = when {
            data?.pathSegments?.contains("threads") == true ->
                data.pathSegments.getOrNull(data.pathSegments.indexOf("threads") + 1)
            else -> null
        }
        val deviceId = extrasDevice ?: pathDevice ?: store.deviceId
        val threadId = extrasThread ?: threadFromPath
        if (!deviceId.isNullOrBlank() && !threadId.isNullOrBlank()) {
            store.deviceId = deviceId
            navState.value = AppRoute.ThreadDetail(deviceId, threadId, null)
        }
    }

    companion object {
        const val EXTRA_RELAY_URL = "e2eRelayUrl"
        const val EXTRA_TOKEN = "e2eToken"
        const val EXTRA_DEVICE_ID = "e2eDeviceId"
    }
}

private fun currentDeviceId(route: AppRoute): String? = when (route) {
    is AppRoute.Workspaces -> route.deviceId
    is AppRoute.WorkspaceNew -> route.deviceId
    is AppRoute.Threads -> route.deviceId
    is AppRoute.ThreadNew -> route.deviceId
    is AppRoute.ThreadImport -> route.deviceId
    is AppRoute.ThreadDetail -> route.deviceId
    else -> null
}
