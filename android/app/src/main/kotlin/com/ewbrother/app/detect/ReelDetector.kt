package com.ewbrother.app.detect

import android.graphics.Rect
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Turns scroll events into "N new reels". Rules come from [DetectionRules].
 *
 * Counting model:
 *  - Only scrolls inside a reel/short feed container count.
 *  - When the feed reports item indexes, a reel counts when the feed SETTLES on an index
 *    higher than any seen in this session. Scrolling back up never counts; quick swipes that
 *    skip events are counted by the index jump (capped at MAX_JUMP).
 *  - Without indexes, one count per swipe (debounced).
 *  - Entering a feed never counts by itself (the spec counts scroll-to-next events).
 */
class ReelDetector(private val screenSize: () -> Pair<Int, Int>) {

    data class Result(val inFeed: Boolean, val newReels: Int)

    private class Session(
        val containerKey: Int,
        var maxIndex: Int,
        var lastCountAt: Long,
        var lastEventAt: Long,
    )

    private val sessions = HashMap<String, Session>()
    private val heuristicCache = HashMap<Int, Boolean>()
    private val heuristicMissUntil = HashMap<Int, Long>()

    /** View IDs added by the user in Settings > Detection check (no rebuild needed). */
    @Volatile
    var extraIds: Set<String> = emptySet()

    /** Recent distinct scroll containers seen in Instagram/YouTube, newest first. */
    val log: ArrayDeque<String> = ArrayDeque()

    private val none = Result(false, 0)

    fun reset(pkg: String) {
        sessions.remove(pkg)
    }

    fun onScroll(pkg: String, event: AccessibilityEvent, now: Long): Result {
        val source: AccessibilityNodeInfo = event.source ?: return none
        val id: String? = source.viewIdResourceName

        if (id != null && DetectionRules.EXCLUDED_ID_PARTS.any { id.contains(it) }) {
            remember(pkg, id, event.className, false)
            return none
        }

        val key = source.hashCode() * 31 + event.windowId
        val idMatch = id != null &&
            (DetectionRules.CONTAINER_IDS[pkg]?.contains(id) == true || extraIds.contains(id))
        val matched = idMatch || (DetectionRules.HEURISTIC_ENABLED && looksLikeReelPager(key, source))
        remember(pkg, id, event.className, matched)
        if (!matched) return none

        val from = event.fromIndex
        val to = event.toIndex
        var s = sessions[pkg]
        // A long reel (3+ min) sends no events while it plays. If the next event is exactly the
        // next index in the same feed, it's the same session: count it instead of re-baselining.
        val stale = s != null && now - s.lastEventAt > DetectionRules.SESSION_GAP_MS
        val nextInSameFeed = s != null && from >= 0 && from == to && from == s.maxIndex + 1
        if (s == null || s.containerKey != key || (stale && !nextInSameFeed)) {
            // New viewing session: set the baseline, don't count.
            s = Session(key, if (from >= 0) from else -1, now, now)
            sessions[pkg] = s
            return Result(true, 0)
        }
        s.lastEventAt = now

        if (from >= 0 && to >= 0) {
            if (from != to) return Result(true, 0) // mid-swipe, two pages visible
            if (s.maxIndex > DetectionRules.MAX_JUMP && from <= 1) {
                // Back at the very top after being far down: the feed reloaded (tab tapped again,
                // refresh). Count from here, or the next reels would never count. Scrolling back
                // by hand doesn't land on index 0/1 this way, so it isn't re-counted.
                s.maxIndex = from
                return Result(true, 0)
            }
            if (from <= s.maxIndex) return Result(true, 0) // went back a little, or same reel
            val jump = if (s.maxIndex < 0) 1 else from - s.maxIndex
            s.maxIndex = from
            // A jump this large is the feed restoring a position, not swiping: new baseline, no count.
            if (jump > DetectionRules.MAX_JUMP) return Result(true, 0)
            s.lastCountAt = now
            return Result(true, jump)
        }

        // Feed gives no indexes: one count per swipe.
        if (now - s.lastCountAt < DetectionRules.SWIPE_DEBOUNCE_MS) return Result(true, 0)
        s.lastCountAt = now
        return Result(true, 1)
    }

    /**
     * Full-screen vertical pager: the container and one of its visible pages fill the screen.
     * Pagers keep the previous page as child 0 (scrolled off-screen), so the first few children
     * are checked. Only a "yes" is cached for good; a "no" is re-checked after a moment, because
     * it may have been taken mid-swipe or while the feed was still loading.
     */
    private fun looksLikeReelPager(key: Int, node: AccessibilityNodeInfo): Boolean {
        heuristicCache[key]?.let { return true }
        val now = System.currentTimeMillis()
        if ((heuristicMissUntil[key] ?: 0L) > now) return false
        val cls = node.className?.toString() ?: ""
        var result = false
        if (cls.contains("ViewPager") || cls.contains("RecyclerView")) {
            val (w, h) = screenSize()
            val r = Rect()
            node.getBoundsInScreen(r)
            if (r.height() >= h * DetectionRules.FULLSCREEN_RATIO) {
                val cr = Rect()
                for (i in 0 until minOf(node.childCount, 3)) {
                    val child = node.getChild(i) ?: continue
                    child.getBoundsInScreen(cr)
                    if (cr.height() >= h * DetectionRules.FULLSCREEN_RATIO && cr.width() >= w * 0.9f) {
                        result = true
                        break
                    }
                }
            }
        }
        if (heuristicCache.size > 64) heuristicCache.clear()
        if (heuristicMissUntil.size > 64) heuristicMissUntil.clear()
        if (result) {
            heuristicCache[key] = true
            heuristicMissUntil.remove(key)
        } else {
            heuristicMissUntil[key] = now + 2_000L
        }
        return result
    }

    private fun remember(pkg: String, id: String?, cls: CharSequence?, matched: Boolean) {
        val app = DetectionRules.APPS[pkg] ?: pkg
        val label = id ?: "(no id) ${cls ?: ""}"
        val line = "$app|$label|${if (matched) 1 else 0}"
        log.remove(line)
        log.addFirst(line)
        while (log.size > 25) log.removeLast()
    }
}
