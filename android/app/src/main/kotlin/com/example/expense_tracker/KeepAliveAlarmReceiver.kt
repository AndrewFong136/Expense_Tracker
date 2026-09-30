package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * Fired by the 4am HKT keep-alive alarm. Enqueues the component-toggle worker
 * and reschedules the next day's alarm.
 */
class KeepAliveAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "KeepAliveAlarmReceiver"
        const val UNIQUE_TOGGLE = "keep_alive_toggle"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        Log.d(TAG, "4am keep-alive alarm fired")
        val toggleWork = OneTimeWorkRequestBuilder<ServiceKeepAliveWorker>().build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            UNIQUE_TOGGLE,
            ExistingWorkPolicy.REPLACE,
            toggleWork
        )
        // Reschedule the next 4am HKT alarm.
        KeepAliveScheduler.scheduleNext(context)
    }
}
