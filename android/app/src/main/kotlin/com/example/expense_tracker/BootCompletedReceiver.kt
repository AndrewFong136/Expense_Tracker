package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * AlarmManager alarms are cleared on reboot. After boot, re-schedule the 4am
 * keep-alive alarm if the listener service is enabled.
 */
class BootCompletedReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootCompletedReceiver"
        private const val PREFS = "expense_tracker_settings"
        private const val KEY_SERVICE_ENABLED = "service_enabled"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val serviceEnabled = prefs.getBoolean(KEY_SERVICE_ENABLED, false)
        Log.d(TAG, "Boot completed; service_enabled=$serviceEnabled")
        if (serviceEnabled) {
            KeepAliveScheduler.scheduleNext(context)
        }
    }
}
