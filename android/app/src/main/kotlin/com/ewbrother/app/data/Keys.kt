package com.ewbrother.app.data

/**
 * Keys of the `settings` table and their defaults.
 * MUST stay in sync with lib/data/settings_keys.dart.
 */
object Keys {
    const val MONITOR_ON = "monitor_on"
    const val BUBBLE_ON = "bubble_on"
    const val BUBBLE_SIZE = "bubble_size" // small | medium | large
    const val BUBBLE_X = "bubble_x"
    const val BUBBLE_Y = "bubble_y"
    const val INTERVAL_INSTAGRAM = "interval_instagram"
    const val INTERVAL_YOUTUBE = "interval_youtube"
    const val PAUSE_SECONDS = "pause_seconds"
    const val LIMIT_ON = "limit_on"
    const val LIMIT_REELS = "limit_reels"
    const val LIMIT_ACTION = "limit_action" // block | pause30
    const val DAY_RESET_HOUR = "day_reset_hour"
    const val DAY_RESET_NEXT = "day_reset_next" // pending new hour, "" = none
    const val DAY_RESET_NEXT_AFTER = "day_reset_next_after" // day key that must end first
    const val MESSAGES = "pause_messages" // JSON array of strings
    const val INTERRUPT_ON = "interrupt_on"
    const val FOCUS_ON = "focus_on"
    const val FOCUS_START = "focus_start" // HH:mm
    const val FOCUS_END = "focus_end" // HH:mm
    const val FOCUS_APPS = "focus_apps" // JSON array of package names
    const val FOCUS_OVERRIDE_UNTIL = "focus_override_until" // epoch millis
    const val FOCUS_LAST_LOGGED = "focus_last_logged" // epoch millis of last logged window start
    const val STATUS_NOTIF_ON = "status_notif_on"
    const val MORNING_ON = "morning_on"
    const val MORNING_TIME = "morning_time"
    const val EVENING_ON = "evening_on"
    const val EVENING_TIME = "evening_time"
    const val WEEKLY_ON = "weekly_on"
    const val THEME = "theme" // dark | light | system
    const val EXTRA_REEL_IDS = "extra_reel_ids" // JSON array of view ids added by the user
    const val ALARM_HABIT_IDS = "alarm_habit_ids" // JSON array, internal
    const val LAST_PRUNE_DAY = "last_prune_day" // internal

    const val DEFAULT_MESSAGES =
        "[\"Ew, brother, ew. What's that? Take 5.\"," +
            "\"Thambi, podhum da. 5 seconds.\"," +
            "\"Ugh. Enough. Breathe.\"," +
            "\"Nopey. Not yet. 5 seconds.\"," +
            "\"Last one promise? Sure you did. Wait 5.\"]"

    val DEFAULTS: Map<String, String> = linkedMapOf(
        MONITOR_ON to "1",
        BUBBLE_ON to "1",
        BUBBLE_SIZE to "medium",
        BUBBLE_X to "-1",
        BUBBLE_Y to "-1",
        INTERVAL_INSTAGRAM to "10",
        INTERVAL_YOUTUBE to "10",
        PAUSE_SECONDS to "5",
        LIMIT_ON to "1",
        LIMIT_REELS to "100",
        LIMIT_ACTION to "block",
        DAY_RESET_HOUR to "4",
        DAY_RESET_NEXT to "",
        DAY_RESET_NEXT_AFTER to "",
        MESSAGES to DEFAULT_MESSAGES,
        INTERRUPT_ON to "0",
        FOCUS_ON to "0",
        FOCUS_START to "09:00",
        FOCUS_END to "17:00",
        FOCUS_APPS to "[]",
        FOCUS_OVERRIDE_UNTIL to "0",
        FOCUS_LAST_LOGGED to "0",
        STATUS_NOTIF_ON to "1",
        MORNING_ON to "1",
        MORNING_TIME to "08:00",
        EVENING_ON to "1",
        EVENING_TIME to "21:00",
        WEEKLY_ON to "1",
        THEME to "dark",
        EXTRA_REEL_IDS to "[]",
        ALARM_HABIT_IDS to "[]",
        LAST_PRUNE_DAY to "",
    )
}
