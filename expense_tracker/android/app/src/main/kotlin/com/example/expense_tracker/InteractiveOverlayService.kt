package com.example.expense_tracker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ContentValues.TAG
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okhttp3.RequestBody.Companion.toRequestBody
import okio.IOException
import org.json.JSONObject

class InteractiveOverlayService : Service() {
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private val client = OkHttpClient()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundService()
        showOverlay(intent)
        return START_STICKY
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun startForegroundService() {
        val channelId = "overlay_channel"
        val name = "Overlay Service"
        val channel = NotificationChannel(channelId, name, NotificationManager.IMPORTANCE_LOW)
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Notification Listener")
            .setContentText("Listening for notifications...")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()

        startForeground(101, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun showOverlay(intent: Intent?) {
        windowManager = getSystemService(WindowManager::class.java)

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        )

        layoutParams.gravity = Gravity.CENTER

        val inflater = getSystemService(android.view.LayoutInflater::class.java)
        overlayView = inflater.inflate(R.layout.interactive_overlay, null)

        val titleText = overlayView?.findViewById<TextView>(R.id.notificationTitle)
        val titleMessage = overlayView?.findViewById<TextView>(R.id.notificationText)
        val credit = overlayView?.findViewById<GridLayout>(R.id.credit)
        val debit = overlayView?.findViewById<LinearLayout>(R.id.debit)

        val title = intent?.getStringExtra("notification_title") ?: "New Notification"
        val message = intent?.getStringExtra("notification_text") ?: ""
        val webhookUrl = intent?.getStringExtra("webhook_url") ?: ""

        titleText?.text = title
        titleMessage?.text = message

        credit?.let { gridLayout ->
            for (i in 0 until gridLayout.childCount) {
                val button = gridLayout.getChildAt(i) as? Button

                button?.setOnClickListener {
                    val buttonText = button.text.toString()
                    sendToWebhook(title, message, buttonText, webhookUrl)
                    removeOverlay()
                }
            }
        }

        debit?.let { gridLayout ->
            for (i in 0 until gridLayout.childCount) {
                val button = gridLayout.getChildAt(i) as? Button

                button?.setOnClickListener {
                    val buttonText = button.text.toString()
                    sendToWebhook(title, message, buttonText, webhookUrl)
                    removeOverlay()
                }
            }
        }

        windowManager?.addView(overlayView, layoutParams)
    }

    private fun sendToWebhook(title: String, message: String, input: String, url: String) {
        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()

        val escapedTitle = title.replace("\"", "\\\"")
        val escapedMessage = message.replace("\"", "\\\"")
        val escapedInput = input.replace("\"", "\\\"")

        val jsonPayload = """
        {
            "title": "$escapedTitle",
            "message": "$escapedMessage",
            "type": "$escapedInput",
            "timestamp": "${System.currentTimeMillis()}"
        }
        """.trimIndent()

        val body = jsonPayload.toRequestBody(mediaType)

        val request = Request.Builder()
            .url(url)
            .post(body)
            .build()

        client.newCall(request).enqueue(object: Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "Webhook request failed: ${e.message}")
                e.printStackTrace()
            }

            override fun onResponse(call: Call, response: Response) {
                Log.d(TAG, "Webhook response: ${response.code}")

                val responseBody = response.body.string()
                Log.d(TAG, "Response body: $responseBody")
                response.close()
            }
        })
    }
    private fun removeOverlay() {

        if (overlayView != null) {
            windowManager?.removeView(overlayView)
            overlayView = null
        }

        stopSelf()
    }

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }
}