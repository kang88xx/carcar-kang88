package com.kang88.carcar

import android.content.Context
import org.json.JSONObject

object WidgetSnapshots {
    fun merge(c: Context, incoming: JSONObject) = synchronized(WidgetSession) {
        val auth = WidgetSession.read(c)
        if (auth != null && (incoming.optBoolean("isDemo") || listOf("userId", "vehicleId").any { incoming.optString(it) != auth.optString(it) })) return@synchronized
        val prefs = c.getSharedPreferences("carcar_widget", Context.MODE_PRIVATE)
        val old = try { JSONObject(prefs.getString("snapshot", "{}")!!) } catch (_: Exception) { JSONObject() }
        val same = listOf("userId", "vehicleId").all { incoming.optString(it).isNotEmpty() && incoming.optString(it) == old.optString(it) }
        if (same && WidgetRules.timestampMicros(old.optString("updatedAt")) > WidgetRules.timestampMicros(incoming.optString("updatedAt"))) return@synchronized
        check(prefs.edit().putString("snapshot", incoming.toString()).commit())
    }
}
