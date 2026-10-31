package com.ewbrother.app.service

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import com.ewbrother.app.MainActivity
import com.ewbrother.app.data.Keys
import com.ewbrother.app.data.LogicalDay
import com.ewbrother.app.data.Store
import com.ewbrother.app.detect.DetectionRules
import com.ewbrother.app.detect.ReelDetector
import com.ewbrother.app.notify.Notifier
import com.ewbrother.app.overlay.Bubble
import com.ewbrother.app.overlay.OverlayStyle
import com.ewbrother.app.overlay.ScreenOverlay
import com.ewbrother.app.widget.TodayWidget
import java.util.Calendar

/**
 * F1 counter, F2 pause, F3 daily limit, floating bubble, F9 smart interrupt, F10 focus mode.
 *
 * Speed: counts are kept in memory, so the pause decision and overlay happen on the event
 * thread in a few ms; database writes go to a background thread.
 */
class EwAccessibilityService : AccessibilityService() {

    private lateinit var store: Store
    private lateinit var detector: ReelDetector
    private lateinit var screen: ScreenOverlay
    private lateinit var bubble: Bubble

    private var settings: Map<String, String> = Keys.DEFAULTS

    // Today's counts in memory: app key -> count / seconds.
    private var day = ""
    private val counts = HashMap<String, Int>()
    private val seconds = HashMap<String, Int>()

    // Foreground tracking.
    private var foreground: String? = null
    private var bubbleHiddenFor: String? = null
    private val lastLeftAt = HashMap<String, Long>()

    // Watch time: when the current reel started, per package.
    private val reelStartedAt = HashMap<String, Long>()

    // A pause that was escaped by leaving the app comes back with the time it had left.
    private var pendingPausePkg: String? = null
    private var pendingPauseLeftMs = 0L
    private var pendingPauseTotalMs = 0L

    private var imePackage: String? = null

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (i.action == Intent.ACTION_SCREEN_OFF) flushWatchTime(System.currentTimeMillis())
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        store = Store(this)
        detector = ReelDetector {
            val m = resources.displayMetrics
            m.widthPixels to m.heightPixels
        }
        screen = ScreenOverlay(this)
        bubble = Bubble(
            this,
            onMoved = { x, y ->
                Store.runIo {
                    store.set(Keys.BUBBLE_X, x.toString())
                    store.set(Keys.BUBBLE_Y, y.toString())
                }
            },
            onLongPress = {
                bubbleHiddenFor = foreground
                bubble.hide()
            },
        )
        reload()
        imePackage = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
            ?.substringBefore('/')
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
        Notifier.refreshStatus(this)
        TodayWidget.updateAll(this)
        MainActivity.notifyFlutter("serviceChanged")
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(screenOff)
        } catch (ignored: Exception) {
        }
        if (::screen.isInitialized) screen.dismiss()
        if (::bubble.isInitialized) bubble.hide()
        instance = null
        Notifier.refreshStatus(this)
        MainActivity.notifyFlutter("serviceChanged")
        super.onDestroy()
    }

    override fun onInterrupt() {}

    /**
     * Re-read settings. Counts are re-read only on a new day or when [full] (backup import),
     * because in-memory counts may be ahead of writes still queued on Store.io.
     */
    fun reload(full: Boolean = false) {
        settings = store.settings()
        detector.extraIds = Store.jsonList(settings[Keys.EXTRA_REEL_IDS]).toSet()
        val today = store.today()
        if (full || today != day) loadDay(today)
        if (!on(Keys.MONITOR_ON) || !on(Keys.BUBBLE_ON)) {
            bubble.hide()
        } else if (isReelApp(foreground)) {
            bubble.hide() // re-show with new size/position
            showBubble()
        }
    }

    private fun loadDay(today: String) {
        day = today
        counts.clear()
        seconds.clear()
        store.dailyCounts(today).forEach { (app, v) ->
            counts[app] = v[0]
            seconds[app] = v[1]
        }
        Store.runIo {
            store.pruneIfNeeded(today)
            store.rolloverTasks(LogicalDay.startOf(today, resetHour()))
        }
    }

    // ------------------------------------------------------------------ events

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkg = event.packageName?.toString() ?: return
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> onWindowChanged(pkg)
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                if (pkg !in DetectionRules.APPS) return // cheap early exit for all other apps
                onReelScroll(pkg, event)
            }
        }
    }

    private fun onWindowChanged(pkg: String) {
        if (pkg in DetectionRules.IGNORED_PACKAGES || pkg == imePackage || pkg == packageName) return
        val old = foreground
        if (pkg == old) return
        foreground = pkg
        val now = System.currentTimeMillis()

        if (old != null && isReelApp(old)) {
            lastLeftAt[old] = now
            flushWatchTime(now, old)
            detector.reset(old)
            if (pendingPausePkg == old) {
                val left = if (screen.isShowing) screen.remainingMs() else pendingPauseLeftMs
                // Leaving mid-countdown: remember what's left so it comes back. Finished = served.
                if (left > 0) pendingPauseLeftMs = left else clearPendingPause()
            }
            if (screen.isShowing) screen.dismiss()
        }
        if (bubbleHiddenFor != null && bubbleHiddenFor != pkg) bubbleHiddenFor = null

        // F10 focus mode applies to any chosen app, even when the reel monitor is off.
        if (focusBlocks(pkg, now)) {
            bubble.hide()
            showFocusGate(pkg)
            return
        }

        if (!isReelApp(pkg)) {
            bubble.hide()
            if (screen.isShowing) screen.dismiss()
            return
        }

        if (!on(Keys.MONITOR_ON)) return
        ensureToday(now)
        showBubble()

        // Escaped pause comes back.
        if (pendingPausePkg == pkg && pendingPauseLeftMs > 0) {
            showPause(pkg, pendingPauseTotalMs, pendingPauseLeftMs)
            return
        }
        // F3: already over the hard limit with "block".
        if (limitReached() && settings[Keys.LIMIT_ACTION] != "pause30") {
            showLimitBlock()
            return
        }
        // F9: smart interrupt when opening Instagram/YouTube.
        if (on(Keys.INTERRUPT_ON) && now - (lastLeftAt[pkg] ?: 0L) > DetectionRules.INTERRUPT_COOLDOWN_MS) {
            showInterrupt(pkg)
        }
    }

    private fun onReelScroll(pkg: String, event: AccessibilityEvent) {
        if (!on(Keys.MONITOR_ON)) return
        val now = System.currentTimeMillis()
        if (foreground != pkg) {
            foreground = pkg
            showBubble()
        }
        ensureToday(now)
        val result = detector.onScroll(pkg, event, now)
        if (!result.inFeed) return
        if (reelStartedAt[pkg] == null) reelStartedAt[pkg] = now

        if (result.newReels <= 0) {
            // Inside the feed but no new reel: still enforce the block if over the limit.
            if (limitReached() && settings[Keys.LIMIT_ACTION] != "pause30" && !screen.isShowing) showLimitBlock()
            return
        }

        val app = DetectionRules.APPS.getValue(pkg)
        val started = reelStartedAt[pkg] ?: now
        val watched = ((now - started) / 1000).toInt().coerceIn(0, DetectionRules.MAX_SECONDS_PER_REEL)
        reelStartedAt[pkg] = now

        val before = counts[app] ?: 0
        val after = before + result.newReels
        counts[app] = after
        seconds[app] = (seconds[app] ?: 0) + watched

        val today = day
        Store.runIo { store.recordReels(app, result.newReels, now, today, watched) }

        updateBubble()
        TodayWidget.updateAll(this, throttled = true)
        MainActivity.notifyFlutter("reelCounted")
        if (on(Keys.STATUS_NOTIF_ON)) Notifier.refreshStatus(this, total())

        decidePause(pkg, app, before, after)
    }

    private fun decidePause(pkg: String, app: String, before: Int, after: Int) {
        if (screen.isShowing) return
        val total = total()
        if (on(Keys.LIMIT_ON) && total >= limit()) {
            if (settings[Keys.LIMIT_ACTION] == "pause30") {
                showPause(pkg, 30_000, 30_000)
            } else {
                showLimitBlock()
            }
            return
        }
        val key = if (app == "instagram") Keys.INTERVAL_INSTAGRAM else Keys.INTERVAL_YOUTUBE
        val interval = (settings[key]?.toIntOrNull() ?: 10).coerceIn(1, 100)
        // Crossed a multiple of the interval (handles quick swipes that add 2+ at once).
        if (after / interval > before / interval) {
            val ms = (settings[Keys.PAUSE_SECONDS]?.toIntOrNull() ?: 5).coerceIn(3, 15) * 1000L
            showPause(pkg, ms, ms)
        }
    }

    // ------------------------------------------------------------------ overlays

    private fun showPause(pkg: String, totalMs: Long, remainingMs: Long) {
        pendingPausePkg = pkg
        pendingPauseTotalMs = totalMs
        pendingPauseLeftMs = remainingMs
        val total = total()
        val reelMinutes = seconds.values.sum() / 60
        val top = store.topTask()
        val lines = ArrayList<String>()
        lines.add("$total reels today, about ${formatMinutes(reelMinutes)} on reels")
        if (top != null) lines.add("Top task: $top")
        screen.show(
            ScreenOverlay.Spec(
                headline = randomMessage(),
                lines = lines,
                totalMs = totalMs,
                remainingMs = remainingMs,
                primary = "Continue",
                secondary = "Close reels",
                calm = true,
                onPrimary = { clearPendingPause() },
                onSecondary = {
                    clearPendingPause()
                    goHome()
                },
            )
        )
    }

    private fun clearPendingPause() {
        pendingPausePkg = null
        pendingPauseLeftMs = 0
    }

    private fun showLimitBlock() {
        clearPendingPause()
        val reset = resetHour()
        screen.show(
            ScreenOverlay.Spec(
                headline = "That's ${limit()}. Done for today, brother.",
                lines = listOf("Reels open again at ${formatHour(reset)}."),
                totalMs = 0,
                remainingMs = 0,
                primary = null,
                secondary = "Close reels",
                calm = true,
                onSecondary = { goHome() },
            )
        )
    }

    private fun showInterrupt(pkg: String) {
        val appName = if (pkg == DetectionRules.INSTAGRAM) "Instagram" else "YouTube"
        screen.show(
            ScreenOverlay.Spec(
                headline = "What is your goal?",
                lines = listOf("Pick one, then decide."),
                totalMs = 5000,
                remainingMs = 5000,
                primary = "Open $appName",
                secondary = "Not now",
                calm = false,
                choices = listOf("Reply to a message", "Look up one thing", "Honestly, just scrolling"),
                onSecondary = { goHome() },
            )
        )
    }

    private fun showFocusGate(pkg: String) {
        val label = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (e: Exception) {
            pkg
        }
        screen.show(
            ScreenOverlay.Spec(
                headline = "Focus time till ${settings[Keys.FOCUS_END] ?: ""}",
                lines = listOf("$label is blocked right now."),
                totalMs = 0,
                remainingMs = 0,
                primary = "Allow 10 minutes",
                secondary = "Close $label",
                calm = false,
                onPrimary = {
                    val until = System.currentTimeMillis() + 10 * 60_000L
                    settings = settings + (Keys.FOCUS_OVERRIDE_UNTIL to until.toString())
                    Store.runIo { store.set(Keys.FOCUS_OVERRIDE_UNTIL, until.toString()) }
                },
                onSecondary = { goHome() },
            )
        )
    }

    private fun showBubble() {
        if (!on(Keys.MONITOR_ON) || !on(Keys.BUBBLE_ON)) return
        if (bubbleHiddenFor != null && bubbleHiddenFor == foreground) return
        if (!bubble.isShowing) {
            bubble.show(
                settings[Keys.BUBBLE_SIZE] ?: "medium",
                settings[Keys.BUBBLE_X]?.toIntOrNull() ?: -1,
                settings[Keys.BUBBLE_Y]?.toIntOrNull() ?: -1,
            )
        }
        updateBubble()
    }

    private fun updateBubble() {
        if (!bubble.isShowing) return
        val total = total()
        bubble.update(total, counts["instagram"] ?: 0, counts["youtube"] ?: 0, OverlayStyle.progressColor(total, limit()))
    }

    private fun goHome() {
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    // ------------------------------------------------------------------ helpers

    private fun on(key: String) = settings[key] == "1"

    private fun isReelApp(pkg: String?) = pkg != null && pkg in DetectionRules.APPS

    private fun total() = counts.values.sum()

    private fun limit() = (settings[Keys.LIMIT_REELS]?.toIntOrNull() ?: 100).coerceAtLeast(1)

    private fun limitReached() = on(Keys.LIMIT_ON) && total() >= limit()

    private fun resetHour() = settings[Keys.DAY_RESET_HOUR]?.toIntOrNull() ?: 4

    private fun ensureToday(now: Long) {
        val today = LogicalDay.keyFor(now, resetHour())
        if (today != day) {
            loadDay(today)
            TodayWidget.updateAll(this)
        }
    }

    private fun flushWatchTime(now: Long, only: String? = null) {
        val pkgs = if (only != null) listOf(only) else reelStartedAt.keys.toList()
        for (pkg in pkgs) {
            val started = reelStartedAt.remove(pkg) ?: continue
            val app = DetectionRules.APPS[pkg] ?: continue
            val secs = ((now - started) / 1000).toInt().coerceIn(0, DetectionRules.MAX_SECONDS_PER_REEL)
            if (secs <= 0) continue
            seconds[app] = (seconds[app] ?: 0) + secs
            val today = day
            Store.runIo { store.addReelSeconds(app, today, secs) }
        }
    }

    private fun randomMessage(): String {
        val list = Store.jsonList(settings[Keys.MESSAGES]).ifEmpty { Store.jsonList(Keys.DEFAULT_MESSAGES) }
        return list.random()
    }

    private fun formatMinutes(m: Int) = if (m < 60) "$m min" else "${m / 60} h ${m % 60} min"

    private fun formatHour(h: Int): String = when {
        h == 0 -> "midnight"
        h < 12 -> "$h AM"
        h == 12 -> "noon"
        else -> "${h - 12} PM"
    }

    /** Focus mode: inside the daily window, app is in the list, no active override. */
    private fun focusBlocks(pkg: String, now: Long): Boolean {
        if (!on(Keys.FOCUS_ON)) return false
        val apps = Store.jsonList(settings[Keys.FOCUS_APPS])
        if (pkg !in apps) return false
        if (now < (settings[Keys.FOCUS_OVERRIDE_UNTIL]?.toLongOrNull() ?: 0L)) return false
        val window = focusWindow(now) ?: return false
        // Log one focus_sessions row per window.
        if ((settings[Keys.FOCUS_LAST_LOGGED]?.toLongOrNull() ?: 0L) != window.first) {
            settings = settings + (Keys.FOCUS_LAST_LOGGED to window.first.toString())
            val appsJson = settings[Keys.FOCUS_APPS] ?: "[]"
            Store.runIo {
                store.set(Keys.FOCUS_LAST_LOGGED, window.first.toString())
                store.logFocusSession(window.first, window.second, appsJson)
            }
        }
        return true
    }

    /** (start, end) of the focus window containing [now], or null. Handles windows past midnight. */
    private fun focusWindow(now: Long): Pair<Long, Long>? {
        val (sh, sm) = hm(settings[Keys.FOCUS_START])
        val (eh, em) = hm(settings[Keys.FOCUS_END])
        val startMin = sh * 60 + sm
        val endMin = eh * 60 + em
        if (startMin == endMin) return null
        for (dayOffset in listOf(0, -1)) {
            val c = Calendar.getInstance()
            c.timeInMillis = now
            c.add(Calendar.DAY_OF_MONTH, dayOffset)
            c.set(Calendar.HOUR_OF_DAY, sh)
            c.set(Calendar.MINUTE, sm)
            c.set(Calendar.SECOND, 0)
            c.set(Calendar.MILLISECOND, 0)
            val start = c.timeInMillis
            val lengthMin = if (endMin > startMin) endMin - startMin else 24 * 60 - startMin + endMin
            val end = start + lengthMin * 60_000L
            if (now in start until end) return start to end
        }
        return null
    }

    private fun hm(s: String?): Pair<Int, Int> {
        val p = (s ?: "").split(":")
        return (p.getOrNull(0)?.toIntOrNull() ?: 0).coerceIn(0, 23) to
            (p.getOrNull(1)?.toIntOrNull() ?: 0).coerceIn(0, 59)
    }

    /** Lines for Settings > Detection check. */
    fun detectionLog(): List<String> = detector.log.toList()

    /** Settings > "Preview pause": shows the real overlay over whatever is on screen. */
    fun previewPause() {
        val ms = (settings[Keys.PAUSE_SECONDS]?.toIntOrNull() ?: 5).coerceIn(3, 15) * 1000L
        showPause(packageName, ms, ms)
        pendingPausePkg = null
    }

    companion object {
        @Volatile
        var instance: EwAccessibilityService? = null
            private set

        /** Settings changed somewhere (app, tile, notification): reload on the main thread. */
        fun reloadFromAnyThread(full: Boolean = false) {
            Handler(Looper.getMainLooper()).post { instance?.reload(full) }
        }
    }
}
