package com.kang88.carcar

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.MethodChannel

object FamilyPushState {
    const val CHANNEL = "carcar_family"
    const val NOTIFICATION_ID = 411
    val gate = PushRegistrationGate()
    fun preferences(context: Context) = context.getSharedPreferences("carcar_family_push", Context.MODE_PRIVATE)
    fun enabled(context: Context) = preferences(context).getBoolean("enabled", false)
    @Synchronized fun setEnabled(context: Context, enabled: Boolean): Boolean = preferences(context).edit().putBoolean("enabled", enabled).commit()
    fun manager(context: Context) = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun messaging(context: Context): FirebaseMessaging? = try {
        val app = FirebaseApp.getApps(context).firstOrNull { it.name == FirebaseApp.DEFAULT_APP_NAME }
            ?: FirebaseApp.initializeApp(context)
        if (app == null) null else FirebaseMessaging.getInstance().also {
            // Remains false after opt-in too. Foreground refresh explicitly obtains
            // the latest token; the SDK must not register after sign-out/restart.
            it.isAutoInitEnabled = false
        }
    } catch (_: RuntimeException) { null }

    fun permissionGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val manager = manager(context)
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE) return false
        return true
    }

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            manager(context).createNotificationChannel(NotificationChannel(CHANNEL, "가족 주차 알림", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "가족이 새 주차 위치를 기록했을 때 알려드려요."
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            })
        }
    }

    fun cancelNotifications(context: Context) { manager(context).cancel(NOTIFICATION_ID) }

    @Suppress("DEPRECATION")
    @Synchronized fun discardLateToken(context: Context, messaging: FirebaseMessaging) {
        if (enabled(context) || !gate.beginDiscardIfIdle()) return
        try { messaging.deleteToken().addOnCompleteListener { gate.endDelete() } }
        catch (_: RuntimeException) { gate.endDelete() }
    }
}

/** No JWT or push token is persisted here. Firebase owns its installation cache. */
class PushNotifications(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var attempt: Long? = null
    private var timeout: Runnable? = null
    var awaitingPermission = false
        private set

    fun status(result: MethodChannel.Result) {
        val configured = FamilyPushState.messaging(activity) != null
        val granted = FamilyPushState.permissionGranted(activity)
        val requested = FamilyPushState.preferences(activity).getBoolean("permissionRequested", false)
        result.success(mapOf(
            "supported" to true, "configured" to configured,
            "permission" to if (granted) "authorized" else if (Build.VERSION.SDK_INT >= 33 && !requested) "notDetermined" else "denied",
            "granted" to granted, "enabled" to FamilyPushState.enabled(activity),
            "provider" to "fcm", "environment" to "production"
        ))
    }

    fun register(requestPermission: Boolean, result: MethodChannel.Result) {
        val messaging = FamilyPushState.messaging(activity)
        if (messaging == null) {
            result.error("push_unconfigured", "가족 알림 연결을 준비하고 있어요.", null); return
        }
        val generation = FamilyPushState.gate.begin()
        if (generation == null) {
            result.error("push_busy", "알림 설정을 처리하고 있어요. 잠시 후 다시 시도해 주세요.", null); return
        }
        pending = result
        attempt = generation
        val work = Runnable { fail("push_timeout", "알림 서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.") }
        timeout = work
        handler.postDelayed(work, 25_000)
        FamilyPushState.createChannel(activity)
        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            if (!requestPermission) { fail("push_permission_required", "설정에서 차자리의 알림을 허용해 주세요."); return }
            FamilyPushState.preferences(activity).edit().putBoolean("permissionRequested", true).apply()
            awaitingPermission = true
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
        } else if (!FamilyPushState.permissionGranted(activity)) {
            fail("push_permission_required", "설정에서 차자리의 가족 주차 알림을 허용해 주세요.")
        } else requestToken(messaging, generation)
    }

    fun permissionResult(granted: Boolean) {
        awaitingPermission = false
        val generation = attempt ?: return
        if (!FamilyPushState.gate.isCurrent(generation) || pending == null) return
        if (!granted || !FamilyPushState.permissionGranted(activity)) {
            fail("push_permission_required", "설정에서 차자리의 알림을 허용해 주세요."); return
        }
        val messaging = FamilyPushState.messaging(activity)
        if (messaging == null) fail("push_unconfigured", "가족 알림 연결을 확인해 주세요.")
        else requestToken(messaging, generation)
    }

    @Suppress("DEPRECATION") // Explicitly pinned token protocol; FID registration is not enabled.
    private fun requestToken(messaging: FirebaseMessaging, generation: Long) {
        val tokenTask = try { messaging.token } catch (_: RuntimeException) {
            fail("push_registration_failed", "알림 등록을 완료하지 못했어요. 연결 설정을 확인해 주세요."); return
        }
        tokenTask.addOnCompleteListener { task ->
            if (!FamilyPushState.gate.isCurrent(generation) || pending == null) {
                FamilyPushState.discardLateToken(activity.applicationContext, messaging)
                return@addOnCompleteListener
            }
            val token = if (task.isSuccessful) task.result else null
            if (token.isNullOrEmpty()) { fail("push_registration_failed", "알림 등록을 완료하지 못했어요. 연결 상태를 확인해 주세요."); return@addOnCompleteListener }
            if (!FamilyPushState.permissionGranted(activity)) {
                fail("push_permission_required", "설정에서 차자리의 알림을 허용해 주세요."); return@addOnCompleteListener
            }
            if (!FamilyPushState.setEnabled(activity, true)) {
                fail("push_storage_failed", "알림 설정을 저장하지 못했어요."); return@addOnCompleteListener
            }
            FamilyPushState.gate.finish(generation)
            val response = pending
            clearPending()
            response?.success(mapOf("provider" to "fcm", "environment" to "production", "token" to token))
        }
    }

    @Suppress("DEPRECATION")
    fun disable(result: MethodChannel.Result) {
        FamilyPushState.gate.cancel()
        val stored = synchronized(FamilyPushState) {
            val saved = FamilyPushState.setEnabled(activity, false)
            FamilyPushState.cancelNotifications(activity)
            saved
        }
        val interrupted = pending
        clearPending()
        interrupted?.error("push_cancelled", "알림 등록을 취소했어요.", null)
        val messaging = FamilyPushState.messaging(activity)
        if (messaging == null) {
            if (stored) result.success(null) else result.error("push_storage_failed", "알림 설정을 저장하지 못했어요.", null)
            return
        }
        FamilyPushState.gate.beginDelete()
        var responded = false
        val work = Runnable {
            responded = true
            result.error("push_disable_pending", "기기의 알림은 껐지만 서버 연결 해제를 확인하지 못했어요. 다시 시도해 주세요.", null)
        }
        handler.postDelayed(work, 25_000)
        val deletion = try { messaging.deleteToken() } catch (_: RuntimeException) {
            FamilyPushState.gate.endDelete()
            handler.removeCallbacks(work)
            result.error("push_disable_failed", "알림 연결 해제를 확인하지 못했어요. 다시 시도해 주세요.", null)
            return
        }
        deletion.addOnCompleteListener { task ->
            FamilyPushState.gate.endDelete()
            handler.removeCallbacks(work)
            if (!responded) {
                responded = true
                if (task.isSuccessful && stored) result.success(null)
                else result.error("push_disable_failed", "알림 연결 해제를 확인하지 못했어요. 다시 시도해 주세요.", null)
            }
        }
    }

    fun detach() {
        if (pending != null) fail("push_cancelled", "알림 등록을 취소했어요.")
    }

    private fun fail(code: String, message: String) {
        attempt?.let { if (FamilyPushState.gate.isCurrent(it)) FamilyPushState.gate.cancel() }
        val response = pending
        clearPending()
        response?.error(code, message, null)
    }

    private fun clearPending() {
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null; pending = null; attempt = null; awaitingPermission = false
    }

    companion object { const val PERMISSION_REQUEST = 411 }
}
