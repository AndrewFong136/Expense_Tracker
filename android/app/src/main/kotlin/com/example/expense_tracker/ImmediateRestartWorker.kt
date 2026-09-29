package com.example.expense_tracker

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * One-shot nudge that asks the system to rebind the NotificationListenerService
 * immediately (e.g. from the "rebindListener" method channel). Calls
 * requestRebind instead of startForegroundService — there is no FGS.
 */
class ImmediateRestartWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            val cn = ComponentName(applicationContext, NotificationListenerService::class.java)
            android.service.notification.NotificationListenerService.requestRebind(cn)
        }
        Log.d("ImmediateRestartWorker", "Worker running (requestRebind)")
        return Result.success()
    }
}
