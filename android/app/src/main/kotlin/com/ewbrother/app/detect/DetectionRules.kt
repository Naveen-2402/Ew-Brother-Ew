package com.ewbrother.app.detect

/**
 * ============================================================================
 *  ALL REEL / SHORT DETECTION RULES LIVE IN THIS ONE FILE.
 * ============================================================================
 * Instagram and YouTube change their internal view IDs from time to time.
 * When counting stops working after an app update:
 *
 *  1. Open Ew Brother Ew > Settings > Detection check, then scroll a few reels.
 *  2. The screen lists the view IDs the service saw while you scrolled.
 *  3. Either add the new ID in that screen (no rebuild needed), or add it to
 *     [CONTAINER_IDS] below and rebuild.
 *
 * IDs below are best-known values; they are NOT guaranteed. The full-screen
 * pager heuristic is a fallback when no ID matches.
 */
object DetectionRules {
    const val INSTAGRAM = "com.instagram.android"
    const val YOUTUBE = "com.google.android.youtube"

    /** Packages we count in. Values are the short app keys stored in the database. */
    val APPS: Map<String, String> = mapOf(
        INSTAGRAM to "instagram",
        YOUTUBE to "youtube",
    )

    /** Scrollable containers that hold the reel/short feed (fully-qualified view IDs). */
    val CONTAINER_IDS: Map<String, Set<String>> = mapOf(
        INSTAGRAM to setOf(
            "com.instagram.android:id/clips_viewer_view_pager",
            "com.instagram.android:id/clips_viewer_pager",
            "com.instagram.android:id/clips_video_container",
        ),
        YOUTUBE to setOf(
            "com.google.android.youtube:id/reel_recycler",
            "com.google.android.youtube:id/reel_player_page_container",
            "com.google.android.youtube:id/reel_watch_player",
        ),
    )

    /**
     * Pagers that are CHECKED ON A TIMER instead of waiting for scroll events.
     * YouTube sends a scroll event when Shorts opens but usually none for the swipes after it,
     * so for YouTube the service looks at which Short fills this pager every [PAGER_POLL_MS]
     * and counts when it changes. (Instagram sends scroll events, so it isn't polled.)
     */
    val POLL_PAGER_IDS: Map<String, List<String>> = mapOf(
        YOUTUBE to listOf("com.google.android.youtube:id/reel_recycler"),
    )

    /** How often the YouTube Shorts pager is checked while YouTube is in front and the screen is on. */
    const val PAGER_POLL_MS = 700L

    /** While the pager was seen this recently, scroll events from that app don't count (no double count). */
    const val POLL_ACTIVE_MS = 2_500L

    /** A page counts as "on screen" when it fills this much of the pager's height. */
    const val PAGE_VISIBLE_RATIO = 0.6f

    /**
     * Never count these, even if the heuristic matches. In Instagram, "reel_viewer"
     * is the STORIES viewer (Instagram calls stories "reels" internally; Reels are "clips").
     */
    val EXCLUDED_ID_PARTS: List<String> = listOf(
        "reel_viewer",
        "story",
        "stories",
        "direct_",
        "comment",
    )

    /** Fallback heuristic: a vertical pager whose page fills most of the screen. */
    const val HEURISTIC_ENABLED = true
    const val FULLSCREEN_RATIO = 0.75f

    /** Ignore further scroll events within one swipe (ms) when the feed gives no item index. */
    const val SWIPE_DEBOUNCE_MS = 900L

    /** Index jumps larger than this are treated as a feed refresh, not real reels. */
    const val MAX_JUMP = 5

    /** Watch time cap per reel, so a reel left playing doesn't add an hour. */
    const val MAX_SECONDS_PER_REEL = 90

    /** No reel activity for this long starts a new viewing session. */
    const val SESSION_GAP_MS = 3 * 60_000L

    /** Smart interrupt is not shown again if you come back within this window. */
    const val INTERRUPT_COOLDOWN_MS = 2 * 60_000L

    /** Packages whose window changes are ignored (shade, keyboard, ourselves). */
    val IGNORED_PACKAGES: Set<String> = setOf(
        "com.android.systemui",
        "com.ewbrother.app",
        "android",
    )
}
