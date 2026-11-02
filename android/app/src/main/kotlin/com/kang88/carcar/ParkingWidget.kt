package com.kang88.carcar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject

class ParkingWidget : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action?.removePrefix("com.kang88.carcar.widget.")
        if (action == "recover") { refresh(context); return }
        if (action in listOf("floor", "zone", "save")) {
            val pending = goAsync()
            executor.execute {
                try {
                    if (action == "save") WidgetActions.save(context) else WidgetActions.cycle(context, action!!)
                    refresh(context)
                } catch (_: Exception) { /* A storage failure must not crash the receiver. */ }
                finally { pending.finish() }
            }
        } else super.onReceive(context, intent)
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: android.os.Bundle) { onUpdate(context, manager, intArrayOf(id)) }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { id ->
            val raw = context.getSharedPreferences("carcar_widget", Context.MODE_PRIVATE).getString("snapshot", null)
            val data = try { raw?.let { JSONObject(it) } } catch (_: Exception) { null }
            val view = RemoteViews(context.packageName, R.layout.parking_widget)
            view.setTextViewText(R.id.widget_title, if (data?.optBoolean("isDemo") == true) "차곡 · 체험" else "차곡 · 마지막 주차")
            view.setTextViewText(R.id.widget_location, if (data == null) "앱에서 주차 위치를 확인해 주세요" else "${data.optString("floor")} · ${data.optString("zone")} ${data.optString("spot")}")
            view.setTextViewText(R.id.widget_updated, if (data == null) "저장된 기록 없음" else WidgetTimestamp.format(data.optString("updatedAt")))
            val draft = WidgetActions.display(context)
            view.setTextViewText(R.id.widget_hint, draft.optString("status", "층·구역 선택 후 저장"))
            val medium = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) >= 240
            view.setViewVisibility(R.id.widget_controls, if (medium) android.view.View.VISIBLE else android.view.View.GONE)
            for ((name, buttonId) in listOf("floor" to R.id.widget_floor, "zone" to R.id.widget_zone, "save" to R.id.widget_save)) {
                view.setTextViewText(buttonId, if (name == "save") (if (draft.optBoolean("busy")) "저장 중" else "저장") else draft.optString(name, if (name == "floor") "층" else "구역"))
                view.setBoolean(buttonId, "setEnabled", draft.optBoolean("enabled") && !draft.optBoolean("busy"))
                val action = Intent(context, ParkingWidget::class.java).setAction("com.kang88.carcar.widget.$name")
                view.setOnClickPendingIntent(buttonId, PendingIntent.getBroadcast(context, name.hashCode(), action, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
            val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            view.setOnClickPendingIntent(R.id.widget_root, open)
            manager.updateAppWidget(id, view)
        }
    }
    companion object {
        private val executor = java.util.concurrent.Executors.newCachedThreadPool()
        fun scheduleRecovery(context: Context) {
            val intent = Intent(context, ParkingWidget::class.java).setAction("com.kang88.carcar.widget.recover")
            val pending = PendingIntent.getBroadcast(context, 2401, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            // One local refresh after an interrupted attempt, never network polling.
            alarm.setAndAllowWhileIdle(android.app.AlarmManager.ELAPSED_REALTIME, android.os.SystemClock.elapsedRealtime() + 21000, pending)
        }
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            ParkingWidget().onUpdate(context, manager, manager.getAppWidgetIds(ComponentName(context, ParkingWidget::class.java)))
        }
    }
}
