package com.ewbrother.app.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONArray
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * All native reads/writes. Queries are tiny (a few rows), so callers on the main thread
 * only use the cheap reads; writes from the accessibility service go through [runIo].
 */
class Store(context: Context) {
    private val appContext = context.applicationContext
    private val db: SQLiteDatabase get() = EwDatabase.get(appContext).writableDatabase

    // ---------- settings ----------

    fun settings(): MutableMap<String, String> {
        val out = HashMap<String, String>(Keys.DEFAULTS)
        db.rawQuery("SELECT key, value FROM settings", null).use { c ->
            while (c.moveToNext()) out[c.getString(0)] = c.getString(1)
        }
        return out
    }

    fun get(key: String): String =
        db.rawQuery("SELECT value FROM settings WHERE key = ?", arrayOf(key)).use { c ->
            if (c.moveToFirst()) c.getString(0) else Keys.DEFAULTS[key] ?: ""
        }

    fun set(key: String, value: String) {
        db.execSQL("INSERT OR REPLACE INTO settings(key, value) VALUES (?, ?)", arrayOf(key, value))
    }

    fun resetHour(): Int = get(Keys.DAY_RESET_HOUR).toIntOrNull() ?: 4

    fun today(now: Long = System.currentTimeMillis()): String {
        applyPendingResetHour(now)
        return LogicalDay.keyFor(now, resetHour())
    }

    /**
     * A new "day starts at" hour is stored as pending and only takes effect once the current
     * logical day (under the old hour) has ended, so changing it can never start a new day early.
     * Same rule as AppController._applyPendingResetHour in Dart. Returns true when applied now.
     */
    fun applyPendingResetHour(now: Long = System.currentTimeMillis(), force: Boolean = false): Boolean {
        val next = get(Keys.DAY_RESET_NEXT).toIntOrNull() ?: return false
        val after = get(Keys.DAY_RESET_NEXT_AFTER)
        // [force]: the counter's day has ended on the uptime clock (the clock can't be trusted).
        if (!force && LogicalDay.keyFor(now, resetHour()) <= after) return false
        db.beginTransaction()
        try {
            set(Keys.DAY_RESET_HOUR, next.coerceIn(0, 23).toString())
            set(Keys.DAY_RESET_NEXT, "")
            set(Keys.DAY_RESET_NEXT_AFTER, "")
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return true
    }

    // ---------- reels ----------

    /** app -> [reel_count, reel_seconds] for one day. */
    fun dailyCounts(day: String): Map<String, IntArray> {
        val out = HashMap<String, IntArray>()
        db.rawQuery(
            "SELECT app, reel_count, reel_seconds FROM daily_stats WHERE date = ?",
            arrayOf(day),
        ).use { c ->
            while (c.moveToNext()) out[c.getString(0)] = intArrayOf(c.getInt(1), c.getInt(2))
        }
        return out
    }

    private fun ensureDailyRow(day: String, app: String) {
        // INSERT OR IGNORE + UPDATE instead of UPSERT: UPSERT needs SQLite 3.24 (Android 11+).
        db.execSQL("INSERT OR IGNORE INTO daily_stats(date, app) VALUES (?, ?)", arrayOf(day, app))
    }

    fun recordReels(app: String, count: Int, now: Long, day: String, addSeconds: Int) {
        val d = db
        d.beginTransaction()
        try {
            repeat(count) {
                val cv = ContentValues()
                cv.put("app", app)
                cv.put("timestamp", now)
                cv.put("date", day)
                d.insert("reel_events", null, cv)
            }
            ensureDailyRow(day, app)
            d.execSQL(
                "UPDATE daily_stats SET reel_count = reel_count + ?, reel_seconds = reel_seconds + ? " +
                    "WHERE date = ? AND app = ?",
                arrayOf<Any>(count, addSeconds, day, app),
            )
            d.setTransactionSuccessful()
        } finally {
            d.endTransaction()
        }
    }

    fun addReelSeconds(app: String, day: String, seconds: Int) {
        if (seconds <= 0) return
        ensureDailyRow(day, app)
        db.execSQL(
            "UPDATE daily_stats SET reel_seconds = reel_seconds + ? WHERE date = ? AND app = ?",
            arrayOf<Any>(seconds, day, app),
        )
    }

    /** Keep raw reel_events for 90 days; daily_stats is kept forever. Runs at most once a day. */
    fun pruneIfNeeded(today: String) {
        if (get(Keys.LAST_PRUNE_DAY) == today) return
        db.execSQL("DELETE FROM reel_events WHERE date < ?", arrayOf(LogicalDay.minusDays(today, 90)))
        set(Keys.LAST_PRUNE_DAY, today)
    }

    fun reelsBetween(fromDay: String, toDay: String): Int =
        db.rawQuery(
            "SELECT COALESCE(SUM(reel_count), 0) FROM daily_stats WHERE date >= ? AND date <= ?",
            arrayOf(fromDay, toDay),
        ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

    // ---------- tasks ----------

    data class TaskItem(val id: Long, val title: String)

    /** Repeat-daily tasks done before today's start become undone again. */
    fun rolloverTasks(dayStart: Long) {
        db.execSQL(
            "UPDATE tasks SET is_done = 0, done_at = NULL " +
                "WHERE repeat_daily = 1 AND is_done = 1 AND done_at < ?",
            arrayOf<Any>(dayStart),
        )
    }

    /** Undone tasks, starred (top 3) first, then in list order. */
    fun openTasks(limit: Int): List<TaskItem> {
        val out = ArrayList<TaskItem>()
        db.rawQuery(
            "SELECT id, title FROM tasks WHERE is_done = 0 " +
                "ORDER BY is_top3 DESC, position ASC, id ASC LIMIT ?",
            arrayOf(limit.toString()),
        ).use { c ->
            while (c.moveToNext()) out.add(TaskItem(c.getLong(0), c.getString(1)))
        }
        return out
    }

    fun topTask(): String? = openTasks(1).firstOrNull()?.title

    fun tasksLeft(): Int =
        db.rawQuery("SELECT COUNT(*) FROM tasks WHERE is_done = 0", null)
            .use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

    fun setTaskDone(id: Long, now: Long) {
        // Only open tasks: an old notification's "Done" must not move the finish time of a done task.
        db.execSQL("UPDATE tasks SET is_done = 1, done_at = ? WHERE id = ? AND is_done = 0", arrayOf<Any>(now, id))
    }

    fun tasksDoneBetween(start: Long, end: Long): Int =
        db.rawQuery(
            "SELECT COUNT(*) FROM task_log WHERE done_at >= ? AND done_at < ?",
            arrayOf(start.toString(), end.toString()),
        ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

    // ---------- habits ----------

    /**
     * [target] = times per day (1 = a plain yes/no habit), [count] = times done today.
     * Reminders: one at [reminder] when [every] is 0, otherwise every [every] minutes
     * from [reminder] to [until].
     */
    data class HabitItem(
        val id: Long,
        val name: String,
        val done: Boolean,
        val reminder: String?,
        val target: Int = 1,
        val count: Int = 0,
        val every: Int = 0,
        val until: String? = null,
    ) {
        val multi: Boolean get() = target > 1
    }

    fun habitsToday(day: String): List<HabitItem> {
        val out = ArrayList<HabitItem>()
        db.rawQuery(
            "SELECT h.id, h.name, COALESCE(l.done, 0), h.reminder_time, h.target, COALESCE(l.count, 0), " +
                "h.remind_every, h.remind_until FROM habits h " +
                "LEFT JOIN habit_logs l ON l.habit_id = h.id AND l.date = ? " +
                "WHERE h.is_active = 1 ORDER BY h.position ASC, h.id ASC",
            arrayOf(day),
        ).use { c ->
            while (c.moveToNext()) {
                out.add(
                    HabitItem(
                        id = c.getLong(0),
                        name = c.getString(1),
                        done = c.getInt(2) == 1,
                        reminder = if (c.isNull(3)) null else c.getString(3),
                        target = c.getInt(4).coerceAtLeast(1),
                        count = c.getInt(5),
                        every = c.getInt(6),
                        until = if (c.isNull(7)) null else c.getString(7),
                    )
                )
            }
        }
        return out
    }

    /** Ticks a habit fully done (count = target) or clears it. */
    fun setHabitDone(id: Long, day: String, done: Boolean) {
        // Only for habits that still exist (an old notification may point to a deleted one).
        db.execSQL(
            "INSERT OR REPLACE INTO habit_logs(habit_id, date, done, count) " +
                "SELECT id, ?, ?, CASE WHEN ? = 1 THEN target ELSE 0 END FROM habits WHERE id = ? AND is_active = 1",
            arrayOf<Any>(day, if (done) 1 else 0, if (done) 1 else 0, id),
        )
    }

    /**
     * One more (or one less) for a habit done several times a day. Done as soon as the
     * count reaches the target, however the ticks were spread over the day.
     * [cap] stops at the target (widget and notifications, where a stray tap can't be undone).
     */
    fun addHabitCount(id: Long, day: String, delta: Int, cap: Boolean = false) {
        val d = db
        d.beginTransaction()
        try {
            val target = d.rawQuery("SELECT target FROM habits WHERE id = ? AND is_active = 1", arrayOf(id.toString()))
                .use { c -> if (c.moveToFirst()) c.getInt(0).coerceAtLeast(1) else null } ?: return
            val current = d.rawQuery(
                "SELECT count FROM habit_logs WHERE habit_id = ? AND date = ?",
                arrayOf(id.toString(), day),
            ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }
            var next = (current + delta).coerceAtLeast(0)
            if (cap && delta > 0) next = minOf(next, maxOf(target, current))
            d.execSQL(
                "INSERT OR REPLACE INTO habit_logs(habit_id, date, done, count) VALUES (?, ?, ?, ?)",
                arrayOf<Any>(id, day, if (next >= target) 1 else 0, next),
            )
            d.setTransactionSuccessful()
        } finally {
            d.endTransaction()
        }
    }

    // ---------- task reminders ----------

    data class TaskReminder(val id: Long, val title: String, val at: Long, val repeatDaily: Boolean, val done: Boolean)

    /** Every task with a reminder: open ones, plus done repeat-daily ones (they come back tomorrow). */
    fun taskReminders(): List<TaskReminder> {
        val out = ArrayList<TaskReminder>()
        db.rawQuery(
            "SELECT id, title, remind_at, repeat_daily, is_done FROM tasks " +
                "WHERE remind_at IS NOT NULL AND (is_done = 0 OR repeat_daily = 1)",
            null,
        ).use { c ->
            while (c.moveToNext()) {
                out.add(TaskReminder(c.getLong(0), c.getString(1), c.getLong(2), c.getInt(3) == 1, c.getInt(4) == 1))
            }
        }
        return out
    }

    fun taskReminder(id: Long): TaskReminder? =
        db.rawQuery(
            "SELECT id, title, remind_at, repeat_daily, is_done FROM tasks WHERE id = ? AND remind_at IS NOT NULL",
            arrayOf(id.toString()),
        ).use { c ->
            if (c.moveToFirst()) TaskReminder(c.getLong(0), c.getString(1), c.getLong(2), c.getInt(3) == 1, c.getInt(4) == 1) else null
        }

    fun habitDoneCountBetween(fromDay: String, toDay: String): Int =
        db.rawQuery(
            "SELECT COUNT(*) FROM habit_logs WHERE done = 1 AND date >= ? AND date <= ?",
            arrayOf(fromDay, toDay),
        ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

    // ---------- focus ----------

    fun logFocusSession(start: Long, end: Long, apps: String) {
        val cv = ContentValues()
        cv.put("start_time", start)
        cv.put("end_time", end)
        cv.put("apps_blocked", apps)
        db.insert("focus_sessions", null, cv)
    }

    // ---------- backup ----------

    /** Flush WAL into the main file so a plain file copy is a complete backup. */
    /** true when everything was written into the main file (first result column 0 = not busy). */
    fun checkpoint(): Boolean =
        db.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", null).use { c -> c.moveToFirst() && c.getInt(0) == 0 }

    companion object {
        /** Single background thread for writes from the accessibility service. */
        private val io: ExecutorService = Executors.newSingleThreadExecutor()

        /** Run on the IO thread. Errors are logged, never thrown (an uncaught one would crash the app). */
        fun runIo(block: () -> Unit) {
            io.execute {
                try {
                    block()
                } catch (e: Exception) {
                    Log.w("EwBrother", "background task failed", e)
                }
            }
        }

        /** Run on the IO thread and wait for the result. Never call from the IO thread itself. */
        fun <T> callIo(block: () -> T): T = io.submit(java.util.concurrent.Callable { block() }).get()

        fun jsonList(raw: String?): List<String> = try {
            val arr = JSONArray(raw ?: "[]")
            List(arr.length()) { arr.optString(it) }.filter { it.isNotBlank() }
        } catch (e: Exception) {
            emptyList()
        }

        fun toJson(list: Collection<String>): String {
            val arr = JSONArray()
            list.forEach { arr.put(it) }
            return arr.toString()
        }
    }
}
