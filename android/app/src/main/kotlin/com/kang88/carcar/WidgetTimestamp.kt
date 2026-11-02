package com.kang88.carcar

import java.text.DateFormat
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Formats the server record timestamp, never the widget-render time. */
object WidgetTimestamp {
    fun format(isoUtc: String?): String {
        val match = Regex("^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(?:\\.(\\d{1,6}))?(Z|[+-]\\d{2}:\\d{2})$")
            .matchEntire(isoUtc.orEmpty()) ?: return "기록 시각 확인 필요"
        // Dart can supply microseconds; SimpleDateFormat accepts milliseconds only.
        val milliseconds = match.groupValues[2].take(3).padEnd(3, '0')
        val normalized = "${match.groupValues[1]}.$milliseconds" + match.groupValues[3]
        val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("UTC")
            isLenient = false
        }
        val position = ParsePosition(0)
        val date = parser.parse(normalized, position)
        if (date == null || position.index != normalized.length) return "기록 시각 확인 필요"
        val display = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT, Locale.getDefault())
        return "기록 ${display.format(date)}"
    }
}
