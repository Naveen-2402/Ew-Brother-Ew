package com.ewbrother.app.notify

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.ewbrother.app.data.Keys
import com.ewbrother.app.data.Store
import java.util.Calendar

/**
 * Schedules the next morning / evening / weekly / per-habit alarm.
 * Uses inexact setAndAllowWhileIdle: no SCHEDULE_EXACT_ALARM permission needed on Android 14;
 * a reminder may arrive a few minutes late in deep sleep, which is fine for reminders.
 * Every alarm reschedules everything after it fires.
 */
object AlarmScheduler {
    const val KIND_MORNING = "morning"
    const val KIND_EVENING = "evening"
    const val KIND_WEEKLY = "weekly"
    const val KIND_HABIT = "habit"

    private const val REQ_MORNING = 10
    private const val REQ_EVENING = 11
    private const val REQ_WEEKLY = 12
    private const val REQ_HABIT_BASE = 2000

    fun scheduleAll(ctx: Context) {
        val store = Store(ctx)
        val s = store.settings()
        val now = System.currentTimeMillis()

        set(ctx, REQ_MORNING, KIND_MORNING, 0, if (s[Keys.MORNING_ON] == "1") nextDaily(s[Keys.MORNING_TIME], now) else null)
        set(ctx, REQ_EVENING, KIND_EVENING, 0, if (s[Keys.EVENING_ON] == "1") nextDaily(s[Keys.EVENING_TIME], now) else null)
        set(ctx, REQ_WEEKLY, KIND_WEEKLY, 0, if (s[Keys.WEEKLY_ON] == "1") nextSunday(now) else null)

        // Habits: cancel what we scheduled last time, then schedule the current ones.
        Store.jsonList(s[Keys.ALARM_HABIT_IDS]).mapNotNull { it.toLongOrNull() }.forEach { id ->
            set(ctx, REQ_HABIT_BASE + id.toInt(), KIND_HABIT, id, null)
        }
        val scheduled = ArrayList<String>()
        store.habitsToday(store.today()).forEach { h ->
            val time = h.reminder ?: return@forEach
            set(ctx, REQ_HABIT_BASE + h.id.toInt(), KIND_HABIT, h.id, nextDaily(time, now))
            scheduled.add(h.id.toString())
        }
        store.set(Keys.ALARM_HABIT_IDS, Store.toJson(scheduled))
    }

    private fun set(ctx: Context, request: Int, kind: String, id: Long, at: Long?) {
        val am = ctx.getSystemService(AlarmManager::class.java)!!
        val intent = Intent(ctx, ActionReceiver::class.java)
            .setAction(ActionReceiver.ACTION_ALARM)
            .putExtra(ActionReceiver.EXTRA_KIND, kind)
            .putExtra(ActionReceiver.EXTRA_ID, id)
        val pi = PendingIntent.getBroadcast(
            ctx, request, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (at == null) {
            am.cancel(pi)
            pi.cancel()
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    /** Next time today/tomorrow at "HH:mm". */
    fun nextDaily(hhmm: String?, now: Long): Long {
        val (h, m) = parse(hhmm)
        val c = Calendar.getInstance()
        c.timeInMillis = now
        c.set(Calendar.HOUR_OF_DAY, h)
        c.set(Calendar.MINUTE, m)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        if (c.timeInMillis <= now + 1000) c.add(Calendar.DAY_OF_MONTH, 1)
        return c.timeInMillis
    }

    private fun nextSunday(now: Long): Long {
        val c = Calendar.getInstance()
        c.timeInMillis = now
        c.set(Calendar.HOUR_OF_DAY, 19)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        while (c.get(Calendar.DAY_OF_WEEK) != Calendar.SUNDAY || c.timeInMillis <= now + 1000) {
            c.add(Calendar.DAY_OF_MONTH, 1)
        }
        return c.timeInMillis
    }

    fun parse(hhmm: String?): Pair<Int, Int> {
        val parts = (hhmm ?: "").split(":")
        val h = parts.getOrNull(0)?.toIntOrNull()?.coerceIn(0, 23) ?: 8
        val m = parts.getOrNull(1)?.toIntOrNull()?.coerceIn(0, 59) ?: 0
        return h to m
    }
}
