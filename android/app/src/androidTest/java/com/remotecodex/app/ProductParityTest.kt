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
                device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "parity-failure.png"))
                fail(message + " | " + js("JSON.stringify({url:location.href,bridge:!!window.remoteCodexNative,body:document.body?.innerText?.slice(0,1500)})"))
            }
            fun tap(element: String) {
                val rect = org.json.JSONObject(js("(() => { const r=($element).getBoundingClientRect(); return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2,width:innerWidth}); })()"))
                var x = 0; var y = 0
                scenario.onActivity { activity ->
                    val view = find(activity.window.decorView)!!
                    val location = IntArray(2); view.getLocationOnScreen(location)
                    val scale = view.width / rect.getDouble("width")
                    x = location[0] + (rect.getDouble("x") * scale).toInt()
                    y = location[1] + (rect.getDouble("y") * scale).toInt()
                }
                device.click(x, y)
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
            assertEquals("thread fills the measured viewport", "true", js("document.querySelector('.thread-ui-shell').getBoundingClientRect().height > innerHeight * .9"))
            js("document.querySelector('[aria-label=\"Thread tools\"]').click()")
            eventually("thread tools expand") { js("!!document.querySelector('.matter-breadcrumb')") == "true" }
            assertEquals("file attachments available", "true", js("!!document.querySelector('input[type=file]')"))
            tap("document.querySelector('[aria-label=\"Add attachment\"]')")
            eventually("attachment menu opens") { js("Array.from(document.querySelectorAll('button')).some(b => b.textContent.trim() === 'File')") == "true" }
            tap("Array.from(document.querySelectorAll('.thread-composer-menu-surface button')).find(b => b.textContent.trim() === 'File')")
            assertTrue("native attachment picker opens", device.wait(Until.hasObject(By.pkg(java.util.regex.Pattern.compile(".*documentsui"))), 10_000))
            device.pressBack()
            eventually("returns to encrypted thread after cancelling picker") { js("location.pathname") == "/devices/${env.deviceId}/threads/${created.id}" }
            js("document.querySelector('[aria-label=\"Download transcript\"]').click()")
            eventually("export dialog ready") { js("Array.from(document.querySelectorAll('button')).some(b => b.textContent.trim() === 'Export HTML' && !b.disabled)") == "true" }
            js("Array.from(document.querySelectorAll('button')).find(b => b.textContent.trim() === 'Export HTML').click()")
            val exported = device.wait(Until.hasObject(By.pkg(java.util.regex.Pattern.compile(".*documentsui"))), 15_000)
            if (!exported) println("Export state: " + js("document.body.innerText"))
            assertTrue("HTML export opens native save picker", exported)
            device.pressBack()
            js("navigator.share({title:'Remote Codex',text:'Share a thread',url:location.href})")
            assertTrue("native share sheet opens", device.wait(Until.hasObject(By.pkg(java.util.regex.Pattern.compile("com.android.intentresolver|android"))), 10_000))
            device.pressBack()
            // A warm notification/deep-link must replace the page, not only its native route.
            val other = env.startThreadAndPrompt()
            context.startActivity(Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("deviceId", env.deviceId); putExtra("threadId", other.id)
            })
            eventually("warm link updates page") { js("location.pathname") == "/devices/${env.deviceId}/threads/${other.id}" }
            scenario.recreate()
            eventually("notification route survives activity recreation") { js("location.pathname") == "/devices/${env.deviceId}/threads/${other.id}" }
            eventually("recreated thread is visibly rendered") { js("document.querySelector('.thread-ui-shell')?.getBoundingClientRect().height > innerHeight * .9") == "true" }
            eventually("recreated encrypted conversation loads") { js("!!document.querySelector('[role=textbox][aria-label=Prompt]') && document.body.innerText.includes('hello')") == "true" }
            device.executeShellCommand("screencap -p /sdcard/Download/remote-codex-parity.png")
        }
    }
}
