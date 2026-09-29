package com.example.expense_tracker

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Periodic nudge that asks the system to rebind the NotificationListenerService.
 * The listener is purely system-bound (no foreground service); this worker
 * keeps the binding healthy instead of restarting a foreground service.
 */
class ServiceKeepAliveWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            val cn = ComponentName(applicationContext, NotificationListenerService::class.java)
            android.service.notification.NotificationListenerService.requestRebind(cn)
        }
        Log.d("ServiceKeepAliveWorker", "Worker running (requestRebind)")
        return Result.success()
    }
}
