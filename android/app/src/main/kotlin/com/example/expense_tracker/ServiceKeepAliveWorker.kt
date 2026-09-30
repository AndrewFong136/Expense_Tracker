package com.example.expense_tracker

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Toggles the NotificationListenerService component (disable -> enable) to force
 * a fresh system rebind. Triggered as a one-time worker by the 4am HKT
 * keep-alive alarm ([KeepAliveAlarmReceiver]). Runs on a WorkManager background
 * thread, so the [ListenerRebinder] sleep is safe here.
 */
class ServiceKeepAliveWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        return try {
            ListenerRebinder.toggle(applicationContext)
            Log.d("ServiceKeepAliveWorker", "Component toggle completed")
            Result.success()
        } catch (e: Exception) {
            Log.e("ServiceKeepAliveWorker", "Component toggle failed", e)
            Result.retry()
        }
    }
}
