package com.example.expense_tracker

import android.Manifest
import android.app.Notification
import android.content.ComponentName
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission
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
import org.json.JSONObject
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.coroutines.resume
import kotlin.time.Duration.Companion.milliseconds

class NotificationListenerService : NotificationListenerService() {
    private val client = OkHttpClient()
    private lateinit var locationManager: LocationManager
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var TAG = "Notification Listener"

    // Cached package -> status map, refreshed at most once per minute so the
    // delta sync worker's updates take effect without the system re-binding.
    @Volatile private var statusCache: Map<String, String> = emptyMap()
    @Volatile private var statusCacheAtMs: Long = 0L

    companion object {
        const val WEBHOOK_URL = "http://192.168.68.53:5678/webhook/expense_tracker"
    }

    /**
     * Re-request the system's notification-listener binding. No-op below API 25
     * where requestRebind isn't available. Called from [onListenerDisconnected]
     * to recover a dropped binding.
     */
    private fun requestListenerRebind() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            requestRebind(ComponentName(this, NotificationListenerService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created (system-bound)")
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
        requestListenerRebind();
    }

    /**
     * Returns the cached classification status for [packageName], reloading
     * the map from prefs at most once per minute so [DeltaSyncWorker] updates
     * propagate. Defaults to UNKNOWN for packages not yet classified (so they
     * keep being observed/forwarded for learning).
     */
    private fun statusFor(packageName: String): String {
        val now = System.currentTimeMillis()
        if (now - statusCacheAtMs > 60_000L) {
            statusCache = StatusRepository.getStatuses(this)
            statusCacheAtMs = now
        }
        return statusCache[packageName] ?: StatusRepository.STATUS_UNKNOWN
    }

    @RequiresApi(Build.VERSION_CODES.R)
    @RequiresPermission(Manifest.permission.POST_NOTIFICATIONS)
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName

        Log.d(TAG, "Notification received from: $packageName")

        // Never process our own notifications — forwarding them would create a
        // feedback loop.
        if (packageName == this.packageName) return

        // Pure-status filter: forward FINANCIAL + UNKNOWN (so unclassified apps
        // keep being observed for learning); skip confirmed NON_FINANCIAL.
        val status = statusFor(packageName)
        if (status == StatusRepository.STATUS_NON_FINANCIAL) {
            Log.d(TAG, "Skipping $packageName (status=$status)")
            return
        }

        val extras = sbn.notification.extras
        val userId = StatusRepository.getUserId(this)
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                    ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                    ?: ""
        val appInfo = packageManager.getApplicationInfo(packageName, 0)
        val appName = packageManager.getApplicationLabel(appInfo).toString()

        serviceScope.launch {
            val location = if (status == StatusRepository.STATUS_FINANCIAL) requestExactLocation() else null
            val lat = location?.first
            val lon = location?.second
            sendToWebhook(userId, title, text, packageName, appName, lat, lon)
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
        return withTimeoutOrNull(5000.milliseconds) {
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

    @RequiresApi(Build.VERSION_CODES.O)
    private fun sendToWebhook(userId: String, title: String, message: String, packageName: String, appName: String, lat: Double?, lon: Double?) {
        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()

        val currentDateTime = OffsetDateTime.now(ZoneOffset.UTC)
            .truncatedTo(ChronoUnit.SECONDS)
            .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)

        val payload = JSONObject().apply {
            put("userId", userId)
            put("package", packageName)
            put("app", appName)
            put("title", title)
            put("message", message)
            put("timestamp", currentDateTime)
            put("location", "$lat,$lon")
        }

        val body = payload.toString().toRequestBody(mediaType)

        val request = Request.Builder()
            .url(WEBHOOK_URL)
            .post(body)
            .build()

        client.newCall(request).enqueue(object: Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "Webhook request failed: ${e.message}")
                e.printStackTrace()
            }

            override fun onResponse(call: Call, response: Response) {
                Log.d(TAG, "Webhook response: ${response.code}")

                val responseBody = response.body.string()
                Log.d(TAG, "Response body: $responseBody")
                response.close()
            }
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
    }
}
