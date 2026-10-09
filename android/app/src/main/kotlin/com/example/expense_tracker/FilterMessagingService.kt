package com.example.expense_tracker

import android.content.Context
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * Receives FCM data messages pushed by the API on package-status changes.
 * Acts as a wake-and-pull trigger: on any message, enqueue a one-time
 * [DeltaSyncWorker] to re-pull the delta. The payload is never trusted to be
 * complete — the worker is the source of truth.
 *
 * Also handles FCM token (re)registration via `POST /devices/token`.
 */
class FilterMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        Log.d(TAG, "FCM received from ${message.from}, triggering delta pull")
        val request = OneTimeWorkRequestBuilder<DeltaSyncWorker>().build()
        WorkManager.getInstance(applicationContext)
            .enqueueUniqueWork(
                DeltaSyncWorker.UNIQUE_ONESHOT,
                ExistingWorkPolicy.REPLACE,
                request
            )
    }

    override fun onNewToken(token: String) {
        Log.d(TAG, "FCM token refreshed, registering with API")
        registerToken(applicationContext, token)
    }

    companion object {
        private const val TAG = "FilterMessagingService"

        private val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .build()

        /**
         * Register (or refresh) this device's FCM token with the API.
         * Best-effort on a background thread; failures are logged, not fatal.
         */
        fun registerToken(context: Context, token: String) {
            val userId = StatusRepository.getUserId(context)
            val payload = """
                {"userId":"$userId","fcmToken":"$token","platform":"android"}
            """.trimIndent()
            val body = payload.toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull())
            val request = Request.Builder()
                .url("${StatusRepository.API_BASE_URL}/devices/token")
                .post(body)
                .build()
            Thread {
                try {
                    client.newCall(request).execute().use { resp ->
                        Log.d(TAG, "Token registration response: ${resp.code}")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Token registration failed", e)
                }
            }.start()
        }
    }
}
