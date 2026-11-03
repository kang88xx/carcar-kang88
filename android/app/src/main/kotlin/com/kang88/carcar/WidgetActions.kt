package com.kang88.carcar

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

object WidgetActions {
    private fun prefs(c: Context) = c.getSharedPreferences("carcar_widget_draft", Context.MODE_PRIVATE)
    fun reset(c: Context) { check(prefs(c).edit().clear().commit()) }
    private fun busy(state: JSONObject) = state.optLong("busyUntil") > System.currentTimeMillis()
    private fun state(c: Context) = try { JSONObject(prefs(c).getString("state", "{}")!!) } catch (_: Exception) { JSONObject() }
    private fun write(c: Context, value: JSONObject) { check(prefs(c).edit().putString("state", value.toString()).commit()) }
    fun display(c: Context): JSONObject = synchronized(WidgetSession) {
        val state = state(c)
        val session = WidgetSession.read(c)
        val demo = try { JSONObject(c.getSharedPreferences("carcar_widget", Context.MODE_PRIVATE).getString("snapshot", "{}")!!).optBoolean("isDemo") } catch (_: Exception) { false }
        val enabled = !demo && session != null && session.optLong("expiresAt") > System.currentTimeMillis() / 1000
        state.put("enabled", enabled).put("busy", busy(state))
        if (enabled) {
            for (field in listOf("floor", "zone")) {
                val values = session!!.getJSONArray(field + "s")
                if ((0 until values.length()).none { values.getString(it) == state.optString(field) }) { state.put(field, values.getString(0)); state.remove("requestId") }
            }
        } else state.put("status", if (demo) "체험은 앱에서 기록해 주세요" else "앱을 열어 로그인 갱신")
        state
    }
    /** Floor or zone choices the signed-in owner configured; empty without a live widget session. */
    fun options(c: Context, field: String): List<String> = synchronized(WidgetSession) {
        val values = WidgetSession.read(c)?.optJSONArray(field + "s") ?: return@synchronized emptyList()
        (0 until values.length()).map { values.getString(it) }
    }
    /** Direct tap on a floor/zone chip. The value must be one of the configured options. */
    fun select(c: Context, field: String, selected: String) = synchronized(WidgetSession) {
        require(field == "floor" || field == "zone")
        val value = display(c)
        if (!value.optBoolean("enabled") || value.optBoolean("busy")) return@synchronized
        if (selected !in options(c, field)) return@synchronized
        value.put(field, selected).put("requestId", UUID.randomUUID().toString()).put("status", "등록을 누르면 서버에 저장돼요")
        write(c, value)
    }
    fun cycle(c: Context, field: String) = synchronized(WidgetSession) {
        val value = display(c)
        if (!value.optBoolean("enabled") || value.optBoolean("busy")) return@synchronized
        val values = WidgetSession.read(c)!!.getJSONArray(field + "s")
        val current = (0 until values.length()).firstOrNull { values.getString(it) == value.optString(field) } ?: 0
        value.put(field, values.getString((current + 1) % values.length())).put("requestId", UUID.randomUUID().toString()).put("status", "등록을 누르면 서버에 저장돼요")
        write(c, value)
    }
    fun save(c: Context) {
        val captured = synchronized(WidgetSession) {
            val state = display(c)
            if (!state.optBoolean("enabled") || state.optBoolean("busy")) return
            if (!state.has("requestId")) state.put("requestId", WidgetRules.requestId(state.optString("requestId")))
            state.put("operation", UUID.randomUUID().toString()).put("busyUntil", System.currentTimeMillis() + 20000).put("status", "서버에 저장 중…")
            write(c, state)
            Pair(WidgetSession.read(c)!!, state)
        }
        ParkingWidget.scheduleRecovery(c)
        ParkingWidget.refresh(c)
        val (session, draft) = captured
        var record: JSONObject? = null
        var message = "저장하지 못했어요 · 다시 시도"
        var connection: HttpURLConnection? = null
        try {
            connection = URL(session.getString("url").trimEnd('/') + "/rest/v1/rpc/create_parking_record_and_set_latest").openConnection() as HttpURLConnection
            connection.apply {
                requestMethod = "POST"; connectTimeout = 2500; readTimeout = 4500; instanceFollowRedirects = false; doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("apikey", session.getString("publishableKey"))
                setRequestProperty("Authorization", "Bearer " + session.getString("accessToken"))
            }
            val body = JSONObject().put("p_vehicle_id", session.getString("vehicleId")).put("p_floor", draft.getString("floor"))
                .put("p_zone", draft.getString("zone")).put("p_spot", "").put("p_note", "").put("p_idempotency_key", draft.getString("requestId"))
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = connection.responseCode
            if (code == 401 || code == 403) message = "앱을 열어 로그인·차량 권한 확인"
            if (code in 200..299) {
                val raw = connection.inputStream.use { stream ->
                    val buffer = java.io.ByteArrayOutputStream()
                    val chunk = ByteArray(4096)
                    while (buffer.size() <= 65536) { val count = stream.read(chunk); if (count < 0) break; buffer.write(chunk, 0, count) }
                    val bytes = buffer.toByteArray()
                    require(bytes.size <= 65536)
                    String(bytes, Charsets.UTF_8)
                }
                val value = JSONObject(raw)
                UUID.fromString(value.getString("id")); require(WidgetRules.validTimestamp(value.getString("created_at")))
                require(value.getString("vehicle_id") == session.getString("vehicleId") && value.getString("floor") == draft.getString("floor") && value.getString("zone") == draft.getString("zone"))
                require(value.getString("idempotency_key") == draft.getString("requestId") && value.getString("created_by") == session.getString("userId"))
                require(value.getString("spot").length <= 20)
                record = value
            }
        } catch (_: Exception) { /* No token, URL response, or personal data in logs. */ }
        finally { connection?.disconnect() }
        synchronized(WidgetSession) {
            if (!WidgetRules.sameOperation(session.getString("generation"), WidgetSession.read(c)?.optString("generation"), draft.getString("operation"), state(c).optString("operation"))) return
            draft.remove("busyUntil")
            if (record != null) {
                val previous = c.getSharedPreferences("carcar_widget", Context.MODE_PRIVATE)
                val snapshot = try { JSONObject(previous.getString("snapshot", "{}")!!) } catch (_: Exception) { JSONObject() }
                for (field in listOf("floor", "zone", "spot")) snapshot.put(field, record!!.getString(field))
                snapshot.put("updatedAt", record!!.getString("created_at")).put("isDemo", false)
                snapshot.put("userId", session.getString("userId")).put("vehicleId", session.getString("vehicleId"))
                WidgetSnapshots.merge(c, snapshot)
                draft.put("status", "저장했어요").remove("requestId")
            } else draft.put("status", message)
            write(c, draft)
        }
        ParkingWidget.refresh(c)
    }
}
