package com.example.expense_tracker

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.google.gson.JsonParser
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Pulls package-status changes from the API (`GET /delta?version=N`) and
 * applies them to [StatusRepository]. Scheduled periodically (24h) and
 * on-demand (app start, manual refresh, FCM receipt via
 * [FilterMessagingService]). Acts as the single source of truth for the local
 * status map — FCM is only a wake-and-pull trigger.
 */
class DeltaSyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    override fun doWork(): Result {
        val ctx = applicationContext
        val sinceVersion = StatusRepository.getLastKnownVersion(ctx)
        val url = "${StatusRepository.API_BASE_URL}/delta?version=$sinceVersion"
        Log.d(TAG, "Pulling status delta since version $sinceVersion")

        return try {
            val response = client.newCall(Request.Builder().url(url).build()).execute()
            response.use { res ->
                if (!res.isSuccessful) {
                    Log.w(TAG, "Delta pull failed: HTTP ${res.code}")
                    return Result.retry()
                }
                val body = res.body?.string() ?: run {
                    Log.w(TAG, "Delta pull: empty body")
                    return Result.retry()
                }
                val root = JsonParser.parseString(body).asJsonObject

                val latestVersion = root.get("latestVersion")?.asString?.toLongOrNull()

                val changes = mutableListOf<Pair<String, String>>()
                root.getAsJsonArray("changes")?.forEach { el ->
                    val obj = el.asJsonObject
                    val pkg = obj.get("packageName")?.asString ?: return@forEach
                    val status = obj.get("status")?.asString ?: return@forEach
                    changes.add(pkg to status)
                }

                StatusRepository.applyChanges(ctx, changes)
                if (latestVersion != null) {
                    StatusRepository.setLastKnownVersion(ctx, latestVersion)
                }
                Log.d(TAG, "Delta applied: ${changes.size} change(s), now at version $latestVersion")
                Result.success()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Delta pull error", e)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "DeltaSyncWorker"
        const val UNIQUE_PERIODIC = "status_delta_periodic"
        const val UNIQUE_ONESHOT = "status_delta_oneshot"
    }
}
