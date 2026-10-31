package com.ewbrother.app.usage

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process

/** F4: foreground time per app from UsageStatsManager events (more accurate than daily buckets). */
object UsageReader {

    fun hasAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(AppOpsManager::class.java)!!
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** List of maps {package, label, seconds} sorted by time, launcher and this app excluded. */
    fun foreground(ctx: Context, start: Long, end: Long): List<Map<String, Any>> {
        if (!hasAccess(ctx)) return emptyList()
        val usm = ctx.getSystemService(UsageStatsManager::class.java)!!
        val events = usm.queryEvents(start, end) ?: return emptyList()
        val ev = UsageEvents.Event()
        val open = HashMap<String, Long>() // "pkg/class" -> resumed at
        val totals = HashMap<String, Long>()

        fun close(key: String, at: Long) {
            val s = open.remove(key) ?: return
            val pkg = key.substringBefore('/')
            totals[pkg] = (totals[pkg] ?: 0L) + (at - s).coerceAtLeast(0)
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            val key = ev.packageName + "/" + (ev.className ?: "")
            when (ev.eventType) {
                RESUMED -> if (!open.containsKey(key)) open[key] = ev.timeStamp
                PAUSED, STOPPED -> close(key, ev.timeStamp)
                SCREEN_OFF, SHUTDOWN -> open.keys.toList().forEach { close(it, ev.timeStamp) }
            }
        }
        // Whatever is still open is the app in front right now.
        open.keys.toList().forEach { close(it, end) }

        val pm = ctx.packageManager
        val skip = HashSet<String>()
        skip.add(ctx.packageName)
        homePackage(ctx)?.let { skip.add(it) }
        skip.add("com.android.systemui")

        return totals.entries
            .filter { it.key !in skip && it.value >= 1000 }
            .sortedByDescending { it.value }
            .map { (pkg, ms) ->
                mapOf("package" to pkg, "label" to label(pm, pkg), "seconds" to (ms / 1000).toInt())
            }
    }

    private fun label(pm: PackageManager, pkg: String): String = try {
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    private fun homePackage(ctx: Context): String? {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return ctx.packageManager.resolveActivity(i, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName
    }

    /** Launchable apps for the focus-mode picker. */
    fun launchableApps(ctx: Context): List<Map<String, String>> {
        val pm = ctx.packageManager
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(i, 0)
            .map { it.activityInfo.packageName }
            .distinct()
            .filter { it != ctx.packageName }
            .map { mapOf("package" to it, "label" to label(pm, it)) }
            .sortedBy { it["label"]!!.lowercase() }
    }

    // UsageEvents.Event constants (values are stable across API levels).
    private const val RESUMED = 1 // ACTIVITY_RESUMED / MOVE_TO_FOREGROUND
    private const val PAUSED = 2 // ACTIVITY_PAUSED / MOVE_TO_BACKGROUND
    private const val STOPPED = 23 // ACTIVITY_STOPPED (API 29)
    private const val SCREEN_OFF = 16 // SCREEN_NON_INTERACTIVE (API 28)
    private const val SHUTDOWN = 26 // DEVICE_SHUTDOWN (API 29)
}
