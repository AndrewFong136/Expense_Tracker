package com.example.expense_tracker

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.Calendar
import java.util.TimeZone

/**
 * Schedules the precise 4am HKT keep-alive alarm. The alarm fires
 * [KeepAliveAlarmReceiver], which enqueues the component-toggle worker and
 * reschedules the next day's alarm.
 *
 * AlarmManager alarms are wiped on reboot, so [BootCompletedReceiver]
 * re-schedules after boot.
 *
 * HKT = Asia/Hong_Kong (UTC+8, no DST).
 */
object KeepAliveScheduler {
    private const val TAG = "KeepAliveScheduler"
    private const val ALARM_REQUEST_CODE = 0
    private const val HKT_ZONE_ID = "Asia/Hong_Kong"

    fun scheduleNext(context: Context) {
        val triggerAt = System.currentTimeMillis() + millisUntilNext4amHkt()
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = buildPendingIntent(context)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                // User revoked SCHEDULE_EXACT_ALARM on API 31+ — best-effort inexact.
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                Log.w(TAG, "Exact alarms not allowed; scheduled inexact 4am keep-alive")
            } else {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                Log.d(TAG, "Scheduled exact 4am HKT keep-alive")
            }
        } catch (e: SecurityException) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            Log.w(TAG, "SecurityException on exact alarm; fell back to inexact", e)
        }
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(buildPendingIntent(context))
        Log.d(TAG, "Cancelled 4am keep-alive alarm")
    }

    private fun buildPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, KeepAliveAlarmReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /**
     * Milliseconds from now until the next 4am Asia/Hong_Kong. Uses
     * java.util.Calendar (safe on API 24, unlike java.time without desugaring).
     */
    private fun millisUntilNext4amHkt(): Long {
        val hkTz = TimeZone.getTimeZone(HKT_ZONE_ID)
        val now = Calendar.getInstance(hkTz)
        val next = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 4)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now.timeInMillis) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        return next.timeInMillis - now.timeInMillis
    }
}
