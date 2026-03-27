package com.example.expense_tracker

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

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

            apps.add(mapOf(
                "packageName" to packageName,
                "appName" to appName,
            ))
        }

        val prefs = getSharedPreferences("expense_tracker_settings", MODE_PRIVATE)
        val selectedSet = prefs.getStringSet("selected_apps", emptySet()) ?: emptySet()

        apps.sortWith(compareByDescending<Map<String, String>> { selectedSet.contains(it["packageName"]) }.thenBy{ it["appName"] })
        return apps
    }

    private fun getAppIcon(packageName: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = (drawable as BitmapDrawable).bitmap
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (_: Exception) {
            null
        }
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
                "isAppNotificationEnabled" -> {
                    val enabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
                    result.success(enabled)
                }
                "isNotificationListenerAccessEnabled" -> {
                    val cn = ComponentName(this, NotificationListenerService::class.java)
                    val enabledListeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    val isEnabled = enabledListeners?.contains(cn.flattenToString()) == true
                    result.success(isEnabled)
                }
                "isLocationAlwaysEnabled" -> {
                    val enabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
                    } else {
                        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    }
                    result.success(enabled)
                }
                "requestNotificationListenerAccess" -> {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    startActivity(intent)
                    result.success(null)
                }
                "requestLocationAccess" -> {
                    val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                    startActivity(intent)
                    result.success(null)
                }
                "openAppNotificationSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = "package:$packageName".toUri()
                        }
                    }
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
                "getAppIcon" -> {
                    val packageName = call.argument<String>(packageName) ?: ""
                    val iconBytes = getAppIcon(packageName)
                    result.success(iconBytes)
                }
                "updateSettings" -> {
                    val serviceEnabled = call.argument<Boolean>("service_enabled") ?: false
                    val webhookUrl = call.argument<String>("webhook_url") ?: ""
                    val selectedApps = call.argument<Map<String, Boolean>>("selected_apps") ?: emptyMap()
                    
                    saveSettings(serviceEnabled, webhookUrl, selectedApps)

                    val action = if (serviceEnabled) {
                        NotificationListenerService.ACTION_SHOW_NOTIFICATION
                    } else {
                        NotificationListenerService.ACTION_HIDE_NOTIFICATION
                    }
                    sendBroadcast(Intent(action).setPackage(packageName))

                    if (serviceEnabled) {
                        val constraints = Constraints.Builder()
                            .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                            .build()
                        val workRequest = PeriodicWorkRequestBuilder<ServiceKeepAliveWorker>(15, TimeUnit.MINUTES)
                            .setConstraints(constraints)
                            .setInitialDelay(1, TimeUnit.MINUTES)
                            .build()
                        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
                            "service_keep_alive",
                            ExistingPeriodicWorkPolicy.KEEP,
                            workRequest
                        )
                    } else {
                        WorkManager.getInstance(this).cancelUniqueWork("service_keep_alive")
                    }

                    result.success(null)
                }
                "rebindListener" -> {
                    val workRequest = OneTimeWorkRequestBuilder<ImmediateRestartWorker>()
                        .setInitialDelay(1, TimeUnit.SECONDS)
                        .build()
                    WorkManager.getInstance(this).enqueueUniqueWork(
                        "immediate_restart",
                        ExistingWorkPolicy.KEEP,
                        workRequest
                    )

                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
