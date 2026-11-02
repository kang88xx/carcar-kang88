package com.kang88.carcar

import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.UUID

/** Pure validation shared by native request processing and JVM regression checks. */
object WidgetRules {
    fun requestId(existing: String): String = existing.ifEmpty { UUID.randomUUID().toString() }
    fun validTimestamp(value: String): Boolean = timestampMicros(value) != Long.MIN_VALUE
    fun timestampMicros(value: String): Long {
        val match = Regex("^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(?:\\.(\\d{1,6}))?(Z|[+-]\\d{2}:\\d{2})$").matchEntire(value) ?: return Long.MIN_VALUE
        val normalized = match.groupValues[1] + "." + match.groupValues[2].take(3).padEnd(3, '0') + match.groupValues[3]
        val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.ROOT).apply { isLenient = false }
        val position = ParsePosition(0)
        val parsed = parser.parse(normalized, position)
        if (parsed == null || position.index != normalized.length) return Long.MIN_VALUE
        // PostgreSQL preserves six fractional digits; Date only preserves three.
        // Add the remaining fraction after parsing the offset-aware milliseconds.
        val subMillisecond = match.groupValues[2].padEnd(6, '0').takeLast(3).toLong()
        return parsed.time * 1000 + subMillisecond
    }
    fun sameOperation(expectedGeneration: String, currentGeneration: String?, expectedOperation: String, currentOperation: String?): Boolean =
        expectedGeneration.isNotBlank() && expectedGeneration == currentGeneration && expectedOperation.isNotBlank() && expectedOperation == currentOperation
}
