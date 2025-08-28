package com.example.expense_tracker

import android.Manifest
import android.R
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.content.Intent
import androidx.core.content.ContextCompat
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission

class NotificationListenerService : NotificationListenerService() {
    private var TAG = "Notification Listener"

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "Listener connected and ready to receive notifications")
    }

    @RequiresPermission(Manifest.permission.POST_NOTIFICATIONS)
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences("expense_tracker_settings", MODE_PRIVATE)
        val serviceEnabled = prefs.getBoolean("service_enabled", false)

        Log.d(TAG, "Service Enabled: $serviceEnabled")

        if(!serviceEnabled) return

        val selectedApps = prefs.getStringSet("selected_apps", emptySet()) ?: emptySet()

        val packageName = sbn.packageName

        Log.d(TAG, "Notification received from: $packageName")

        if (!selectedApps.contains(packageName)) return

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: "Unknown"
        val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                    ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                    ?: "No content"


        val overlayIntent = Intent(this, InteractiveOverlayService::class.java).apply {
            putExtra("notification_title", title)
            putExtra("notification_text", text)
            putExtra("source_package", packageName)
        }

        ContextCompat.startForegroundService(this, overlayIntent)
    }
}