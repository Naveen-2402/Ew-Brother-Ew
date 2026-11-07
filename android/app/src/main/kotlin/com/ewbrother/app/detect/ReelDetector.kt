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
        polls.remove(pkg)
    }

    // ---------------------------------------------------------------- polled pager (YouTube Shorts)

    private class PollState(
        val pagerKey: Int,
        var maxIndex: Int,
        var lastItem: Int,
        var lastSeenAt: Long,
    )

    /**
     * One state per pager, per app. YouTube can have SEVERAL views with the Shorts pager ID attached
     * at once (e.g. after starting on Home and then opening Shorts): the one you swipe and one or
     * more covered ones. Android still reports covered views as "visible", so each pager is followed
     * on its own: a covered pager never changes, so only the one being swiped can count.
     */
    private val polls = HashMap<String, HashMap<Int, PollState>>()

    /**
     * Forget the polled Short (not the scroll session) after a full-screen overlay closes, so the
     * next look takes a fresh baseline instead of comparing against what it saw before the overlay.
     * The Short under the overlay is unchanged, so no swipe is lost.
     */
    fun resetPoll(pkg: String) {
        polls.remove(pkg)
    }

    /**
     * Look at every candidate pager of [pkg] once. Returns the new Shorts seen; at most one pager
     * (the one being swiped) can change between two looks, so the counts don't add up twice.
     */
    fun onPagerPolls(pkg: String, pagers: List<Pair<AccessibilityNodeInfo, String>>, now: Long): Result {
        if (pagers.isEmpty()) return none
        // Drop pagers not seen for a while (a closed Shorts screen).
        polls[pkg]?.values?.removeAll { now - it.lastSeenAt > DetectionRules.SESSION_GAP_MS }
        var best = 0
        var anyInFeed = false
        val notes = ArrayList<String>()
        for ((pager, id) in pagers) {
            val r = onPagerPoll(pkg, pager, id, now)
            notes.add(lastPollNote)
            if (r.inFeed) anyInFeed = true
            if (r.newReels > best) best = r.newReels
        }
        lastPollNote = if (notes.size == 1) notes[0] else "${notes.size} pagers: " + notes.joinToString(" | ")
        return Result(anyInFeed, best)
    }

    /** What the last pager check saw, for the live log in Settings > Detection check. */
    var lastPollNote: String = ""
        private set

    /**
     * One look at the Shorts pager. Counts when a different Short fills it than last time.
     * With list positions (rowIndex) it uses the same rules as scroll events: only moving past the
     * furthest Short counts, scrolling back doesn't, a reload at the top re-baselines, a big jump
     * counts 0. Without positions, any change of the Short on screen counts one.
     * The first look after entering is the baseline and never counts.
     */
    private fun onPagerPoll(pkg: String, pager: AccessibilityNodeInfo, id: String, now: Long): Result {
        remember(pkg, id, pager.className, true) // shows as counted in Settings > Detection check
        // Read live values, not the service's node cache: after an overlay (pause, interrupt) the
        // cache can hold the pager's old pages and the Short on screen would never seem to change.
        pager.refresh()
        val pr = Rect()
        pager.getBoundsInScreen(pr)
        if (pr.height() <= 0) {
            lastPollNote = "pager has no size"
            return none
        }

        // The page that fills most of the pager; none while mid-swipe (two half pages).
        var current: AccessibilityNodeInfo? = null
        val cr = Rect()
        for (i in 0 until minOf(pager.childCount, 6)) {
            val child = pager.getChild(i) ?: continue
            if (!child.refresh()) continue // page already gone (recycled mid-swipe)
            child.getBoundsInScreen(cr)
            if (!cr.intersect(pr)) continue
            if (cr.height() >= pr.height() * DetectionRules.PAGE_VISIBLE_RATIO) {
                current = child
                break
            }
        }
        val page = current ?: run {
            lastPollNote = "pager found, no full page (mid-swipe?)"
            return Result(true, 0)
        }
        val index = page.collectionItemInfo?.rowIndex?.takeIf { it >= 0 }
        val item = page.hashCode()
        lastPollNote = "pager found, ${pager.childCount} children, page " +
            (if (index != null) "row $index" else "#${Integer.toHexString(item)}")
        val key = pager.hashCode() * 31 + pager.windowId

        val states = polls.getOrPut(pkg) { HashMap() }
        val p = states[key]
        if (p == null || now - p.lastSeenAt > DetectionRules.SESSION_GAP_MS) {
            states[key] = PollState(key, index ?: -1, item, now) // baseline
            return Result(true, 0)
        }
        p.lastSeenAt = now
        if (index != null && p.maxIndex >= 0) {
            p.lastItem = item
            if (p.maxIndex > DetectionRules.MAX_JUMP && index <= 1) {
                p.maxIndex = index // feed reloaded at the top
                return Result(true, 0)
            }
            if (index <= p.maxIndex) return Result(true, 0) // same Short, or went back
            val jump = index - p.maxIndex
            p.maxIndex = index
            return Result(true, if (jump > DetectionRules.MAX_JUMP) 0 else jump)
        }
        if (item == p.lastItem) return Result(true, 0)
        p.lastItem = item
        if (index != null) p.maxIndex = index
        return Result(true, 1)
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
