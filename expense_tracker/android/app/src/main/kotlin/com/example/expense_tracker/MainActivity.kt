package com.example.expense_tracker

import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.provider.Settings
import android.util.Base64
import java.io.ByteArrayOutputStream
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale

class MainActivity : FlutterActivity() {
    private fun getInstalledApps(): List<Map<String, String>> {
        val apps = mutableListOf<Map<String, String>>()
        val packageManager = this.packageManager

        val intent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val packages = packageManager.queryIntentActivities(intent, 0)

        for (resolveInfo in packages) {
            val appInfo = resolveInfo.activityInfo.applicationInfo

            val appName = packageManager.getApplicationLabel(appInfo).toString()
            val packageName = appInfo.packageName

            val drawable = packageManager.getApplicationIcon(appInfo)
            val bitmap = drawableToBitmap(drawable)
            val resizedBitmap = bitmap.scale(64, 64, true)
            val appIcon = bitmapToBase64(resizedBitmap)

            apps.add(mapOf(
                "packageName" to packageName,
                "appName" to appName,
                "appIcon" to appIcon
            ))
        }

        apps.sortBy { it["appName"] }
        return apps
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable) {
            return drawable.bitmap
        }

        val width = drawable.intrinsicWidth.coerceAtLeast(1)
        val height = drawable.intrinsicHeight.coerceAtLeast(1)
        val bitmap = createBitmap(width, height)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, width, height)
        drawable.draw(canvas)

        return bitmap
    }

    private fun bitmapToBase64(bitmap: Bitmap): String {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        val byteArray = stream.toByteArray()
        return Base64.encodeToString(byteArray, Base64.NO_WRAP)
    }

    private fun saveSettings(serviceEnabled: Boolean, webhookUrl: String, selectedApps: Map<String, Boolean>) {
        val prefs = getSharedPreferences("expense_tracker_settings", MODE_PRIVATE)
        with (prefs.edit()) {
            putBoolean("service_enabled", serviceEnabled)
            putString("webhook_url", webhookUrl)

            val selectedAppsList = HashSet<String>()
            selectedApps.forEach { (app, enabled) ->
                if (enabled) {
                    selectedAppsList.add(app)
                }
            }
            putStringSet("selected_apps", selectedAppsList)

            apply()
        }
    }

    private val CHANNEL = "com.example.expense_tracker/settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerAccessEnabled" -> {
                    val cn = ComponentName(this, NotificationListenerService::class.java)
                    val enabledListeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    val isEnabled = enabledListeners?.contains(cn.flattenToString()) == true
                    result.success(isEnabled)
                }
                "requestNotificationListenerAccess" -> {
                    val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                    startActivity(intent)
                    result.success(null)
                }
                "getInstalledApps" -> {
                    try {
                        val apps = getInstalledApps()
                        result.success(apps)
                    } catch (e: Exception) {
                        result.error("GET_APPS_FAILED", "Failed to get installed apps.", e.message)
                    }
                }
                "updateSettings" -> {
                    val serviceEnabled = call.argument<Boolean>("service_enabled") ?: false
                    val webhookUrl = call.argument<String>("webhook_url") ?: ""
                    val selectedApps = call.argument<Map<String, Boolean>>("selected_apps") ?: emptyMap()
                    
                    saveSettings(serviceEnabled, webhookUrl, selectedApps)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
