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
                // 2 -> { db.execSQL("ALTER TABLE ...") }
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

    private fun insertDefaultSettings(db: SQLiteDatabase) {
        for ((k, v) in Keys.DEFAULTS) {
            db.execSQL("INSERT OR IGNORE INTO settings(key, value) VALUES (?, ?)", arrayOf(k, v))
        }
    }

    companion object {
        const val NAME = "focuspal.db"
        const val VERSION = 1

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
