package com.ewbrother.app.data

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * A "day" in this app starts at [resetHour] (default 4 AM), not midnight,
 * so late-night scrolling counts toward the same day.
 *
 * MUST stay identical to lib/core/logical_day.dart.
 */
object LogicalDay {
    private fun fmt() = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    /** Day key such as "2026-11-01" for the given moment. */
    fun keyFor(millis: Long, resetHour: Int): String {
        val cal = Calendar.getInstance()
        cal.timeInMillis = millis
        cal.add(Calendar.HOUR_OF_DAY, -resetHour)
        return fmt().format(cal.time)
    }

    /** Epoch millis when the given day key starts (local time, at resetHour). */
    fun startOf(key: String, resetHour: Int): Long {
        val parts = key.split("-")
        val cal = Calendar.getInstance()
        cal.clear()
        cal.set(parts[0].toInt(), parts[1].toInt() - 1, parts[2].toInt(), resetHour, 0, 0)
        return cal.timeInMillis
    }

    /** Day key [days] before [key]. */
    fun minusDays(key: String, days: Int): String {
        val parts = key.split("-")
        val cal = Calendar.getInstance()
        cal.clear()
        cal.set(parts[0].toInt(), parts[1].toInt() - 1, parts[2].toInt(), 12, 0, 0)
        cal.add(Calendar.DAY_OF_MONTH, -days)
        return fmt().format(cal.time)
    }
}
