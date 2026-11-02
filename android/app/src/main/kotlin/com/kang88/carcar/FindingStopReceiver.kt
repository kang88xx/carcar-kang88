package com.kang88.carcar

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class FindingStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(MainActivity.FINDING_ID)
    }
}
