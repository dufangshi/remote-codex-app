package com.remotecodex.app

import android.content.Context
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONTokener
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class ProductParityTest {
    @get:Rule val notifications = GrantPermissionRule.grant(android.Manifest.permission.POST_NOTIFICATIONS)

    @Test fun encryptedThreadAndSystemNotificationOpenExactThread() {
        val env = E2eEnv.load()
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("remote_codex", Context.MODE_PRIVATE).edit().clear().commit()
        context.getSharedPreferences("notification_cursor", Context.MODE_PRIVATE).edit().clear().commit()
        val intent = Intent(context, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_RELAY_URL, env.appRelayUrl)
            putExtra(MainActivity.EXTRA_TOKEN, env.token)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            fun find(view: View): WebView? {
                if (view is WebView) return view
                if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i))?.let { return it }
                return null
            }
            fun js(source: String): String {
                val latch = CountDownLatch(1)
                var result = ""
                scenario.onActivity { activity ->
                    val web = find(activity.window.decorView) ?: error("WebView missing")
                    web.evaluateJavascript(source) { result = it; latch.countDown() }
                }
                assertTrue("JavaScript callback", latch.await(10, TimeUnit.SECONDS))
                return JSONTokener(result).nextValue().toString()
            }
            fun eventually(message: String, check: () -> Boolean) {
                val end = System.currentTimeMillis() + 30_000
                while (System.currentTimeMillis() < end) {
                    if (runCatching(check).getOrDefault(false)) return
                    Thread.sleep(200)
                }
                fail(message + " | " + js("JSON.stringify({url:location.href,bridge:!!window.remoteCodexNative,body:document.body?.innerText?.slice(0,1500)})"))
            }
            eventually("native bridge and authenticated page") { js("!!window.remoteCodexNative && !!document.body.innerText") == "true" }
            // Initialize the durable watcher before finishing a real fake-harness turn.
            eventually("notification watcher started") {
                context.getSharedPreferences("notification_cursor", Context.MODE_PRIVATE).all.keys.any { it.endsWith(".since") }
            }
            device.pressHome()
            val created = env.startThreadAndPrompt()
            device.openNotification()
            assertTrue("system completion notification", device.wait(Until.hasObject(By.textContains("Agent run finished")), 30_000))
            device.findObject(By.textContains("Agent run finished")).click()
            device.executeShellCommand("cmd statusbar collapse")
            eventually("notification opens exact device and thread") { js("location.pathname") == "/devices/${env.deviceId}/threads/${created.id}" }
            eventually("encrypted thread renders its real composer") { js("!!document.querySelector('[role=textbox][aria-label=Prompt]')") == "true" }
            assertEquals("one shared header, no native duplicate", "1", js("document.querySelectorAll('.matter-topbar').length"))
            assertEquals("mobile rail absent", "0", js("document.querySelectorAll('.matter-rail').length"))
            assertEquals("tools collapsed by default", "0", js("document.querySelectorAll('.matter-breadcrumb').length"))
            assertEquals("real Service Worker controls encrypted files", "true", js("!!navigator.serviceWorker.controller"))
            js("document.querySelector('[aria-label=\"Thread tools\"]').click()")
            eventually("thread tools expand") { js("!!document.querySelector('.matter-breadcrumb')") == "true" }
            assertEquals("file attachments available", "true", js("!!document.querySelector('input[type=file]')"))
            // A warm notification/deep-link must replace the page, not only its native route.
            val other = env.startThreadAndPrompt()
            context.startActivity(Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("deviceId", env.deviceId); putExtra("threadId", other.id)
            })
            eventually("warm link updates page") { js("location.pathname") == "/devices/${env.deviceId}/threads/${other.id}" }
        }
    }
}
