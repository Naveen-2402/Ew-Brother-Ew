package com.ewbrother.app.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.File

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
                3 -> createV3Counts(db)
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

    /**
     * v3: habits done several times a day, interval reminders, task reminders.
     * habit_logs.done stays the source of truth for streaks and stats (set to count >= target
     * when the tick is made), so every older query keeps working unchanged.
     */
    private fun createV3Counts(db: SQLiteDatabase) {
        addColumn(db, "habits", "target", "INTEGER NOT NULL DEFAULT 1")
        // Minutes between reminders; 0 = one reminder at reminder_time.
        addColumn(db, "habits", "remind_every", "INTEGER NOT NULL DEFAULT 0")
        // End of the reminder range ("HH:mm"); the range starts at reminder_time.
        addColumn(db, "habits", "remind_until", "TEXT")
        addColumn(db, "habit_logs", "count", "INTEGER NOT NULL DEFAULT 0")
        db.execSQL("UPDATE habit_logs SET count = 1 WHERE done = 1 AND count = 0")
        // Epoch ms. Repeat-daily tasks use only its time of day.
        addColumn(db, "tasks", "remind_at", "INTEGER")
    }

    private fun addColumn(db: SQLiteDatabase, table: String, column: String, type: String) {
        val exists = db.rawQuery("PRAGMA table_info($table)", null).use { c ->
            var found = false
            while (c.moveToNext()) if (c.getString(1) == column) found = true
            found
        }
        if (!exists) db.execSQL("ALTER TABLE $table ADD COLUMN $column $type")
    }

    private fun insertDefaultSettings(db: SQLiteDatabase) {
        for ((k, v) in Keys.DEFAULTS) {
            db.execSQL("INSERT OR IGNORE INTO settings(key, value) VALUES (?, ?)", arrayOf(k, v))
        }
    }

    companion object {
        const val NAME = "focuspal.db"
        const val VERSION = 3

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

        /** Triggers this app creates; a backup with any other trigger is refused. */
        val KNOWN_TRIGGERS = setOf("trg_task_done", "trg_task_insert_done", "trg_task_rename")

        val REQUIRED_TABLES = listOf(
            "settings", "tasks", "habits", "habit_logs", "daily_stats", "app_usage", "reel_events",
        )

        /**
         * Replace the database with [source] (an already validated backup).
         * Holds the lock for the whole swap, so [get] waits instead of opening a half-copied file.
         * The current file is kept aside and put back if the new one fails to open or migrate.
         */
        fun replaceWith(context: Context, source: File): Boolean {
            val app = context.applicationContext
            val dbFile = app.getDatabasePath(NAME)
            val staged = File(dbFile.path + ".incoming")
            val saved = File(dbFile.path + ".before-restore")
            // The slow copy happens before taking the lock, so readers aren't blocked by it.
            try {
                source.copyTo(staged, overwrite = true)
            } catch (e: Exception) {
                staged.delete()
                return false
            }
            return synchronized(lock) {
                instance?.close() // closing the last connection folds the WAL into the main file
                instance = null
                saved.delete()
                for (suffix in listOf("-wal", "-shm", "-journal")) File(dbFile.path + suffix).delete()
                // Keep the current data aside (a rename, so it can't half-fail like a copy).
                if (dbFile.exists() && !dbFile.renameTo(saved)) {
                    staged.delete()
                    return@synchronized false
                }
                var helper: EwDatabase? = null
                try {
                    if (!staged.renameTo(dbFile)) throw java.io.IOException("could not move the backup in place")
                    helper = EwDatabase(app)
                    helper.writableDatabase // opens and migrates an older backup
                    instance = helper
                    saved.delete()
                    true
                } catch (e: Exception) {
                    helper?.close()
                    SQLiteDatabase.deleteDatabase(dbFile)
                    staged.delete()
                    if (saved.exists()) saved.renameTo(dbFile) // put the old data back
                    false
                }
            }
        }
    }
}
