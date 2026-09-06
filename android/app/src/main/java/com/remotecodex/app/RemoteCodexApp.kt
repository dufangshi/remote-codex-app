package com.remotecodex.app

import android.app.Application
import com.remotecodex.app.notify.Notifications

class RemoteCodexApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannel(this)
    }
}
