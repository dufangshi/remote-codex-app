package com.remotecodex.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Smartphone
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.remotecodex.app.data.ApiClient
import com.remotecodex.app.data.ApiException
import com.remotecodex.app.data.LoginChallenge
import com.remotecodex.app.data.RelaySession
import com.remotecodex.app.data.SessionStore
import com.remotecodex.app.data.normalizeRelayUrl
import com.remotecodex.app.theme.rcColors
import com.remotecodex.app.ui.components.BrandMark
import com.remotecodex.app.ui.components.Notice
import com.remotecodex.app.ui.components.NoticeTone
import com.remotecodex.app.ui.components.PrimaryButton
import com.remotecodex.app.ui.components.RcField
import com.remotecodex.app.ui.components.RcPage
import com.remotecodex.app.ui.components.RcRadius
import com.remotecodex.app.ui.components.SecondaryButton
import kotlinx.coroutines.launch

@Composable
fun ConnectScreen(
    store: SessionStore,
    onContinue: () -> Unit,
) {
    val colors = rcColors
    var url by remember { mutableStateOf(store.relayUrl.ifBlank { "https://" }) }
    var error by remember { mutableStateOf<String?>(null) }
    RcPage {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(48.dp))
            Column(
                Modifier
                    .widthIn(max = 420.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                    .background(colors.panel)
                    .padding(20.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BrandMark()
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text("Remote Codex", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                        Text("Relay access", color = colors.fgMuted, fontSize = 12.sp)
                    }
                }
                Spacer(Modifier.height(16.dp))
                Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
                Spacer(Modifier.height(16.dp))
                Text("Connect to a relay", color = colors.fg, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(8.dp))
                Text(
                    "Enter the public relay URL. Sign-in after this step matches the web portal.",
                    color = colors.fgMuted,
                    fontSize = 14.sp,
                    lineHeight = 22.sp,
                )
                Spacer(Modifier.height(16.dp))
                RcField(
                    label = "Relay URL",
                    value = url,
                    onValueChange = { url = it; error = null },
                    placeholder = "https://relay.example.com",
                    tag = "relayUrlField",
                )
                if (error != null) {
                    Spacer(Modifier.height(12.dp))
                    Notice(error!!)
                }
                Spacer(Modifier.height(16.dp))
                PrimaryButton(
                    label = "Continue",
                    tag = "continueButton",
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        val normalized = normalizeRelayUrl(url)
                        if (normalized.isBlank()) {
                            error = "Enter a relay URL."
                            return@PrimaryButton
                        }
                        store.relayUrl = normalized
                        onContinue()
                    },
                )
            }
        }
    }
}

@Composable
fun HomeScreen(
    store: SessionStore,
    api: ApiClient,
    onSignIn: () -> Unit,
    onDevices: () -> Unit,
    onGuide: () -> Unit,
    onChangeRelay: () -> Unit,
) {
    val colors = rcColors
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var session by remember { mutableStateOf<RelaySession?>(null) }

    fun load() {
        loading = true
        error = null
        scope.launch {
            runCatching { api.fetchSession() }
                .onSuccess { session = it }
                .onFailure { error = it.message ?: "The relay service could not be reached." }
            loading = false
        }
    }

    LaunchedEffect(store.relayUrl) { load() }

    val authenticated = session?.authenticated == true && session?.user?.role != "admin"
    val title = when {
        loading -> "Checking relay access"
        error != null -> "Relay service unavailable"
        authenticated -> "Choose a device to continue"
        else -> "Sign in to your relay workspace"
    }

    RcPage {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BrandMark()
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("Remote Codex Relay", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                Text("Private supervisor access", color = colors.fgMuted, fontSize = 12.sp)
            }
            SecondaryButton("Guide", tag = "guideButton", leading = {
                Icon(Icons.Filled.MenuBook, null, tint = colors.fg, modifier = Modifier.size(16.dp))
            }, onClick = onGuide)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
        Column(Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(
                            when {
                                loading -> colors.fgMuted
                                error != null -> colors.dangerFg
                                authenticated -> colors.successFg
                                else -> colors.fgMuted
                            },
                        ),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    when {
                        loading -> "Checking session"
                        error != null -> "Connection failed"
                        authenticated -> "Signed in as ${session?.user?.username}"
                        else -> "Signed out"
                    },
                    color = colors.fgMuted,
                    fontSize = 14.sp,
                )
            }
            Spacer(Modifier.height(16.dp))
            Text(title, color = colors.fg, fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(12.dp))
            Text(
                when {
                    error != null -> "Your session could not be checked. Verify the relay address and try again."
                    authenticated -> "Open device management to connect to a supervisor, then continue into its workspaces and threads."
                    else -> "Use your relay account to reach the devices, workspaces, and threads shared with you."
                },
                color = colors.fgSoft,
                fontSize = 14.sp,
                lineHeight = 22.sp,
            )
            Spacer(Modifier.height(20.dp))
            if (error != null) {
                Notice(error!!)
                Spacer(Modifier.height(12.dp))
                SecondaryButton("Retry", onClick = { load() }, leading = {
                    Icon(Icons.Filled.Refresh, null, tint = colors.fg, modifier = Modifier.size(16.dp))
                })
            } else if (!loading) {
                PrimaryButton(
                    label = if (authenticated) "Open devices" else "Sign in",
                    tag = if (authenticated) "openDevicesButton" else "signInEntryButton",
                    onClick = if (authenticated) onDevices else onSignIn,
                    leading = {
                        Icon(Icons.Filled.Smartphone, null, tint = rcColors.accentSolidFg, modifier = Modifier.size(16.dp))
                    },
                )
            }
            Spacer(Modifier.height(28.dp))
            Text(store.relayUrl, color = colors.fgMuted, fontSize = 12.sp)
            Spacer(Modifier.height(8.dp))
            SecondaryButton("Change relay URL", tag = "changeRelayButton", onClick = onChangeRelay)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
        Column(Modifier.padding(20.dp)) {
            Text("Connection path", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            Spacer(Modifier.height(4.dp))
            Text("Three steps, one outbound tunnel.", color = colors.fgMuted, fontSize = 12.sp)
            Spacer(Modifier.height(12.dp))
            ConnectionStep("01", "Register a device", "Create a one-time token for the private supervisor machine.")
            ConnectionStep("02", "Start the supervisor", "Keep an outbound relay connection open from that machine.")
            ConnectionStep("03", "Open your workspace", "Select the online device and continue to its workspaces and threads.")
        }
    }
}

@Composable
private fun ConnectionStep(number: String, title: String, body: String) {
    val colors = rcColors
    Row(
        Modifier
            .fillMaxWidth()
            .border(width = 0.dp, color = colors.border)
            .padding(vertical = 12.dp),
    ) {
        Text(number, color = colors.fgMuted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(40.dp))
        Column {
            Text(title, color = colors.fg, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.height(4.dp))
            Text(body, color = colors.fgMuted, fontSize = 13.sp, lineHeight = 20.sp)
        }
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
}

@Composable
fun PortalScreen(
    store: SessionStore,
    api: ApiClient,
    onBack: () -> Unit,
    onGuide: () -> Unit,
    onAuthenticated: () -> Unit,
) {
    val colors = rcColors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var session by remember { mutableStateOf<RelaySession?>(null) }
    var loading by remember { mutableStateOf(true) }
    var mode by remember { mutableStateOf("login") }
    var identifier by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var registrationPassword by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var challenge by remember { mutableStateOf<LoginChallenge?>(null) }

    LaunchedEffect(store.relayUrl) {
        loading = true
        error = null
        runCatching { api.fetchSession() }
            .onSuccess {
                session = it
                if (it.authenticated && it.user?.role != "admin") {
                    onAuthenticated()
                }
            }
            .onFailure { error = it.message ?: "Unable to load the relay portal." }
        runCatching { api.fetchLoginChallenge() }
            .onSuccess { if (it.challengeRequired) challenge = it }
        loading = false
    }

    val registrationEnabled = session?.registrationEnabled == true
    val settings = session?.registrationSettings
    val passwordRequired = settings?.registrationPasswordConfigured == true

    RcPage {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier
                    .clickable(onClick = onBack)
                    .testTag("relayHomeLink")
                    .padding(end = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = colors.fg, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                BrandMark()
                Spacer(Modifier.width(8.dp))
                Text("Relay home", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            }
            Spacer(Modifier.weight(1f))
            SecondaryButton("Guide", leading = {
                Icon(Icons.Filled.MenuBook, null, tint = colors.fg, modifier = Modifier.size(16.dp))
            }, onClick = onGuide)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
        Column(
            Modifier.fillMaxWidth().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (loading) {
                Text("Checking relay session...", color = colors.fgMuted, fontSize = 14.sp, modifier = Modifier.padding(48.dp))
                return@Column
            }
            challenge?.let { pending ->
                LoginVerification(
                    api = api,
                    challenge = pending,
                    onSuccess = onAuthenticated,
                    onBack = {
                        scope.launch { api.cancelLoginChallenge() }
                        challenge = null
                    },
                )
                return@Column
            }
            Column(
                Modifier
                    .widthIn(max = 440.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                    .background(colors.panel)
                    .padding(20.dp),
            ) {
                Text("Relay access", color = colors.accentStrong, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(8.dp))
                Text(
                    if (mode == "login") "Welcome back" else "Create your account",
                    color = colors.fg,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    if (mode == "login") "Sign in to open your devices and shared work."
                    else "Create a relay user account for private supervisor access.",
                    color = colors.fgMuted,
                    fontSize = 14.sp,
                    lineHeight = 22.sp,
                )
                Spacer(Modifier.height(16.dp))
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(colors.muted)
                        .padding(4.dp),
                ) {
                    Box(
                        Modifier
                            .weight(1f)
                            .clip(RcRadius)
                            .background(if (mode == "login") colors.panel else colors.muted)
                            .clickable { mode = "login"; error = null }
                            .padding(vertical = 12.dp)
                            .testTag("signInTab"),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("Sign in", color = colors.fg, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                    }
                    Box(
                        Modifier
                            .weight(1f)
                            .clip(RcRadius)
                            .background(if (mode == "register") colors.panel else colors.muted)
                            .clickable(enabled = registrationEnabled) {
                                if (registrationEnabled) {
                                    mode = "register"
                                    error = null
                                }
                            }
                            .padding(vertical = 12.dp)
                            .testTag("registerTab"),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            if (registrationEnabled) "Create account" else "Registration closed",
                            color = if (registrationEnabled) colors.fg else colors.fgMuted,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
                if (settings?.googleAuthEnabled == true || settings?.githubAuthEnabled == true) {
                    Spacer(Modifier.height(16.dp))
                    if (settings.googleAuthEnabled) {
                        SecondaryButton("Continue with Google", modifier = Modifier.fillMaxWidth(), tag = "googleOAuth") {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(api.oauthStartUrl("google"))))
                        }
                        Spacer(Modifier.height(8.dp))
                    }
                    if (settings.githubAuthEnabled) {
                        SecondaryButton("Continue with GitHub", modifier = Modifier.fillMaxWidth(), tag = "githubOAuth") {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(api.oauthStartUrl("github"))))
                        }
                        Spacer(Modifier.height(8.dp))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 8.dp)) {
                        Box(Modifier.weight(1f).height(1.dp).background(colors.border))
                        Text("  or use a password  ", color = colors.fgMuted, fontSize = 12.sp)
                        Box(Modifier.weight(1f).height(1.dp).background(colors.border))
                    }
                }
                Spacer(Modifier.height(8.dp))
                if (mode == "login") {
                    RcField("Email or username", identifier, { identifier = it; error = null }, tag = "identifierField")
                } else {
                    RcField("Email", email, { email = it; error = null }, tag = "emailField")
                    Spacer(Modifier.height(12.dp))
                    RcField("Username", username, { username = it; error = null }, tag = "usernameField")
                    Spacer(Modifier.height(12.dp))
                    RcField(
                        label = if (passwordRequired) "Registration code" else "Registration code (if required)",
                        value = registrationPassword,
                        onValueChange = { registrationPassword = it; error = null },
                        password = true,
                        description = if (passwordRequired) "Required by this relay." else "Enter the invite code if this relay requires one.",
                        tag = "registrationCodeField",
                    )
                }
                Spacer(Modifier.height(12.dp))
                RcField(
                    "Password",
                    password,
                    { password = it; error = null },
                    password = true,
                    description = if (mode == "register") "Use at least 8 characters." else null,
                    tag = "passwordField",
                )
                if (error != null) {
                    Spacer(Modifier.height(12.dp))
                    Notice(error!!)
                }
                if (notice != null) {
                    Spacer(Modifier.height(12.dp))
                    Notice(notice!!, NoticeTone.Accent)
                }
                Spacer(Modifier.height(16.dp))
                PrimaryButton(
                    label = when {
                        busy -> "Working..."
                        mode == "login" -> "Sign in"
                        else -> "Create account"
                    },
                    tag = "signInButton",
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        busy = true
                        error = null
                        notice = null
                        scope.launch {
                            try {
                                if (mode == "login") {
                                    val result = api.login(identifier, password)
                                    password = ""
                                    if (result.challengeRequired) {
                                        challenge = LoginChallenge(
                                            challengeRequired = true,
                                            authenticator = result.authenticator,
                                            passkey = result.passkey,
                                        )
                                    } else if (result.session.user?.role == "admin") {
                                        api.logout()
                                        error = "This portal accepts relay user accounts only."
                                    } else {
                                        onAuthenticated()
                                    }
                                } else {
                                    if (password.length < 8) {
                                        error = "Password must be at least 8 characters."
                                    } else if (username.trim().length < 3) {
                                        error = "Username must be at least 3 characters."
                                    } else {
                                        val result = api.register(
                                            email = email,
                                            username = username,
                                            password = password,
                                            registrationPassword = registrationPassword.ifBlank { null },
                                        )
                                        if (result.pendingApproval) {
                                            notice = "Registration request sent. An admin must approve it before you can sign in."
                                            mode = "login"
                                        } else {
                                            onAuthenticated()
                                        }
                                    }
                                }
                            } catch (caught: ApiException) {
                                error = caught.body.message
                            } catch (caught: Exception) {
                                error = caught.message ?: "Unable to authenticate with the relay."
                            } finally {
                                busy = false
                            }
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun LoginVerification(
    api: ApiClient,
    challenge: LoginChallenge,
    onSuccess: () -> Unit,
    onBack: () -> Unit,
) {
    val colors = rcColors
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var rememberBrowser by remember { mutableStateOf(true) }
    var recovery by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(
        Modifier
            .widthIn(max = 440.dp)
            .clip(RoundedCornerShape(8.dp))
            .border(1.dp, colors.border, RoundedCornerShape(8.dp))
            .background(colors.panel)
            .padding(20.dp),
    ) {
        Text("Verify it’s you", color = colors.fg, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Text("One more step for this browser.", color = colors.fgMuted, fontSize = 14.sp)
        Spacer(Modifier.height(16.dp))
        if (challenge.authenticator || recovery) {
            RcField(
                if (recovery) "Recovery code" else "Authenticator code",
                code,
                { code = it; error = null },
                tag = "mfaCodeField",
            )
            if (!recovery) {
                Spacer(Modifier.height(12.dp))
                Row(
                    Modifier.clickable { rememberBrowser = !rememberBrowser },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(if (rememberBrowser) "☑" else "☐", color = colors.fg, fontSize = 16.sp)
                    Spacer(Modifier.width(8.dp))
                    Text("Trust this browser for 30 days", color = colors.fgMuted, fontSize = 14.sp)
                }
            }
            Spacer(Modifier.height(16.dp))
            PrimaryButton(
                if (busy) "Verifying…" else "Verify",
                enabled = !busy && code.isNotBlank(),
                tag = "verifyMfaButton",
            ) {
                busy = true
                error = null
                scope.launch {
                    runCatching { api.verifyLoginCode(code, rememberBrowser && !recovery) }
                        .onSuccess { onSuccess() }
                        .onFailure { error = it.message }
                    busy = false
                }
            }
        } else {
            Text("Use a recovery code, or finish sign-in on the web with a passkey.", color = colors.fgMuted, fontSize = 14.sp)
        }
        if (error != null) {
            Spacer(Modifier.height(12.dp))
            Notice(error!!)
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                if (recovery) "Use another method" else "Use a recovery code",
                color = colors.fgMuted,
                fontSize = 14.sp,
                modifier = Modifier.clickable {
                    recovery = !recovery
                    code = ""
                    error = null
                },
            )
            Text(
                "Back to sign in",
                color = colors.fgMuted,
                fontSize = 14.sp,
                modifier = Modifier.clickable(onClick = onBack).testTag("mfaBack"),
            )
        }
    }
}

@Composable
fun GuideScreen(onBack: () -> Unit) {
    val colors = rcColors
    val modes = listOf(
        "Local mode" to "For the same machine, an emulator, LAN, or Tailscale network. No relay account is needed.",
        "Server mode" to "For a directly exposed supervisor protected by its own server login on a trusted private server.",
        "Relay mode" to "For a machine that should accept no inbound connection. The supervisor opens an outbound tunnel.",
    )
    val steps = listOf(
        "Register or sign in" to "Open the relay portal, then create or enter your relay account.",
        "Create a device" to "In Devices, choose a recognizable name and create a one-time token for the private supervisor.",
        "Copy the setup command" to "Use Copy setup. The generated command includes the relay URL, device token, and supervisor port.",
        "Start the supervisor" to "Run the command on the workspace host. When tmux is available, Remote Codex keeps it detached by default.",
        "Connect and work" to "Return to Devices, wait for Online, then connect. Workspaces and threads use the selected device.",
        "Share when needed" to "From a thread, open sharing, enter a relay username, and choose thread and workspace permissions.",
    )
    RcPage {
        Column(Modifier.padding(20.dp)) {
            SecondaryButton("Relay home", tag = "guideBack", leading = {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = colors.fg, modifier = Modifier.size(16.dp))
            }, onClick = onBack)
            Spacer(Modifier.height(20.dp))
            Text("Setup guide", color = colors.accentStrong, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.height(8.dp))
            Text("Connect a private supervisor", color = colors.fg, fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            Text(
                "Pick the mode that matches your network, then follow the relay steps when the private machine should only connect outward.",
                color = colors.fgSoft,
                fontSize = 14.sp,
                lineHeight = 22.sp,
            )
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.border))
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Connection modes", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
            modes.forEach { (title, body) ->
                Column {
                    Text(title, color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    Spacer(Modifier.height(4.dp))
                    Text(body, color = colors.fgMuted, fontSize = 14.sp, lineHeight = 22.sp)
                }
            }
            Spacer(Modifier.height(8.dp))
            Text("Relay steps", color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
            steps.forEachIndexed { index, (title, body) ->
                Row {
                    Text(String.format("%02d", index + 1), color = colors.fgMuted, modifier = Modifier.width(36.dp), fontSize = 13.sp)
                    Column {
                        Text(title, color = colors.fg, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                        Spacer(Modifier.height(4.dp))
                        Text(body, color = colors.fgMuted, fontSize = 14.sp, lineHeight = 22.sp)
                    }
                }
            }
        }
    }
}
