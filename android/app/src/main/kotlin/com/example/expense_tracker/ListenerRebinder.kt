package com.example.expense_tracker

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log

/**
 * Forces the system to rebind the [NotificationListenerService] by toggling the
 * component enabled state (disable -> brief pause -> enable). Used ONLY by the
 * daily 4am keep-alive; every other rebind path still uses
 * [android.service.notification.NotificationListenerService.requestRebind].
 *
 * Must be called off the main thread — it sleeps briefly so the system can
 * process the disable before the component is re-enabled.
 */
object ListenerRebinder {
    private const val TAG = "ListenerRebinder"
    private const val TOGGLE_PAUSE_MS = 1500L

    fun toggle(context: Context) {
        val pm = context.packageManager
        val component = ComponentName(context, NotificationListenerService::class.java)
        try {
            pm.setComponentEnabledSetting(
                component,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
            Thread.sleep(TOGGLE_PAUSE_MS)
            pm.setComponentEnabledSetting(
                component,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            Log.d(TAG, "Component toggled (disable -> enable)")
        } catch (e: Exception) {
            Log.e(TAG, "Component toggle failed", e)
        }
    }
}
