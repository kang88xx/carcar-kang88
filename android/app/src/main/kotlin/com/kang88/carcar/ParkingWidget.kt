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
        if (action in listOf("floor", "zone", "save", "select")) {
            val field = intent.getStringExtra("field")
            val value = intent.getStringExtra("value")
            val pending = goAsync()
            executor.execute {
                try {
                    when (action) {
                        "save" -> WidgetActions.save(context)
                        "select" -> if (field != null && value != null) WidgetActions.select(context, field, value)
                        else -> WidgetActions.cycle(context, action!!)
                    }
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
            // No app name in the widget: the location itself is the headline.
            view.setTextViewText(R.id.widget_location, if (data == null) "주차 위치 없음" else "${data.optString("floor")} · ${data.optString("zone")} ${data.optString("spot")}".trim())
            view.setTextViewText(R.id.widget_updated, when {
                data == null -> "앱에서 확인"
                data.optBoolean("isDemo") -> "체험 · " + WidgetTimestamp.format(data.optString("updatedAt"))
                else -> WidgetTimestamp.format(data.optString("updatedAt"))
            })
            val draft = WidgetActions.display(context)
            view.setTextViewText(R.id.widget_hint, draft.optString("status", "층을 누른 뒤 등록을 누르면 서버에 저장돼요"))
            val options = manager.getAppWidgetOptions(id)
            val roomy = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) >= 200 && options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) >= 140
            view.setViewVisibility(R.id.widget_controls, if (roomy) android.view.View.VISIBLE else android.view.View.GONE)
            val enabled = draft.optBoolean("enabled") && !draft.optBoolean("busy")
            val floors = if (draft.optBoolean("enabled")) WidgetActions.options(context, "floor") else emptyList()
            view.setViewVisibility(R.id.widget_floor_row_2, if (floors.size > FLOOR_SLOTS / 2) android.view.View.VISIBLE else android.view.View.GONE)
            floorIds.forEachIndexed { index, slotId ->
                val floor = floors.getOrNull(index)
                view.setViewVisibility(slotId, if (floor == null) android.view.View.GONE else android.view.View.VISIBLE)
                if (floor == null) return@forEachIndexed
                val selected = floor == draft.optString("floor")
                view.setTextViewText(slotId, floor)
                view.setInt(slotId, "setBackgroundResource", if (selected) R.drawable.widget_chip_selected else R.drawable.widget_chip)
                view.setTextColor(slotId, if (selected) 0xFF1E293B.toInt() else 0xFFFFFFFF.toInt())
                view.setContentDescription(slotId, if (selected) "$floor 선택됨" else "$floor 선택")
                view.setBoolean(slotId, "setEnabled", enabled)
                view.setFloat(slotId, "setAlpha", if (enabled) 1f else 0.45f)
                val select = Intent(context, ParkingWidget::class.java).setAction("com.kang88.carcar.widget.select").putExtra("field", "floor").putExtra("value", floor)
                view.setOnClickPendingIntent(slotId, PendingIntent.getBroadcast(context, "select:floor:$floor".hashCode(), select, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
            view.setTextViewText(R.id.widget_zone, draft.optString("zone", "구역").let { if (draft.optBoolean("enabled")) "$it 구역" else "구역" })
            view.setTextViewText(R.id.widget_save, if (draft.optBoolean("busy")) "저장 중…" else "등록")
            for ((name, buttonId) in listOf("zone" to R.id.widget_zone, "save" to R.id.widget_save)) {
                view.setBoolean(buttonId, "setEnabled", enabled)
                view.setFloat(buttonId, "setAlpha", if (enabled) 1f else 0.45f)
                val action = Intent(context, ParkingWidget::class.java).setAction("com.kang88.carcar.widget.$name")
                view.setOnClickPendingIntent(buttonId, PendingIntent.getBroadcast(context, name.hashCode(), action, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
            val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            view.setOnClickPendingIntent(R.id.widget_root, open)
            manager.updateAppWidget(id, view)
        }
    }
    companion object {
        /** Fixed layout slots; owners with more floors keep the remaining floors in the app. */
        const val FLOOR_SLOTS = 12
        private val floorIds = listOf(
            R.id.widget_floor_0, R.id.widget_floor_1, R.id.widget_floor_2, R.id.widget_floor_3, R.id.widget_floor_4, R.id.widget_floor_5,
            R.id.widget_floor_6, R.id.widget_floor_7, R.id.widget_floor_8, R.id.widget_floor_9, R.id.widget_floor_10, R.id.widget_floor_11,
        )
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
