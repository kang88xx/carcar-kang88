package com.kang88.carcar

import android.app.Notification
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FamilyMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        synchronized(FamilyPushState) {
            // The server sends data-only messages. Notification payloads would let
            // the SDK bypass the local opt-out gate when the app is in background.
            if (message.data["kind"] != "parking_updated" || !FamilyPushState.enabled(this) || !FamilyPushState.permissionGranted(this)) return
            FamilyPushState.createChannel(this)
            val open = PendingIntent.getActivity(this, FamilyPushState.NOTIFICATION_ID,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, FamilyPushState.CHANNEL) else Notification.Builder(this)
            builder.setSmallIcon(R.drawable.ic_parking_notification)
                .setContentTitle("새 주차 기록이 있어요")
                .setContentText("차곡에서 가족의 최신 주차 위치를 확인해 주세요.")
                .setContentIntent(open).setAutoCancel(true)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setOnlyAlertOnce(false)
            try { FamilyPushState.manager(this).notify(FamilyPushState.NOTIFICATION_ID, builder.build()) }
            catch (_: SecurityException) { FamilyPushState.cancelNotifications(this) }
        }
    }

    override fun onNewToken(token: String) {
        // Never persist/log tokens or bind one to a stale account. The app gets
        // the current SDK token on every opted-in foreground refresh.
        if (!FamilyPushState.enabled(this)) {
            FamilyPushState.messaging(this)?.let { FamilyPushState.discardLateToken(this, it) }
        }
    }
}
