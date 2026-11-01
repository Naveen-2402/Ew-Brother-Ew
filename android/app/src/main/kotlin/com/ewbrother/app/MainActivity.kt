package com.ewbrother.app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import com.ewbrother.app.data.EwDatabase
import com.ewbrother.app.data.Keys
import com.ewbrother.app.data.Store
import com.ewbrother.app.notify.AlarmScheduler
import com.ewbrother.app.notify.Notifier
import com.ewbrother.app.service.EwAccessibilityService
import com.ewbrother.app.usage.UsageReader
import com.ewbrother.app.widget.TodayWidget
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream

/**
 * Flutter <-> native bridge on channel "ew/native".
 * Method names MUST match lib/core/native_bridge.dart.
 */
class MainActivity : FlutterActivity() {

    private val main = Handler(Looper.getMainLooper())
    private var pendingBackup: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result -> handle(call, result) }
        channel = ch
        Notifier.ensureChannels(this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "dbPath" -> {
                // Opening through the helper runs schema creation/migrations first.
                result.success(EwDatabase.get(this).writableDatabase.path)
            }
            "permissions" -> result.success(permissions())
            "openAccessibility" -> result.success(open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)))
            "openUsageAccess" -> result.success(open(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)))
            "requestNotifications" -> {
                if (Build.VERSION.SDK_INT >= 33 && !Notifier.canPost(this)) {
                    val prefs = getSharedPreferences("perm", MODE_PRIVATE)
                    val asked = prefs.getBoolean("notif_asked", false)
                    if (asked && !shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
                        // Denied twice: Android no longer shows the dialog, so open the app's notification settings.
                        val settings = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        if (!open(settings)) open(appDetails())
                    } else {
                        prefs.edit().putBoolean("notif_asked", true).apply()
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
                    }
                }
                result.success(true)
            }
            "openNotificationSettings" -> {
                val settings = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                result.success(open(settings) || open(appDetails()))
            }
            "openBattery" -> {
                // "unrestricted": Android's one-tap "allow" dialog while still restricted.
                // Otherwise (or "saver"): the page where you pick the mode yourself; on HyperOS that's
                // the per-app battery saver page (No restrictions / Battery saver / Restrict).
                val mode = call.argument<String>("mode") ?: "unrestricted"
                val pm = getSystemService(PowerManager::class.java)!!
                val direct = Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                )
                val miui = Intent()
                    .setComponent(ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"))
                    .putExtra("package_name", packageName)
                    .putExtra("package_label", "Ew Brother Ew")
                val opened = (mode == "unrestricted" && !pm.isIgnoringBatteryOptimizations(packageName) && open(direct)) ||
                    open(miui) ||
                    open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) ||
                    open(appDetails())
                result.success(opened)
            }
            "openAutostart" -> {
                val miui = Intent().setComponent(
                    ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity",
                    )
                )
                result.success(open(miui) || open(appDetails()))
            }
            "openAppDetails" -> result.success(open(appDetails()))
            "settingsChanged" -> {
                EwAccessibilityService.reloadFromAnyThread()
                Store.runIo {
                    AlarmScheduler.scheduleAll(this)
                    Notifier.refreshStatus(this)
                    TodayWidget.updateAll(this)
                }
                result.success(true)
            }
            "dataChanged" -> {
                Store.runIo {
                    // A task finished or deleted in the app: take down its reminder if it's showing.
                    val store = Store(this)
                    Store.jsonList(store.get(Keys.ALARM_TASK_IDS)).mapNotNull { it.toLongOrNull() }.forEach { id ->
                        val t = store.taskReminder(id)
                        if (t == null || t.done) Notifier.cancel(this, Notifier.ID_TASK_BASE + id.toInt())
                    }
                    TodayWidget.updateAll(this)
                    AlarmScheduler.scheduleAll(this)
                }
                result.success(true)
            }
            "usage" -> {
                val start = (call.argument<Number>("start") ?: 0).toLong()
                val end = (call.argument<Number>("end") ?: System.currentTimeMillis()).toLong()
                Thread {
                    val list = try {
                        UsageReader.foreground(this, start, end)
                    } catch (e: Exception) {
                        emptyList()
                    }
                    main.post { result.success(list) }
                }.start()
            }
            "launchableApps" -> {
                Thread {
                    val list = try {
                        UsageReader.launchableApps(this)
                    } catch (e: Exception) {
                        emptyList()
                    }
                    main.post { result.success(list) }
                }.start()
            }
            "detectionLog" -> result.success(EwAccessibilityService.instance?.detectionLog() ?: emptyList<String>())
            "previewPause" -> {
                val svc = EwAccessibilityService.instance
                svc?.previewPause()
                result.success(svc != null)
            }
            "exportBackup" -> {
                val name = call.argument<String>("fileName") ?: "ew-brother-backup.db"
                val i = Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("application/octet-stream")
                    .putExtra(Intent.EXTRA_TITLE, name)
                startForBackup(i, REQ_EXPORT, result)
            }
            "importBackup" -> {
                val i = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*")
                startForBackup(i, REQ_IMPORT, result)
            }
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------- permissions

    private fun permissions(): Map<String, Boolean> {
        val pm = getSystemService(PowerManager::class.java)!!
        return mapOf(
            "accessibility" to accessibilityEnabled(),
            "serviceRunning" to (EwAccessibilityService.instance != null),
            "usage" to UsageReader.hasAccess(this),
            "notifications" to Notifier.canPost(this),
            "battery" to pm.isIgnoringBatteryOptimizations(packageName),
        )
    }

    private fun accessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
        return enabled.split(':').any {
            val cn = ComponentName.unflattenFromString(it)
            cn != null && cn.packageName == packageName && cn.className == EwAccessibilityService::class.java.name
        }
    }

    private fun appDetails() =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))

    private fun open(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }

    // ---------------------------------------------------------------- backup (F13)

    private fun startForBackup(intent: Intent, request: Int, result: MethodChannel.Result) {
        if (pendingBackup != null) {
            result.error("busy", "A backup is already in progress", null)
            return
        }
        pendingBackup = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, request)
        } catch (e: ActivityNotFoundException) {
            pendingBackup = null
            result.error("no_picker", "No file picker found", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // Flutter refreshes the permission list on this event.
        if (requestCode == REQ_NOTIF) notifyFlutter("serviceChanged")
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_EXPORT && requestCode != REQ_IMPORT) return
        val result = pendingBackup ?: return
        pendingBackup = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success("cancelled")
            return
        }
        Thread {
            val outcome = try {
                if (requestCode == REQ_EXPORT) exportTo(uri) else importFrom(uri)
            } catch (e: Exception) {
                "error: ${e.message}"
            }
            main.post { result.success(outcome) }
        }.start()
    }

    private fun exportTo(uri: Uri): String {
        // On the IO thread: no reel write can land while the file is being copied.
        return Store.callIo {
            if (!Store(this).checkpoint()) return@callIo "error: the database is busy, try again in a moment"
            val dbFile = getDatabasePath(EwDatabase.NAME)
            val out = contentResolver.openOutputStream(uri) ?: return@callIo "error: cannot write file"
            out.use { o -> dbFile.inputStream().use { it.copyTo(o) } }
            "ok"
        }
    }

    private fun importFrom(uri: Uri): String {
        val tmp = File(cacheDir, "import.db")
        SQLiteDatabase.deleteDatabase(tmp) // also removes any -wal/-shm left from an earlier try
        val input = contentResolver.openInputStream(uri) ?: return "error: cannot read file"
        input.use { i ->
            // Check the header before copying anything, and cap the size.
            val header = ByteArray(16)
            if (readFully(i, header) < 16 || String(header, 0, 15, Charsets.US_ASCII) != "SQLite format 3") {
                return "error: $NOT_A_BACKUP"
            }
            tmp.outputStream().use { o ->
                o.write(header)
                val buf = ByteArray(64 * 1024)
                var total = header.size.toLong()
                while (true) {
                    val n = i.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_BACKUP_BYTES) {
                        o.close()
                        SQLiteDatabase.deleteDatabase(tmp)
                        return "error: the file is too big to be a backup"
                    }
                    o.write(buf, 0, n)
                }
            }
        }

        val problem = validateBackup(tmp)
        if (problem != null) {
            SQLiteDatabase.deleteDatabase(tmp)
            return "error: $problem"
        }

        // Swap on the single IO thread so no queued reel write lands in the wrong file.
        // replaceWith keeps the current data and puts it back if the new file won't open.
        val swapped = Store.callIo { EwDatabase.replaceWith(this, tmp) }
        SQLiteDatabase.deleteDatabase(tmp)
        if (!swapped) return "error: the backup could not be opened. Your data was not changed."

        EwAccessibilityService.reloadFromAnyThread(full = true)
        Store.runIo {
            AlarmScheduler.scheduleAll(this)
            TodayWidget.updateAll(this)
        }
        return "ok"
    }

    /** null when [file] is a healthy backup from this or an older app version, else the reason. */
    private fun validateBackup(file: File): String? {
        try {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                val version = db.version
                if (version < 1) return NOT_A_BACKUP
                if (version > EwDatabase.VERSION) return "this backup is from a newer app version. Update the app first."
                val check = db.rawQuery("PRAGMA quick_check", null).use { c ->
                    if (c.moveToFirst()) c.getString(0) else ""
                }
                if (check != "ok") return "the backup file is damaged"

                val tables = HashSet<String>()
                var unexpected = false
                db.rawQuery("SELECT type, name FROM sqlite_master", null).use { c ->
                    while (c.moveToNext()) {
                        val type = c.getString(0)
                        val name = c.getString(1)
                        when (type) {
                            "table" -> tables.add(name)
                            "trigger" -> if (name !in EwDatabase.KNOWN_TRIGGERS) unexpected = true
                            "view" -> unexpected = true
                        }
                    }
                }
                if (!tables.containsAll(EwDatabase.REQUIRED_TABLES)) return NOT_A_BACKUP
                // A backup we made never contains other triggers or views; refuse anything that does.
                if (unexpected) return "the backup contains database code this app didn't create"
            }
        } catch (e: Exception) {
            return NOT_A_BACKUP
        }
        return null
    }

    private fun readFully(input: InputStream, buf: ByteArray): Int {
        var off = 0
        while (off < buf.size) {
            val n = input.read(buf, off, buf.size - off)
            if (n < 0) break
            off += n
        }
        return off
    }

    companion object {
        private const val CHANNEL = "ew/native"
        private const val REQ_EXPORT = 41
        private const val REQ_IMPORT = 42
        private const val REQ_NOTIF = 7
        private const val MAX_BACKUP_BYTES = 200L * 1024 * 1024
        private const val NOT_A_BACKUP = "not an Ew Brother Ew backup"

        @Volatile
        private var channel: MethodChannel? = null

        /** Tell the Flutter UI something changed (safe from any thread; no-op if UI is closed). */
        fun notifyFlutter(method: String) {
            Handler(Looper.getMainLooper()).post {
                try {
                    channel?.invokeMethod(method, null)
                } catch (ignored: Exception) {
                }
            }
        }
    }
}
