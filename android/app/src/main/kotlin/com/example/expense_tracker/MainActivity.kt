package com.example.expense_tracker

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.core.graphics.createBitmap
import androidx.core.net.toUri
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {

    // Background executor for icon decoding / disk I/O so the platform thread
    // (and therefore Flutter's UI thread) is never blocked.
    private val iconExecutor: ExecutorService = Executors.newSingleThreadExecutor()

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

        apps.sortBy { it["appName"] }
        return apps
    }

    /**
     * Returns the PNG bytes for [packageName]'s launcher icon.
     *
     * Uses a disk cache (`cacheDir/<packageName>.png`) so an icon is only
     * decoded + compressed once; subsequent calls (including across launches)
     * just read the cached file. Returns null if the icon can't be resolved.
     */
    private fun getAppIconBytes(packageName: String): ByteArray? {
        val file = File(cacheDir, "$packageName.png")
        if (file.exists() && file.length() > 0) {
            return try {
                file.readBytes()
            } catch (_: Exception) {
                null
            }
        }
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = drawableToBitmap(drawable)
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            val bytes = out.toByteArray()
            // Persist to disk so the next call (and next launch) is a cheap read.
            file.writeBytes(bytes)
            bytes
        } catch (_: Exception) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable) {
            return drawable.bitmap
        }
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
        val bitmap = createBitmap(width, height)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun cacheAppList(apps: List<Map<String, String>>) {
        val gson = Gson()
        val json = gson.toJson(apps)
        getSharedPreferences("expense_tracker_settings", MODE_PRIVATE).edit {
            putString("cached_apps", json)
        }
    }

    private fun saveSettings(serviceEnabled: Boolean) {
        val prefs = getSharedPreferences("expense_tracker_settings", MODE_PRIVATE)
        prefs.edit {
            putBoolean("service_enabled", serviceEnabled)
        }
    }

    private val CHANNEL = "com.example.expense_tracker/settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        scheduleStatusSync()
        registerFcmToken()
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
                    iconExecutor.execute {
                        try {
                            val apps = getInstalledApps()
                            cacheAppList(apps)
                            result.success(apps)
                        } catch (e: Exception) {
                            result.error("GET_APPS_FAILED", "Failed to get installed apps.", e.message)
                        }
                    }
                }
                "getCachedApps" -> {
                    val prefs = getSharedPreferences("expense_tracker_settings", MODE_PRIVATE)
                    val cachedJson = prefs.getString("cached_apps", null)
                    if (cachedJson != null) {
                        val type = object : TypeToken<List<Map<String, String>>>() {}.type
                        val apps: List<Map<String, String>> = Gson().fromJson(cachedJson, type)
                        result.success(apps)
                    } else {
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    iconExecutor.execute {
                        result.success(getAppIconBytes(packageName))
                    }
                }
                "getAppIcons" -> {
                    val packageNames = call.argument<List<String>>("packageNames") ?: emptyList()
                    iconExecutor.execute {
                        val resultMap = mutableMapOf<String, ByteArray>()
                        for (pkg in packageNames) {
                            val bytes = getAppIconBytes(pkg)
                            if (bytes != null) resultMap[pkg] = bytes
                        }
                        result.success(resultMap)
                    }
                }
                "updateSettings" -> {
                    val serviceEnabled = call.argument<Boolean>("service_enabled") ?: false

                    saveSettings(serviceEnabled)

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
                "syncStatuses" -> {
                    val constraints = Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                    val oneShot = OneTimeWorkRequestBuilder<DeltaSyncWorker>()
                        .setConstraints(constraints)
                        .build()
                    WorkManager.getInstance(this).enqueueUniqueWork(
                        DeltaSyncWorker.UNIQUE_ONESHOT,
                        ExistingWorkPolicy.REPLACE,
                        oneShot
                    )
                    result.success(null)
                }
                "getStatuses" -> {
                    val statuses = StatusRepository.getStatuses(this)
                    val version = StatusRepository.getLastKnownVersion(this)
                    result.success(mapOf(
                        "statuses" to statuses,
                        "version" to version
                    ))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /** Schedule the 24h periodic delta pull + a one-time startup pull. */
    private fun scheduleStatusSync() {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val periodic = PeriodicWorkRequestBuilder<DeltaSyncWorker>(24, TimeUnit.HOURS)
            .setConstraints(constraints)
            .setInitialDelay(10, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            DeltaSyncWorker.UNIQUE_PERIODIC,
            ExistingPeriodicWorkPolicy.KEEP,
            periodic
        )
        val oneShot = OneTimeWorkRequestBuilder<DeltaSyncWorker>()
            .setConstraints(constraints)
            .setInitialDelay(2, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(this).enqueueUniqueWork(
            DeltaSyncWorker.UNIQUE_ONESHOT,
            ExistingWorkPolicy.KEEP,
            oneShot
        )
    }

    /** Best-effort FCM token registration */
    private fun registerFcmToken() {
        try {
            com.google.firebase.messaging.FirebaseMessaging.getInstance().token
                .addOnSuccessListener { token ->
                    FilterMessagingService.registerToken(this, token)
                }
                .addOnFailureListener { e ->
                    Log.w("MainActivity", "FCM token unavailable: ${e.message}")
                }
        } catch (e: Exception) {
            Log.w("MainActivity", "Firebase unavailable, skipping FCM token registration")
        }
    }
}
