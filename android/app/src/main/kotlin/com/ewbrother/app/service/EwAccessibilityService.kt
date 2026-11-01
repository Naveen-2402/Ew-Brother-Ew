package com.ewbrother.app.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
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

    private val mainHandler = Handler(Looper.getMainLooper())

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

    // Time you can't cheat by changing the phone's clock or time zone:
    // wall time at service start, moved forward by the uptime clock (which can't be set by hand).
    // Only automatic (network) time re-anchors it, so a manual change is ignored.
    private var anchorWall = 0L
    private var anchorElapsed = 0L

    // When the current logical day really ends, on the uptime clock.
    private var dayEndElapsed = 0L

    private fun trustedNow(): Long = anchorWall + (SystemClock.elapsedRealtime() - anchorElapsed)

    private fun anchorClock() {
        anchorWall = System.currentTimeMillis()
        anchorElapsed = SystemClock.elapsedRealtime()
    }

    private val systemEvents = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    flushWatchTime(trustedNow())
                    mainHandler.removeCallbacks(pagerPoll) // no polling with the screen off
                }
                Intent.ACTION_SCREEN_ON -> startPagerPoll()
                Intent.ACTION_TIME_CHANGED -> if (autoTimeOn()) {
                    anchorClock()
                    if (day.isNotEmpty()) computeDayEnd()
                }
            }
        }
    }

    private fun autoTimeOn(): Boolean = try {
        Settings.Global.getInt(contentResolver, Settings.Global.AUTO_TIME, 0) == 1
    } catch (e: Exception) {
        false
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        // Apply the window-list flag right away. A flag added to the XML config in an app update
        // otherwise only takes effect after the service is turned off and on. Without it, events
        // and the screen tree only come from the "active" window, which can stay stuck on our own
        // focused overlay (interrupt, pause) after it closes: YouTube Shorts then weren't counted.
        try {
            serviceInfo = serviceInfo?.apply {
                flags = flags or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            }
        } catch (e: Exception) {
            Log.w(TAG, "service flags not applied", e)
        }
        store = Store(this)
        detector = ReelDetector {
            val m = resources.displayMetrics
            m.widthPixels to m.heightPixels
        }
        screen = ScreenOverlay(this, onClosed = { afterOverlayClosed() })
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
        anchorClock()
        reload()
        refreshImePackage()
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        filter.addAction(Intent.ACTION_TIME_CHANGED)
        filter.addAction(Intent.ACTION_SCREEN_ON)
        registerReceiver(systemEvents, filter)
        Notifier.refreshStatus(this)
        TodayWidget.updateAll(this)
        MainActivity.notifyFlutter("serviceChanged")
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(systemEvents)
        } catch (ignored: Exception) {
        }
        foreground = null // so a closing overlay below doesn't restart the Shorts check
        if (::screen.isInitialized) screen.dismiss()
        if (::bubble.isInitialized) bubble.hide()
        mainHandler.removeCallbacksAndMessages(null) // after dismiss: nothing it posted survives
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
        val fresh = try {
            store.settings()
        } catch (e: Exception) {
            Log.w(TAG, "reload failed", e)
            return
        }
        // "Allow 10 minutes" is written in the background; don't lose it to a reload that read first.
        val memOverride = settings[Keys.FOCUS_OVERRIDE_UNTIL]?.toLongOrNull() ?: 0L
        val dbOverride = fresh[Keys.FOCUS_OVERRIDE_UNTIL]?.toLongOrNull() ?: 0L
        if (memOverride > dbOverride) fresh[Keys.FOCUS_OVERRIDE_UNTIL] = memOverride.toString()
        settings = fresh
        detector.extraIds = Store.jsonList(settings[Keys.EXTRA_REEL_IDS]).toSet()
        if (full || day.isEmpty()) {
            loadDay(LogicalDay.keyFor(trustedNow(), resetHour()))
        } else {
            ensureToday(trustedNow())
        }
        scheduleFocusCheck()
        startPagerPoll() // monitor switched on/off
        if (!on(Keys.MONITOR_ON) || !on(Keys.BUBBLE_ON)) {
            bubble.hide()
        } else if (isReelApp(foreground)) {
            bubble.hide() // re-show with new size/position
            showBubble()
        }
    }

    private fun loadDay(today: String) {
        val stored = try {
            store.dailyCounts(today)
        } catch (e: Exception) {
            Log.w(TAG, "loadDay failed", e)
            if (today == day) return // keep what we have rather than dropping to 0
            emptyMap()
        }
        day = today
        counts.clear()
        seconds.clear()
        stored.forEach { (app, v) ->
            counts[app] = v[0]
            seconds[app] = v[1]
        }
        computeDayEnd()
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
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                // Our own overlays are ignored, but opening the Ew Brother app itself is a real app switch.
                val target = if (pkg == packageName && event.className?.toString() == MainActivity::class.java.name) {
                    SELF_PKG
                } else {
                    pkg
                }
                // In Instagram/YouTube, other packages also send window events without you leaving:
                // Play services pop-ups, toasts, HyperOS's video toolbox (it watches YouTube) and so on.
                // Treating those as "left the app" hid the bubble and stopped counting. Only switch
                // when the app really in front changed; re-check shortly in case the window list lags.
                if (isReelApp(foreground) && target != foreground && !isReelApp(target) && target != SELF_PKG) {
                    if (frontApp() == foreground) {
                        scheduleFrontCheck()
                        return
                    }
                }
                onWindowChanged(target)
            }
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                if (pkg !in DetectionRules.APPS) return // cheap early exit for all other apps
                onReelScroll(pkg, event)
            }
        }
    }

    private fun onWindowChanged(pkg: String) {
        if (pkg != foreground && pkg != SELF_PKG && pkg !in DetectionRules.APPS) refreshImePackage()
        if (pkg in DetectionRules.IGNORED_PACKAGES || pkg == imePackage || pkg == packageName) return
        val old = foreground
        if (pkg == old) return
        foreground = pkg
        val now = trustedNow()
        startPagerPoll() // starts in YouTube, stops itself anywhere else

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
        // A focus gate belongs to the app it was shown over; drop it when that app is left.
        if (old != null && !isReelApp(old) && screen.isShowing) screen.dismiss()
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
        // F3: over the limit, the block appears in the reel feed itself (see onReelScroll),
        // so the rest of Instagram/YouTube (messages, normal videos) stays usable.
        // F9: smart interrupt when opening Instagram/YouTube.
        if (on(Keys.INTERRUPT_ON) && now - (lastLeftAt[pkg] ?: 0L) > DetectionRules.INTERRUPT_COOLDOWN_MS) {
            showInterrupt(pkg)
        }
    }

    private fun onReelScroll(pkg: String, event: AccessibilityEvent) {
        if (!on(Keys.MONITOR_ON)) return
        if (foreground != pkg) {
            // A late scroll event can arrive just after you left; only count it as coming back
            // if the reel app is really the app in front.
            if (frontApp() != pkg) return
            // Back in the reel app without a window event (e.g. after a floating assistant or
            // pop-up): run the same entry checks, so an escaped pause or a focus block comes back.
            onWindowChanged(pkg)
            if (foreground != pkg || screen.isShowing) return
        }
        val now = trustedNow()
        ensureToday(now)
        var result = detector.onScroll(pkg, event, now)
        // While the pager is being checked on a timer (YouTube Shorts), that check does the
        // counting; a scroll event that does arrive mustn't count the same Short twice.
        if (result.newReels > 0 && detector.pollActive(pkg, now)) result = ReelDetector.Result(true, 0)
        onFeedResult(pkg, result, now)
    }

    // ------------------------------------------------------------------ YouTube Shorts pager check
    // YouTube sends one scroll event when Shorts opens and usually none for the swipes after it,
    // so scroll events alone never counted Shorts. While YouTube is in front (screen on, monitor
    // on), look at which Short fills the Shorts pager every PAGER_POLL_MS and count when it changes.

    private val pagerPoll = object : Runnable {
        override fun run() {
            if (!shouldPollPager()) return
            try {
                pollPager()
            } catch (e: Exception) {
                Log.w(TAG, "pager check failed", e)
            }
            mainHandler.postDelayed(this, DetectionRules.PAGER_POLL_MS)
        }
    }

    private fun shouldPollPager(): Boolean {
        val pkg = foreground ?: return false
        return on(Keys.MONITOR_ON) && DetectionRules.POLL_PAGER_IDS.containsKey(pkg)
    }

    /**
     * A pause, block or interrupt just closed. Our overlay had window focus, so start the YouTube
     * check fresh: new baseline (the Short underneath is the same one, so nothing is lost) and a
     * restarted timer. Instagram's scroll-event counting is left as it is.
     */
    private fun afterOverlayClosed() {
        foreground?.let { detector.resetPoll(it) }
        startPagerPoll()
    }

    private fun startPagerPoll() {
        mainHandler.removeCallbacks(pagerPoll)
        if (shouldPollPager()) mainHandler.postDelayed(pagerPoll, DetectionRules.PAGER_POLL_MS)
    }

    private fun pollPager() {
        val pkg = foreground ?: return
        if (screen.isShowing) return // pause or block on top: nothing can be swiped
        val root = appRoot(pkg) ?: return
        root.refresh() // live tree, not the cached one (see ReelDetector.onPagerPoll)
        // Built-in pager IDs, plus any ID for this app added in Settings > Detection check.
        val ids = DetectionRules.POLL_PAGER_IDS[pkg].orEmpty() + detector.extraIds.filter { it.startsWith("$pkg:id/") }
        for (id in ids) {
            val found = try {
                root.findAccessibilityNodeInfosByViewId(id)
            } catch (e: Exception) {
                null
            } ?: continue
            val pager = found.firstOrNull { it.isVisibleToUser } ?: continue
            val now = trustedNow()
            ensureToday(now)
            onFeedResult(pkg, detector.onPagerPoll(pkg, pager, id, now), now)
            return
        }
    }

    /** Root of [pkg]'s own app window (not our overlays, not the keyboard). */
    private fun appRoot(pkg: String): AccessibilityNodeInfo? {
        try {
            for (w in windows) {
                if (w.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
                val r = w.root ?: continue
                if (r.packageName?.toString() == pkg) return r
            }
        } catch (e: Exception) {
            Log.w(TAG, "window list failed", e)
        }
        return try {
            rootInActiveWindow?.takeIf { it.packageName?.toString() == pkg }
        } catch (e: Exception) {
            null
        }
    }

    /** Shared by scroll events and the pager check: watch time, limit block, count, pause. */
    private fun onFeedResult(pkg: String, result: ReelDetector.Result, now: Long) {
        if (!result.inFeed) return
        if (reelStartedAt[pkg] == null) reelStartedAt[pkg] = now

        if (result.newReels <= 0) {
            // Inside the feed but no new reel: still enforce the block if over the limit.
            if (limitReached() && blockAtLimit() && !screen.isShowing) showLimitBlock()
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
        Store.runIo {
            store.recordReels(app, result.newReels, now, today, watched)
            // After the write, so the widget reads the new count.
            TodayWidget.updateAll(this, throttled = true)
        }
        scheduleWidgetTrailing()

        updateBubble()
        MainActivity.notifyFlutter("reelCounted")
        if (on(Keys.STATUS_NOTIF_ON)) Notifier.refreshStatus(this, total())

        decidePause(pkg, app, before, after)
    }

    private var widgetTrailingPosted = false

    /** Widget updates are throttled to one per 3 s; this makes sure the last count of a burst lands. */
    private fun scheduleWidgetTrailing() {
        if (widgetTrailingPosted) return
        widgetTrailingPosted = true
        mainHandler.postDelayed({
            widgetTrailingPosted = false
            Store.runIo { TodayWidget.updateAll(this) }
        }, 3100)
    }

    private fun decidePause(pkg: String, app: String, before: Int, after: Int) {
        if (screen.isShowing) return
        val total = total()
        if (on(Keys.LIMIT_ON) && total >= limit()) {
            // Block switch on: reels are blocked. Off: a 30-second pause after every reel over the limit.
            if (blockAtLimit()) showLimitBlock() else showPause(pkg, LIMIT_PAUSE_MS, LIMIT_PAUSE_MS)
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

    /** [remember] = false for the Settings preview, so it never replaces or clears a real escaped pause. */
    private fun showPause(pkg: String, totalMs: Long, remainingMs: Long, remember: Boolean = true) {
        if (remember) {
            pendingPausePkg = pkg
            pendingPauseTotalMs = totalMs
            pendingPauseLeftMs = remainingMs
        }
        val total = total()
        val reelMinutes = seconds.values.sum() / 60
        val top = try {
            store.topTask()
        } catch (e: Exception) {
            null
        }
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
                onPrimary = { if (remember) clearPendingPause() },
                onSecondary = {
                    if (remember) clearPendingPause()
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
                    val until = trustedNow() + 10 * 60_000L
                    settings = settings + (Keys.FOCUS_OVERRIDE_UNTIL to until.toString())
                    Store.runIo { store.set(Keys.FOCUS_OVERRIDE_UNTIL, until.toString()) }
                    scheduleFocusCheck()
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
        val limitOn = on(Keys.LIMIT_ON)
        // Without a hard limit the ring still fills toward the soft limit of 100 (same as the app).
        val ringLimit = if (limitOn) limit() else 100
        val app = DetectionRules.APPS[foreground] ?: "instagram"
        val key = if (app == "youtube") Keys.INTERVAL_YOUTUBE else Keys.INTERVAL_INSTAGRAM
        val interval = (settings[key]?.toIntOrNull() ?: 10).coerceIn(1, 100)
        val appCount = counts[app] ?: 0
        bubble.update(
            Bubble.State(
                total = total,
                instagram = counts["instagram"] ?: 0,
                youtube = counts["youtube"] ?: 0,
                color = OverlayStyle.progressColor(total, ringLimit),
                progress = total.toFloat() / ringLimit,
                nextPauseIn = interval - appCount % interval,
                left = if (limitOn) limit() - total else null,
            )
        )
    }

    private fun goHome() {
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    // ------------------------------------------------------------------ helpers

    private fun on(key: String) = settings[key] == "1"

    /** Limit switch: "block" blocks the reel feeds; "pause30" gives a 30-second pause per reel instead. */
    private fun blockAtLimit() = settings[Keys.LIMIT_ACTION] != "pause30"

    private fun refreshImePackage() {
        imePackage = try {
            Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)?.substringBefore('/')
        } catch (e: Exception) {
            imePackage
        }
    }

    // ------------------------------------------------------------------ focus checks
    // App switches catch most cases; this timer also catches: the focus window starting while you
    // are already in a blocked app, "Allow 10 minutes" running out, and returning from a pop-up.

    private val focusCheck = Runnable {
        checkFocusNow()
        scheduleFocusCheck()
    }

    private fun scheduleFocusCheck() {
        mainHandler.removeCallbacks(focusCheck)
        if (on(Keys.FOCUS_ON)) mainHandler.postDelayed(focusCheck, FOCUS_CHECK_MS)
    }

    /**
     * Package of the app really in front: the active (or topmost) application window.
     * Overlays, toasts, keyboards, the status bar and our own bubble are not application windows.
     */
    private fun frontApp(): String? {
        try {
            var fallback: String? = null
            for (w in windows) {
                if (w.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
                val p = w.root?.packageName?.toString() ?: continue
                if (w.isActive || w.isFocused) return p
                if (fallback == null) fallback = p
            }
            if (fallback != null) return fallback
        } catch (e: Exception) {
            Log.w(TAG, "window list failed", e)
        }
        return try {
            // While our own overlay is up it can be the "active" window; that isn't an app switch.
            rootInActiveWindow?.packageName?.toString()?.takeUnless { it == packageName && screen.isShowing }
        } catch (e: Exception) {
            null
        }
    }

    /** After ignoring a window event in a reel app: if you did leave after all, catch up. */
    private val frontCheck = Runnable {
        if (!isReelApp(foreground)) return@Runnable
        val front = frontApp() ?: return@Runnable
        if (front != foreground) onWindowChanged(if (front == packageName) SELF_PKG else front)
    }

    private fun scheduleFrontCheck() {
        mainHandler.removeCallbacks(frontCheck)
        mainHandler.postDelayed(frontCheck, FRONT_CHECK_MS)
    }

    private fun checkFocusNow() {
        if (screen.isShowing) return
        val pkg = frontApp() ?: return
        if (pkg == packageName || pkg == imePackage || pkg in DetectionRules.IGNORED_PACKAGES) return
        if (pkg != foreground) {
            onWindowChanged(pkg) // does the leave bookkeeping and shows the gate if needed
            return
        }
        if (focusBlocks(pkg, trustedNow())) {
            foreground = pkg
            bubble.hide()
            showFocusGate(pkg)
        }
    }

    private fun isReelApp(pkg: String?) = pkg != null && pkg in DetectionRules.APPS

    private fun total() = counts.values.sum()

    private fun limit() = (settings[Keys.LIMIT_REELS]?.toIntOrNull() ?: 100).coerceAtLeast(1)

    private fun limitReached() = on(Keys.LIMIT_ON) && total() >= limit()

    private fun resetHour() = settings[Keys.DAY_RESET_HOUR]?.toIntOrNull() ?: 4

    /**
     * The day changes only when it has really ended on the uptime clock, so changing the time,
     * date, time zone or "day starts at" hour can never start a new day early.
     */
    private fun ensureToday(now: Long) {
        if (day.isNotEmpty() && SystemClock.elapsedRealtime() < dayEndElapsed) return
        // The day is over: a changed "day starts at" hour takes effect now.
        val applied = try {
            store.applyPendingResetHour(force = true)
        } catch (e: Exception) {
            false
        }
        if (applied) {
            try {
                val fresh = store.settings()
                fresh[Keys.FOCUS_OVERRIDE_UNTIL] = settings[Keys.FOCUS_OVERRIDE_UNTIL] ?: "0"
                settings = fresh
            } catch (e: Exception) {
                Log.w(TAG, "settings reload failed", e)
            }
            MainActivity.notifyFlutter("settingsChanged")
        }
        val byClock = LogicalDay.keyFor(now, resetHour())
        val rollover = day.isNotEmpty()
        val next = if (rollover) maxOf(byClock, LogicalDay.minusDays(day, -1)) else byClock
        loadDay(next)
        // A day that starts by rolling over lasts at least 20 hours, so a time-zone change
        // can't make the next day short (20 h still allows moving "day starts at" earlier).
        if (rollover) dayEndElapsed = maxOf(dayEndElapsed, SystemClock.elapsedRealtime() + MIN_DAY_MS)
        TodayWidget.updateAll(this)
    }

    /** When the current [day] ends, measured on the uptime clock. */
    private fun computeDayEnd() {
        val c = Calendar.getInstance()
        c.timeInMillis = LogicalDay.startOf(day, resetHour())
        c.add(Calendar.DAY_OF_MONTH, 1)
        dayEndElapsed = SystemClock.elapsedRealtime() + (c.timeInMillis - trustedNow())
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
        showPause(packageName, ms, ms, remember = false)
    }

    companion object {
        /** Stand-in package name for "the Ew Brother app itself is in front". */
        private const val SELF_PKG = "__ew_self__"
        private const val TAG = "EwBrother"
        private const val LIMIT_PAUSE_MS = 30_000L
        private const val FOCUS_CHECK_MS = 15_000L
        private const val FRONT_CHECK_MS = 800L
        private const val MIN_DAY_MS = 20 * 3_600_000L

        @Volatile
        var instance: EwAccessibilityService? = null
            private set

        /** Settings changed somewhere (app, tile, notification): reload on the main thread. */
        fun reloadFromAnyThread(full: Boolean = false) {
            Handler(Looper.getMainLooper()).post { instance?.reload(full) }
        }
    }
}
