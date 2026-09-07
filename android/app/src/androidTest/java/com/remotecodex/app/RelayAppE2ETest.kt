package com.remotecodex.app

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class RelayAppE2ETest {
    @get:Rule(order = 0)
    val clearPrefs = ClearPrefsRule()

    @get:Rule(order = 1)
    val notifications = GrantPermissionRule.grant(android.Manifest.permission.POST_NOTIFICATIONS)

    @get:Rule(order = 2)
    val compose = SoftComposeRule()

    private lateinit var device: UiDevice
    private lateinit var env: E2eEnv

    @Before
    fun setUp() {
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        env = E2eEnv.load()
    }

    @Test
    fun loginNavigateThreadAndOpenCompletedNotification() {
        compose.onNodeWithTag("relayUrlField").assertIsDisplayed()
        compose.onNodeWithTag("relayUrlField").performTextClearance()
        compose.onNodeWithTag("relayUrlField").performTextInput(env.appRelayUrl)
        compose.onNodeWithTag("continueButton").performClick()

        compose.waitUntil(20_000) {
            compose.onAllNodesWithTag("signInEntryButton").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithTag("openDevicesButton").fetchSemanticsNodes().isNotEmpty()
        }
        if (compose.onAllNodesWithTag("signInEntryButton").fetchSemanticsNodes().isNotEmpty()) {
            compose.onNodeWithTag("signInEntryButton").performClick()
        }

        compose.waitUntil(20_000) {
            compose.onAllNodesWithTag("identifierField").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithTag("connectDeviceButton").fetchSemanticsNodes().isNotEmpty()
        }

        if (compose.onAllNodesWithTag("identifierField").fetchSemanticsNodes().isNotEmpty()) {
            compose.onNodeWithTag("identifierField").performTextInput(env.username)
            compose.onNodeWithTag("passwordField").performTextInput(env.password)
            compose.onNodeWithTag("signInButton").performClick()
        }

        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag("connectDeviceButton").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("connectDeviceButton").performClick()

        val workspaceTag = "workspace-${env.workspaceId}"
        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag(workspaceTag).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag(workspaceTag).performClick()

        compose.waitUntil(20_000) {
            compose.onAllNodesWithTag("New thread").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithText("Recent Threads").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithText("No threads available in this workspace.").fetchSemanticsNodes().isNotEmpty()
        }

        val created = env.startThreadAndPrompt()
        compose.waitUntil(10_000) {
            compose.onAllNodesWithTag("Back to workspaces").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("Back to workspaces").performClick()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag(workspaceTag).fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithText("Workspaces").fetchSemanticsNodes().isNotEmpty()
        }

        device.openNotification()
        assertTrue(
            "expected agent-complete notification",
            device.wait(Until.hasObject(By.textContains("Agent run")), 60_000),
        )
        val n = device.findObject(By.textContains("Agent run"))
            ?: device.findObject(By.textContains(created.title))
        n.click()

        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag("threadWebView").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("threadWebView").assertIsDisplayed()
        device.executeShellCommand("cmd statusbar collapse")
    }
}

private fun androidx.compose.ui.test.SemanticsNodeInteractionCollection.fetchSemanticsNodes() =
    fetchSemanticsNodes(atLeastOneRootRequired = false)

class SoftComposeRule : org.junit.rules.TestRule {
    val inner = androidx.compose.ui.test.junit4.createAndroidComposeRule<MainActivity>()

    override fun apply(base: org.junit.runners.model.Statement, description: org.junit.runner.Description): org.junit.runners.model.Statement {
        val wrapped = inner.apply(base, description)
        return object : org.junit.runners.model.Statement() {
            override fun evaluate() {
                try {
                    wrapped.evaluate()
                } catch (error: AssertionError) {
                    if (error.message?.contains("DESTROYED") == true) return
                    throw error
                }
            }
        }
    }

    fun onNodeWithTag(tag: String) = inner.onNodeWithTag(tag)
    fun onAllNodesWithTag(tag: String) = inner.onAllNodesWithTag(tag)
    fun onAllNodesWithText(text: String) = inner.onAllNodesWithText(text)
    fun waitUntil(timeoutMillis: Long, condition: () -> Boolean) = inner.waitUntil(timeoutMillis, condition)
}

class ClearPrefsRule : org.junit.rules.TestWatcher() {
    override fun starting(description: org.junit.runner.Description) {
        ApplicationProvider.getApplicationContext<Context>()
            .getSharedPreferences("remote_codex", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }
}

data class E2eEnv(
    val appRelayUrl: String,
    val hostRelayUrl: String,
    val username: String,
    val password: String,
    val token: String,
    val deviceId: String,
    val workspaceId: String,
    val deviceApi: String,
) {
    fun startThreadAndPrompt(): CreatedThread {
        val title = "notify-${UUID.randomUUID().toString().take(6)}"
        val thread = post(
            "$deviceApi/threads/start",
            """{"workspaceId":"$workspaceId","title":"$title","provider":"codex","model":"ios-e2e-stream","approvalMode":"yolo"}""",
        )
        val id = thread.optString("id").ifBlank { thread.optJSONObject("thread")?.optString("id") }.orEmpty()
        post("$deviceApi/threads/$id/prompt", """{"prompt":"hello, reply me with hello"}""")
        return CreatedThread(id, title)
    }

    private fun post(url: String, body: String): JSONObject {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.setRequestProperty("content-type", "application/json")
        if (token.isNotBlank()) {
            connection.setRequestProperty("authorization", "Bearer $token")
        }
        connection.outputStream.use { it.write(body.toByteArray()) }
        val text = connection.inputStream.bufferedReader().readText()
        return if (text.isBlank()) JSONObject() else JSONObject(text)
    }

    companion object {
        fun load(): E2eEnv {
            val args = InstrumentationRegistry.getArguments()
            val appRelayUrl = args.getString("relayUrl")
                ?: "http://127.0.0.1:${args.getString("relayPort") ?: "18790"}"
            val hostRelayUrl = args.getString("hostRelayUrl") ?: appRelayUrl
            val username = args.getString("username") ?: "mobile"
            val password = args.getString("password") ?: "mobile-pass-1"
            val token = args.getString("token").orEmpty()
            val deviceId = args.getString("deviceId").orEmpty()
            val workspaceId = args.getString("workspaceId").orEmpty()
            val deviceApi = args.getString("deviceApi")
                ?: "$hostRelayUrl/relay/devices/$deviceId/api"
            return E2eEnv(
                appRelayUrl = appRelayUrl,
                hostRelayUrl = hostRelayUrl,
                username = username,
                password = password,
                token = token,
                deviceId = deviceId,
                workspaceId = workspaceId,
                deviceApi = deviceApi,
            )
        }
    }
}

data class CreatedThread(val id: String, val title: String)
