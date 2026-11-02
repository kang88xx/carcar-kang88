package com.kang88.carcar

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var pendingFinding: Map<*, *>? = null
    private lateinit var familyPush: PushNotifications
    private lateinit var launcherIcons: LauncherIcons

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        familyPush = PushNotifications(this)
        launcherIcons = LauncherIcons(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "carcar/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "shareText" -> {
                    val text = (call.arguments as? Map<*, *>)?.get("text") as? String
                    if (text.isNullOrBlank() || text.length > 4096) {
                        result.error("invalid_share_text", "공유할 내용을 확인해 주세요.", null)
                    } else if (isFinishing || isDestroyed) {
                        result.success(false)
                    } else {
                        try {
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(Intent.createChooser(send, "초대 링크 공유"))
                            // This confirms only that the chooser opened, not that a message was sent.
                            result.success(true)
                        } catch (_: Exception) { result.success(false) }
                    }
                }
                "launcherIconState" -> launcherIcons.read(result)
                "setLauncherIcon" -> launcherIcons.set(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "pushStatus" -> familyPush.status(result)
                "registerPush" -> {
                    if (permissionResult != null) result.error("push_busy", "알림 권한 확인 중이에요.", null)
                    else familyPush.register(call.argument<Boolean>("requestPermission") ?: true, result)
                }
                "disablePush" -> familyPush.disable(result)
                "recognizeText" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank() || !File(path).isFile) {
                        result.error("image_missing", "사진을 다시 선택해 주세요.", null)
                    } else {
                        try {
                            val image = InputImage.fromFilePath(this, Uri.fromFile(File(path)))
                            val recognizer = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
                            recognizer.process(image)
                                .addOnSuccessListener { result.success(it.text) }
                                .addOnFailureListener { result.error("ocr_failed", "글자를 읽지 못했어요. 직접 입력해 주세요.", null) }
                                .addOnCompleteListener { recognizer.close() }
                        } catch (_: Exception) {
                            result.error("image_invalid", "사진을 열지 못했어요.", null)
                        }
                    }
                }
                "updateWidgetSession", "clearWidgetSession" -> {
                    try {
                        if (call.method == "updateWidgetSession") WidgetSession.update(this, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                        else WidgetSession.clear(this)
                        ParkingWidget.refresh(this)
                        result.success(null)
                    } catch (_: Exception) { result.error("widget_session_failed", "위젯 보안 설정을 갱신하지 못했어요.", null) }
                }
                "updateSnapshot" -> {
                    val snapshot = sanitizedSnapshot(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                    try {
                        WidgetSnapshots.merge(this, snapshot)
                        ParkingWidget.refresh(this)
                        result.success(null)
                    } catch (_: Exception) { result.error("widget_snapshot_failed", "위젯 위치를 갱신하지 못했어요.", null) }
                }
                "clearSnapshot" -> {
                    try { WidgetSession.clear(this) } catch (_: Exception) {
                        result.error("widget_clear_failed", "위젯 로그인을 지우지 못했어요. 다시 시도해 주세요.", null)
                        return@setMethodCallHandler
                    }
                    permissionResult?.success(false)
                    permissionResult = null
                    pendingFinding = null
                    getSharedPreferences("carcar_widget", MODE_PRIVATE).edit().clear().apply()
                    ParkingWidget.refresh(this)
                    notificationManager().cancel(FINDING_ID)
                    result.success(null)
                }
                "startFinding" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val minutes = (args["minutes"] as? Number)?.toInt()
                    if (minutes !in listOf(60, 120, 240, 480)) {
                        result.error("invalid_duration", "1·2·4·8시간 중 선택해 주세요.", null)
                    } else if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null || familyPush.awaitingPermission) result.error("busy", "알림 권한 확인 중이에요.", null)
                        else {
                            permissionResult = result
                            pendingFinding = args
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 410)
                        }
                    } else result.success(showFinding(args))
                }
                "stopFinding" -> {
                    permissionResult?.success(false)
                    permissionResult = null
                    pendingFinding = null
                    notificationManager().cancel(FINDING_ID)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 410) {
            val allowed = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            permissionResult?.success(allowed && pendingFinding?.let { showFinding(it) } == true)
            permissionResult = null
            pendingFinding = null
        }
        if (requestCode == PushNotifications.PERMISSION_REQUEST && ::familyPush.isInitialized) {
            familyPush.permissionResult(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        }
    }

    override fun onDestroy() {
        if (::familyPush.isInitialized) familyPush.detach()
        super.onDestroy()
    }

    private fun notificationManager() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun showFinding(args: Map<*, *>): Boolean {
        // Older APIs cannot enforce a notification expiry.
        if (Build.VERSION.SDK_INT < 26) return false
        val manager = notificationManager()
        if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) return false
        val snapshot = sanitizedSnapshot(args)
        val minutes = (args["minutes"] as? Number)?.toLong() ?: return false
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel("carcar_finding", "차량 찾기", NotificationManager.IMPORTANCE_LOW))
            if (manager.getNotificationChannel("carcar_finding").importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getBroadcast(this, 1, Intent(this, FindingStopReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = Notification.Builder(this, "carcar_finding")
        builder.setSmallIcon(R.drawable.ic_parking_notification)
            .setContentTitle("${snapshot.optString("vehicleName", "우리 차")} 찾기")
            .setContentText("${snapshot.optString("floor")} · ${snapshot.optString("zone")} ${snapshot.optString("spot")}".trim())
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .addAction(Notification.Action.Builder(null, "표시 종료", stop).build())
        builder.setTimeoutAfter(minutes * 60_000)
        manager.notify(FINDING_ID, builder.build())
        return true
    }

    companion object {
        const val FINDING_ID = 410
        fun sanitizedSnapshot(args: Map<*, *>): JSONObject {
            val result = JSONObject()
            listOf("vehicleName", "floor", "zone", "spot", "updatedAt", "userId", "vehicleId").forEach { key ->
                result.put(key, (args[key] as? String ?: "").take(100))
            }
            result.put("isDemo", args["isDemo"] == true)
            return result
        }
    }
}
