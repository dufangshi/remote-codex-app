package com.remotecodex.app.data

import android.content.Context
import android.content.SharedPreferences
import com.remotecodex.app.theme.ThemeMode

class SessionStore(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("remote_codex", Context.MODE_PRIVATE)

    var relayUrl: String
        get() = prefs.getString(KEY_URL, "").orEmpty()
        set(value) = prefs.edit().putString(KEY_URL, normalizeRelayUrl(value)).apply()

    var token: String
        get() = prefs.getString(KEY_TOKEN, "").orEmpty()
        set(value) = prefs.edit().putString(KEY_TOKEN, value).apply()

    var deviceId: String
        get() = prefs.getString(KEY_DEVICE, "").orEmpty()
        set(value) = prefs.edit().putString(KEY_DEVICE, value).apply()

    var themeMode: ThemeMode
        get() = when (prefs.getString(KEY_THEME, "system")) {
            "light" -> ThemeMode.Light
            "dark" -> ThemeMode.Dark
            else -> ThemeMode.System
        }
        set(value) = prefs.edit().putString(
            KEY_THEME,
            when (value) {
                ThemeMode.Light -> "light"
                ThemeMode.Dark -> "dark"
                ThemeMode.System -> "system"
            },
        ).apply()

    var autoCollapseCompletedTurns: Boolean
        get() = prefs.getBoolean(KEY_AUTO_COLLAPSE, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_COLLAPSE, value).apply()

    val hasRelayUrl: Boolean get() = relayUrl.isNotBlank()
    val isSignedIn: Boolean get() = token.isNotBlank()

    fun clearSession() {
        prefs.edit()
            .remove(KEY_TOKEN)
            .remove(KEY_DEVICE)
            .apply()
    }

    fun clearAll() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val KEY_URL = "relay_url"
        private const val KEY_TOKEN = "relay_token"
        private const val KEY_DEVICE = "relay_device_id"
        private const val KEY_THEME = "theme_mode"
        private const val KEY_AUTO_COLLAPSE = "auto_collapse_completed_turns"
    }
}

fun normalizeRelayUrl(raw: String): String {
    var value = raw.trim()
    if (value.isEmpty()) return ""
    if (!value.contains("://")) {
        value = "https://$value"
    }
    return value.trimEnd('/')
}
