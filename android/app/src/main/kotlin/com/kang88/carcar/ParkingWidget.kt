package com.kang88.carcar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.TypedValue
import android.view.View
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
            val floor = data?.optString("floor").orEmpty().trim()
            val zone = data?.optString("zone").orEmpty().trim()
            val spot = data?.optString("spot").orEmpty().trim()
            val hasRecord = floor.isNotEmpty()
            val timestamp = if (hasRecord) WidgetTimestamp.format(data?.optString("updatedAt")) else "주차 기록 없음"
            val caption = if (data?.optBoolean("isDemo") == true) "체험 · $timestamp" else timestamp
            view.setTextViewText(R.id.widget_updated, caption)
            view.setContentDescription(R.id.widget_updated, caption)
            view.setViewVisibility(R.id.widget_location, if (hasRecord) View.VISIBLE else View.GONE)
            view.setViewVisibility(R.id.widget_empty, if (hasRecord) View.GONE else View.VISIBLE)
            view.setTextViewText(R.id.widget_floor, floor)
            view.setTextViewText(R.id.widget_zone, if (zone.isEmpty() || zone.endsWith("구역")) zone else "${zone}구역")
            view.setTextViewText(R.id.widget_spot, if (spot.isEmpty() || spot.endsWith("번")) spot else "${spot}번")
            view.setViewVisibility(R.id.widget_zone, if (zone.isEmpty()) View.GONE else View.VISIBLE)
            view.setViewVisibility(R.id.widget_spot, if (spot.isEmpty()) View.GONE else View.VISIBLE)
            view.setContentDescription(R.id.widget_location, listOf(floor, zone, spot).filter { it.isNotEmpty() }.joinToString(" · "))
            // Framework TextView autosizing starts at API 26. Older supported
            // devices use smaller text; full values remain in the spoken label.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                view.setTextViewTextSize(R.id.widget_floor, TypedValue.COMPLEX_UNIT_SP, 20f)
                view.setTextViewTextSize(R.id.widget_zone, TypedValue.COMPLEX_UNIT_SP, 11f)
                view.setTextViewTextSize(R.id.widget_spot, TypedValue.COMPLEX_UNIT_SP, 11f)
            }
            // The action opens the form, never saves a record by itself.
            val intent = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("carcar://parking"))
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val open = PendingIntent.getActivity(context, 2402, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val home = PendingIntent.getActivity(context, 2403, Intent(intent).setData(Uri.parse("carcar://home")), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            view.setOnClickPendingIntent(R.id.widget_root, home)
            view.setOnClickPendingIntent(R.id.widget_record, open)
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
