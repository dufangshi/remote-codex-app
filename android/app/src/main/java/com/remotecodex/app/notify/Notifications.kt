package com.remotecodex.app.notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.remotecodex.app.MainActivity
import com.remotecodex.app.R

object Notifications {
    const val CHANNEL_AGENT = "agent-runs"
    const val WATCH_ID = 41
    const val EXTRA_DEVICE_ID = "deviceId"
    const val EXTRA_THREAD_ID = "threadId"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_AGENT,
            context.getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.notification_channel_desc)
        }
        manager.createNotificationChannel(channel)
    }

    fun watchNotification(context: Context) =
        NotificationCompat.Builder(context, CHANNEL_AGENT)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(context.getString(R.string.watch_notification_title))
            .setContentText(context.getString(R.string.watch_notification_text))
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(openApp(context))
            .build()

    fun agentFinished(
        context: Context,
        deviceId: String,
        threadId: String,
        title: String,
        body: String,
        notificationId: Int,
    ) {
        ensureChannel(context)
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_DEVICE_ID, deviceId)
            putExtra(EXTRA_THREAD_ID, threadId)
            data = android.net.Uri.parse("remotecodex://devices/$deviceId/threads/$threadId")
        }
        val pending = PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_AGENT)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pending)
            .build()
        context.getSystemService(NotificationManager::class.java).notify(notificationId, notification)
    }

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
