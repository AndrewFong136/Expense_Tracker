package com.example.expense_tracker

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.coroutines.resume

class NotificationListenerService : NotificationListenerService() {
    private val client = OkHttpClient()
    private lateinit var locationManager: LocationManager
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var TAG = "Notification Listener"

    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "notification_listener_channel"
    private val CHANNEL_NAME = "Notification Listener Service"

    companion object {
        const val ACTION_SHOW_NOTIFICATION = "com.example.expense_tracker.SHOW_NOTIFICATION"
        const val ACTION_HIDE_NOTIFICATION = "com.example.expense_tracker.HIDE_NOTIFICATION"
        const val ACTION_DISMISS_NOTIFICATION = "com.example.expense_tracker.DISMISS_NOTIFICATION"
    }

    /**
     * Re-request the system's notification-listener binding. No-op below API 25
     * where [requestRebind] isn't available. Called from [onCreate],
     * [onListenerDisconnected] and [onTimeout] to recover a dropped binding.
     */
    private fun requestListenerRebind() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            requestRebind(ComponentName(this, NotificationListenerService::class.java))
        }
    }

    /**
     * Start (or update) the foreground notification, declaring the specialUse
     * FGS type on Android 14+ so the system associates the correct
     * (non-time-limited) type with the running service.
     */
    private fun startForegroundWithType(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_SHOW_NOTIFICATION -> {
                    startForegroundWithType(buildEnabledNotification())
                }
                ACTION_HIDE_NOTIFICATION -> {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                }
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForegroundWithType(buildEnabledNotification())

        Handler(Looper.getMainLooper()).postDelayed({
            requestListenerRebind()
        }, 1000)

        val filter = IntentFilter(ACTION_SHOW_NOTIFICATION).apply { addAction(ACTION_HIDE_NOTIFICATION) }
        registerReceiver(notificationReceiver, filter, RECEIVER_NOT_EXPORTED)
        Log.d(TAG, "Service created and running in foreground")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android 14+ lets the user dismiss even an ongoing FGS notification.
        // When that happens the deleteIntent attached in buildEnabledNotification
        // fires here; re-create the notification so it persists. Guarded by the
        // service_enabled pref so we never fight the user's "disable" toggle.
        if (intent?.action == ACTION_DISMISS_NOTIFICATION) {
            val enabled = getSharedPreferences("expense_tracker_settings", MODE_PRIVATE)
                .getBoolean("service_enabled", false)
            if (enabled) {
                startForegroundWithType(buildEnabledNotification())
            }
            return START_STICKY
        }

        if (intent?.getBooleanExtra("STOP", false) == true) {
            Log.d(TAG, "Stop command received")
            stopSelf()
            return START_NOT_STICKY
        }
        super.onStartCommand(intent, flags, startId)
        return START_STICKY
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "Listener connected and ready to receive notifications")
    }

    override fun onListenerDisconnected() {
        // The system dropped the listener binding (e.g. under memory pressure or
        // after a battery-saver event). Ask to be re-bound immediately instead of
        // waiting for the next notification or the 15-min keep-alive worker.
        super.onListenerDisconnected()
        Log.d(TAG, "Listener disconnected — requesting rebind")
        requestListenerRebind()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 14+ FGS timeout hook. Shouldn't fire for the specialUse type,
        // but handled defensively: refresh the listener binding so the system
        // reconnects us; the keep-alive worker will re-post the foreground
        // notification on its next cycle.
        super.onTimeout(startId, fgsType)
        Log.d(TAG, "onTimeout(startId=$startId, fgsType=$fgsType) — refreshing listener binding")
        requestListenerRebind()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Expense tracker listening for transactions"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
        Log.d(TAG, "Notification channel created")
    }

    private fun buildEnabledNotification(): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // On Android 14+ an ongoing FGS notification can be dismissed by the
        // user. Attach a deleteIntent routed back to this service so onStartCommand
        // re-posts the notification, keeping the listener persistent.
        val dismissIntent = Intent(this, NotificationListenerService::class.java).apply {
            action = ACTION_DISMISS_NOTIFICATION
        }
        val dismissPendingIntent = PendingIntent.getService(
            this,
            0,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Expense Tracker")
            .setContentText("Notification listener enabled")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setDeleteIntent(dismissPendingIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setColor(0xFFFB8C00.toInt())   // brand orange (#FB8C00)
            .setColorized(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()

        notification.flags = notification.flags or Notification.FLAG_NO_CLEAR or Notification.FLAG_ONGOING_EVENT
        return notification
    }

    @RequiresApi(Build.VERSION_CODES.R)
    @RequiresPermission(Manifest.permission.POST_NOTIFICATIONS)
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences("expense_tracker_settings", MODE_PRIVATE)
        val serviceEnabled = prefs.getBoolean("service_enabled", false)

        Log.d(TAG, "Service Enabled: $serviceEnabled")

        if(!serviceEnabled) {
            stopSelf()
            return
        }

        val selectedApps = prefs.getStringSet("selected_apps", emptySet()) ?: emptySet()

        val packageName = sbn.packageName

        Log.d(TAG, "Notification received from: $packageName")

        if (!selectedApps.contains(packageName)) return

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                    ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                    ?: ""
        val webhookUrl = prefs.getString("webhook_url", "") ?: ""
        val appInfo = packageManager.getApplicationInfo(packageName, 0)
        val appName = packageManager.getApplicationLabel(appInfo).toString()

        serviceScope.launch {
            val location = requestExactLocation()
            val lat = location?.first
            val lon = location?.second
            sendToWebhook(title, text, appName, webhookUrl, lat, lon)
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private suspend fun requestExactLocation(): Pair<Double, Double>? {
        if (ContextCompat.checkSelfPermission(this@NotificationListenerService, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            Log.d(TAG, "Location permission not granted")
            return null
        }
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager

        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        for (provider in providers) {
            try {
                val lastLocation = locationManager.getLastKnownLocation(provider)
                if (lastLocation != null && System.currentTimeMillis() - lastLocation.time < 120000) {
                    Log.d(TAG, "Using recent last known location from $provider")
                    return Pair(lastLocation.latitude, lastLocation.longitude)
                }
            } catch (_: SecurityException) {
                null
            }
        }

        val fusedClient = LocationServices.getFusedLocationProviderClient(this)
        return withTimeoutOrNull(5000) {
            suspendCancellableCoroutine { continuation ->
                val cancellationTokenSource = com.google.android.gms.tasks.CancellationTokenSource()

                fusedClient.getCurrentLocation(
                    Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                    cancellationTokenSource.token
                ).addOnSuccessListener { location ->
                    if (location != null && continuation.isActive) {
                        Log.d(TAG, "Location received: $location")
                        continuation.resume(location)
                    } else if (continuation.isActive) {
                        continuation.resume(null)
                    }
                }.addOnFailureListener { e ->
                    Log.e(TAG, "Location request failed")
                    if (continuation.isActive) continuation.resume(null)
                }

                continuation.invokeOnCancellation {
                    Log.d(TAG, "Location request cancelled")
                    cancellationTokenSource.cancel()
                }
            }
        }?.let { Pair(it.latitude, it.longitude) }
    }

    private fun sendToWebhook(title: String, message: String, appName: String, url: String, lat: Double?, lon: Double?) {
        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()

        val escapedTitle = title.replace("\"", "\\\"")
        val escapedMessage = message.replace("\"", "\\\"")

        val currentDate = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

        val jsonPayload = """
        {
            "app": "$appName",
            "title": "$escapedTitle",
            "message": "$escapedMessage",
            "timestamp": "$currentDate",
            "location": "$lat,$lon"
        }
        """.trimIndent()

        val body = jsonPayload.toRequestBody(mediaType)

        val request = Request.Builder()
            .url(url)
            .post(body)
            .build()

        client.newCall(request).enqueue(object: Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(ContentValues.TAG, "Webhook request failed: ${e.message}")
                e.printStackTrace()
            }

            override fun onResponse(call: Call, response: Response) {
                Log.d(ContentValues.TAG, "Webhook response: ${response.code}")

                val responseBody = response.body.string()
                Log.d(ContentValues.TAG, "Response body: $responseBody")
                response.close()
            }
        })
    }
}
