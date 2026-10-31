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

    fun today(now: Long = System.currentTimeMillis()): String = LogicalDay.keyFor(now, resetHour())

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
        db.execSQL("UPDATE tasks SET is_done = 1, done_at = ? WHERE id = ?", arrayOf<Any>(now, id))
    }

    fun tasksDoneBetween(start: Long, end: Long): Int =
        db.rawQuery(
            "SELECT COUNT(*) FROM tasks WHERE done_at >= ? AND done_at < ?",
            arrayOf(start.toString(), end.toString()),
        ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

    // ---------- habits ----------

    data class HabitItem(val id: Long, val name: String, val done: Boolean, val reminder: String?)

    fun habitsToday(day: String): List<HabitItem> {
        val out = ArrayList<HabitItem>()
        db.rawQuery(
            "SELECT h.id, h.name, COALESCE(l.done, 0), h.reminder_time FROM habits h " +
                "LEFT JOIN habit_logs l ON l.habit_id = h.id AND l.date = ? " +
                "WHERE h.is_active = 1 ORDER BY h.position ASC, h.id ASC",
            arrayOf(day),
        ).use { c ->
            while (c.moveToNext()) {
                out.add(
                    HabitItem(
                        c.getLong(0),
                        c.getString(1),
                        c.getInt(2) == 1,
                        if (c.isNull(3)) null else c.getString(3),
                    )
                )
            }
        }
        return out
    }

    fun setHabitDone(id: Long, day: String, done: Boolean) {
        db.execSQL(
            "INSERT OR REPLACE INTO habit_logs(habit_id, date, done) VALUES (?, ?, ?)",
            arrayOf<Any>(id, day, if (done) 1 else 0),
        )
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
    fun checkpoint() {
        db.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", null).use { it.moveToFirst() }
    }

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
