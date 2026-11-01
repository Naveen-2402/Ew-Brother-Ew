package com.ewbrother.app.notify

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.ewbrother.app.data.Keys
import com.ewbrother.app.data.Store
import java.util.Calendar

/**
 * Schedules the next morning / evening / weekly / per-habit / per-task alarm.
 * Uses inexact setAndAllowWhileIdle: no SCHEDULE_EXACT_ALARM permission needed on Android 14;
 * a reminder may arrive a few minutes late in deep sleep, which is fine for reminders.
 * Every alarm reschedules everything after it fires, so interval reminders walk forward slot by slot.
 */
object AlarmScheduler {
    const val KIND_MORNING = "morning"
    const val KIND_EVENING = "evening"
    const val KIND_WEEKLY = "weekly"
    const val KIND_HABIT = "habit"
    const val KIND_TASK = "task"

    private const val REQ_MORNING = 10
    private const val REQ_EVENING = 11
    private const val REQ_WEEKLY = 12
    private const val REQ_HABIT_BASE = 2000
    private const val REQ_TASK_BASE = 1_000_000

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
        val habits = ArrayList<String>()
        store.habitsToday(store.today()).forEach { h ->
            val start = h.reminder ?: return@forEach
            set(ctx, REQ_HABIT_BASE + h.id.toInt(), KIND_HABIT, h.id, nextSlot(start, h.until, h.every, now))
            habits.add(h.id.toString())
        }
        store.set(Keys.ALARM_HABIT_IDS, Store.toJson(habits))

        // Tasks: same pattern.
        Store.jsonList(s[Keys.ALARM_TASK_IDS]).mapNotNull { it.toLongOrNull() }.forEach { id ->
            set(ctx, REQ_TASK_BASE + id.toInt(), KIND_TASK, id, null)
        }
        val tasks = ArrayList<String>()
        store.taskReminders().forEach { t ->
            val at = taskNext(t, now) ?: return@forEach
            set(ctx, REQ_TASK_BASE + t.id.toInt(), KIND_TASK, t.id, at)
            tasks.add(t.id.toString())
        }
        store.set(Keys.ALARM_TASK_IDS, Store.toJson(tasks))
    }

    /** Repeat-daily: every day at the reminder's time of day. Otherwise once, if still ahead. */
    fun taskNext(t: Store.TaskReminder, now: Long): Long? {
        if (t.repeatDaily) {
            val c = Calendar.getInstance()
            c.timeInMillis = t.at
            return nextDaily("${c.get(Calendar.HOUR_OF_DAY)}:${c.get(Calendar.MINUTE)}", now)
        }
        return if (!t.done && t.at > now + 1000) t.at else null
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

    /**
     * Next reminder slot. [every] = 0 (or no [until]): once a day at [start].
     * Otherwise every [every] minutes from [start] to [until] (inclusive), today or tomorrow.
     */
    fun nextSlot(start: String, until: String?, every: Int, now: Long): Long {
        val slots = slotMinutes(start, until, every) ?: return nextDaily(start, now)
        for (dayOffset in 0..1) {
            for (min in slots) {
                val c = Calendar.getInstance()
                c.timeInMillis = now
                c.add(Calendar.DAY_OF_MONTH, dayOffset)
                c.set(Calendar.HOUR_OF_DAY, min / 60)
                c.set(Calendar.MINUTE, min % 60)
                c.set(Calendar.SECOND, 0)
                c.set(Calendar.MILLISECOND, 0)
                if (c.timeInMillis > now + 1000) return c.timeInMillis
            }
        }
        return nextDaily(start, now)
    }

    /** Minutes after midnight of each interval reminder, or null for a single daily reminder. */
    fun slotMinutes(start: String, until: String?, every: Int): List<Int>? {
        if (every <= 0 || until == null) return null
        val (sh, sm) = parse(start)
        val (eh, em) = parse(until)
        val from = sh * 60 + sm
        val to = eh * 60 + em
        if (to <= from) return null
        return (from..to step every.coerceAtLeast(15)).toList()
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
