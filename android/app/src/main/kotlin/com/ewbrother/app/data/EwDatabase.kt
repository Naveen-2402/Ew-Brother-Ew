package com.ewbrother.app.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * Owner of the SQLite schema (focuspal.db).
 *
 * Flutter (sqflite) opens the SAME file but never creates or migrates it: it first calls the
 * native `dbPath` method, which goes through this helper so migrations always run here.
 * The accessibility service can start after a reboot before the Flutter UI ever opens,
 * which is why the schema lives on the native side.
 *
 * Migrations are additive and versioned so an app update never wipes data.
 * To change the schema: bump VERSION and add a `when` branch in [migrate].
 */
class EwDatabase private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, NAME, null, VERSION) {

    init {
        setWriteAheadLoggingEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        migrate(db, 0, VERSION)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        migrate(db, oldVersion, newVersion)
    }

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        // New settings keys added in later versions get their defaults without touching user values.
        if (!db.isReadOnly) insertDefaultSettings(db)
    }

    private fun migrate(db: SQLiteDatabase, from: Int, to: Int) {
        for (v in (from + 1)..to) {
            when (v) {
                1 -> createV1(db)
                2 -> createV2TaskLog(db)
            }
        }
    }

    private fun createV1(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE reel_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                date TEXT NOT NULL)"""
        )
        db.execSQL("CREATE INDEX idx_reel_events_date ON reel_events(date)")

        db.execSQL(
            """CREATE TABLE daily_stats (
                date TEXT NOT NULL,
                app TEXT NOT NULL,
                reel_count INTEGER NOT NULL DEFAULT 0,
                reel_seconds INTEGER NOT NULL DEFAULT 0,
                screen_seconds INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (date, app))"""
        )
        db.execSQL("CREATE INDEX idx_daily_stats_date ON daily_stats(date)")

        db.execSQL(
            """CREATE TABLE app_usage (
                date TEXT NOT NULL,
                package_name TEXT NOT NULL,
                app_label TEXT NOT NULL,
                seconds INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (date, package_name))"""
        )

        db.execSQL(
            """CREATE TABLE tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                is_done INTEGER NOT NULL DEFAULT 0,
                is_top3 INTEGER NOT NULL DEFAULT 0,
                repeat_daily INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                done_at INTEGER,
                position INTEGER NOT NULL DEFAULT 0)"""
        )

        db.execSQL(
            """CREATE TABLE habits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                icon TEXT NOT NULL DEFAULT 'spark',
                reminder_time TEXT,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL,
                position INTEGER NOT NULL DEFAULT 0)"""
        )

        db.execSQL(
            """CREATE TABLE habit_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                habit_id INTEGER NOT NULL,
                date TEXT NOT NULL,
                done INTEGER NOT NULL DEFAULT 1,
                UNIQUE (habit_id, date))"""
        )
        db.execSQL("CREATE INDEX idx_habit_logs_habit_date ON habit_logs(habit_id, date)")

        db.execSQL("CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")

        db.execSQL(
            """CREATE TABLE focus_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time INTEGER NOT NULL,
                end_time INTEGER NOT NULL,
                apps_blocked TEXT NOT NULL)"""
        )

        insertDefaultSettings(db)
    }

    /**
     * v2: history of finished tasks. Repeat-daily tasks are reset every morning, so the tasks
     * table alone forgets past completions. Triggers log every 0 -> 1 transition, whoever makes
     * it (Flutter, notification action). Un-ticking today's task removes its log row in code.
     */
    private fun createV2TaskLog(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE IF NOT EXISTS task_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                done_at INTEGER NOT NULL,
                UNIQUE (task_id, done_at))"""
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_task_log_done_at ON task_log(done_at)")
        db.execSQL(
            """CREATE TRIGGER IF NOT EXISTS trg_task_done AFTER UPDATE OF is_done ON tasks
                WHEN NEW.is_done = 1 AND OLD.is_done = 0 AND NEW.done_at IS NOT NULL
                BEGIN
                    INSERT OR IGNORE INTO task_log(task_id, title, done_at) VALUES (NEW.id, NEW.title, NEW.done_at);
                END"""
        )
        db.execSQL(
            """CREATE TRIGGER IF NOT EXISTS trg_task_insert_done AFTER INSERT ON tasks
                WHEN NEW.is_done = 1 AND NEW.done_at IS NOT NULL
                BEGIN
                    INSERT OR IGNORE INTO task_log(task_id, title, done_at) VALUES (NEW.id, NEW.title, NEW.done_at);
                END"""
        )
        // Keep the title in history current when a task is renamed.
        db.execSQL(
            """CREATE TRIGGER IF NOT EXISTS trg_task_rename AFTER UPDATE OF title ON tasks
                BEGIN
                    UPDATE task_log SET title = NEW.title WHERE task_id = NEW.id;
                END"""
        )
        // Tasks already done before this version.
        db.execSQL(
            "INSERT OR IGNORE INTO task_log(task_id, title, done_at) " +
                "SELECT id, title, done_at FROM tasks WHERE is_done = 1 AND done_at IS NOT NULL"
        )
    }

    private fun insertDefaultSettings(db: SQLiteDatabase) {
        for ((k, v) in Keys.DEFAULTS) {
            db.execSQL("INSERT OR IGNORE INTO settings(key, value) VALUES (?, ?)", arrayOf(k, v))
        }
    }

    companion object {
        const val NAME = "focuspal.db"
        const val VERSION = 2

        @Volatile
        private var instance: EwDatabase? = null
        private val lock = Any()

        fun get(context: Context): EwDatabase =
            instance ?: synchronized(lock) {
                instance ?: EwDatabase(context).also { instance = it }
            }

        /** Used by backup import: close so the file can be replaced. */
        fun closeInstance() {
            synchronized(lock) {
                instance?.close()
                instance = null
            }
        }
    }
}
