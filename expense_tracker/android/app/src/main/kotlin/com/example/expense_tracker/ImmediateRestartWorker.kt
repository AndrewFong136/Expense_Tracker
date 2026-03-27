package com.example.expense_tracker

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.WorkerParameters
import androidx.work.Worker

class ImmediateRestartWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val intent = Intent(applicationContext, NotificationListenerService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(intent)
        } else {
            applicationContext.startService(intent)
        }

        Log.d("ImmediateRestartWorker", "Worker running")
        return Result.success()
    }
}