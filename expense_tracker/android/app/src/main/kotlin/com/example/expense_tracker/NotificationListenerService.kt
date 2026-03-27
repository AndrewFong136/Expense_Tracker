package com.example.expense_tracker

import android.Manifest
import android.app.AlarmManager
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
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
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
import java.util.concurrent.TimeUnit
import java.util.function.Consumer
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
    }

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_SHOW_NOTIFICATION -> {
                    startForeground(NOTIFICATION_ID, buildEnabledNotification())
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
        startForeground(NOTIFICATION_ID, buildEnabledNotification())

        Handler(Looper.getMainLooper()).postDelayed({
            val cn = ComponentName(this, com.example.expense_tracker.NotificationListenerService::class.java)
            requestRebind(cn)
        }, 1000)

        val filter = IntentFilter(ACTION_SHOW_NOTIFICATION).apply { addAction(ACTION_HIDE_NOTIFICATION) }
        registerReceiver(notificationReceiver, filter, RECEIVER_NOT_EXPORTED)
        Log.d(TAG, "Service created and running in foreground")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
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

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Expense Tracker")
            .setContentText("Notification listener enabled")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
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
            } catch (e: SecurityException) { }
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