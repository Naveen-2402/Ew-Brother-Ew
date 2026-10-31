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
                if (Build.VERSION.SDK_INT >= 33) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7)
                }
                result.success(true)
            }
            "openBattery" -> {
                val direct = Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                )
                result.success(open(direct) || open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)))
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
        Store(this).checkpoint()
        val dbFile = getDatabasePath(EwDatabase.NAME)
        val out = contentResolver.openOutputStream(uri) ?: return "error: cannot write file"
        out.use { o -> dbFile.inputStream().use { it.copyTo(o) } }
        return "ok"
    }

    private fun importFrom(uri: Uri): String {
        val tmp = File(cacheDir, "import.db")
        val input = contentResolver.openInputStream(uri) ?: return "error: cannot read file"
        input.use { i -> tmp.outputStream().use { i.copyTo(it) } }

        // Must be an SQLite file with our tables.
        val header = ByteArray(15)
        tmp.inputStream().use { it.read(header) }
        if (String(header, Charsets.US_ASCII) != "SQLite format 3") {
            tmp.delete()
            return "error: not an Ew Brother Ew backup"
        }
        val valid = try {
            SQLiteDatabase.openDatabase(tmp.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                db.rawQuery(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('settings', 'tasks', 'habits', 'daily_stats')",
                    null,
                ).use { c -> c.moveToFirst() && c.getInt(0) == 4 }
            }
        } catch (e: Exception) {
            false
        }
        if (!valid) {
            tmp.delete()
            return "error: not an Ew Brother Ew backup"
        }

        val dbFile = getDatabasePath(EwDatabase.NAME)
        EwDatabase.closeInstance()
        File(dbFile.path + "-wal").delete()
        File(dbFile.path + "-shm").delete()
        tmp.copyTo(dbFile, overwrite = true)
        tmp.delete()
        EwDatabase.get(this).writableDatabase // reopen + migrate older backups
        EwAccessibilityService.reloadFromAnyThread(full = true)
        Store.runIo {
            AlarmScheduler.scheduleAll(this)
            TodayWidget.updateAll(this)
        }
        return "ok"
    }

    companion object {
        private const val CHANNEL = "ew/native"
        private const val REQ_EXPORT = 41
        private const val REQ_IMPORT = 42

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
