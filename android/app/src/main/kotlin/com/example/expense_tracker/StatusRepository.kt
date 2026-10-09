package com.example.expense_tracker

import android.content.Context
import androidx.core.content.edit
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.util.UUID

/**
 * Owns the local copy of package classification statuses synced from the API
 * via [DeltaSyncWorker], plus the monotonic last_known_version cursor and a
 * per-install user_id used for FCM token registration.
 *
 * All values live in the `expense_tracker_settings` prefs file so
 * [NotificationListenerService] can read the status map directly when
 * filtering incoming notifications, and so the Flutter UI can read it via
 * the platform channel without a separate prefs file.
 */
object StatusRepository {

    private const val PREFS = "expense_tracker_settings"
    private const val KEY_VERSION = "last_known_version"
    private const val KEY_STATUSES = "package_statuses"
    private const val KEY_USER_ID = "user_id"

    const val API_BASE_URL = "http://192.168.68.53:3001"

    const val STATUS_FINANCIAL = "FINANCIAL"
    const val STATUS_NON_FINANCIAL = "NON_FINANCIAL"
    const val STATUS_UNKNOWN = "UNKNOWN"

    private val gson = Gson()

    fun getLastKnownVersion(context: Context): Long =
        prefs(context).getLong(KEY_VERSION, 0L)

    fun setLastKnownVersion(context: Context, version: Long) {
        prefs(context).edit { putLong(KEY_VERSION, version) }
    }

    /** Returns the package -> status map (FINANCIAL / NON_FINANCIAL / UNKNOWN). */
    fun getStatuses(context: Context): Map<String, String> {
        val json = prefs(context).getString(KEY_STATUSES, null) ?: return emptyMap()
        return try {
            val type = object : TypeToken<Map<String, String>>() {}.type
            gson.fromJson<Map<String, String>>(json, type) ?: emptyMap()
        } catch (_: Exception) {
            emptyMap()
        }
    }

    /** Apply a batch of (packageName -> status) changes atomically. */
    fun applyChanges(context: Context, changes: List<Pair<String, String>>) {
        if (changes.isEmpty()) return
        val current = getStatuses(context).toMutableMap()
        for ((pkg, status) in changes) {
            current[pkg] = status
        }
        prefs(context).edit { putString(KEY_STATUSES, gson.toJson(current)) }
    }

    /**
     * Per-install UUID, generated on first access. Used as the opaque user_id
     * for FCM token registration until real auth exists.
     */
    fun getUserId(context: Context): String {
        val p = prefs(context)
        p.getString(KEY_USER_ID, null)?.let { return it }
        val id = UUID.randomUUID().toString()
        p.edit { putString(KEY_USER_ID, id) }
        return id
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
