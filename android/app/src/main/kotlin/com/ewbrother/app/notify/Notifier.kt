package com.ewbrother.app.notify

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import com.ewbrother.app.MainActivity
import com.ewbrother.app.R
import com.ewbrother.app.data.Keys
import com.ewbrother.app.data.LogicalDay
import com.ewbrother.app.data.Store
import com.ewbrother.app.service.EwAccessibilityService
import kotlin.math.abs
import kotlin.math.roundToInt

/** F8 notifications, F12 weekly summary and the monitor status notification. Framework APIs only. */
object Notifier {
    private const val CH_STATUS = "status"
    private const val CH_REMIND = "reminders"

    const val ID_STATUS = 1
    const val ID_MORNING = 2
    const val ID_EVENING = 3
    const val ID_WEEKLY = 4
    const val ID_HABIT_BASE = 1000
    const val ID_TASK_BASE = 2_000_000
    private const val REQ_TASK_DONE_BASE = 3_000_000

    fun ensureChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)!!
        nm.createNotificationChannel(
            NotificationChannel(CH_STATUS, "Monitor status", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Today's reel count and the monitor on/off button"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_REMIND, "Tasks and habits", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Morning top 3, evening habits, habit reminders, weekly summary"
            }
        )
    }

    fun canPost(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun openApp(ctx: Context): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(ctx, 1, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun broadcast(ctx: Context, action: String, request: Int, id: Long = 0, source: String = ""): PendingIntent {
        val i = Intent(ctx, ActionReceiver::class.java)
            .setAction(action)
            .putExtra(ActionReceiver.EXTRA_ID, id)
            .putExtra(ActionReceiver.EXTRA_SOURCE, source)
        return PendingIntent.getBroadcast(ctx, request, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun action(ctx: Context, title: String, pi: PendingIntent): Notification.Action =
        Notification.Action.Builder(Icon.createWithResource(ctx, R.drawable.ic_notif), title, pi).build()

    /** Pause/resume from the notification asks to unlock first when the phone is locked (Android 12+). */
    private fun toggleAction(ctx: Context, on: Boolean): Notification.Action {
        val b = Notification.Action.Builder(
            Icon.createWithResource(ctx, R.drawable.ic_notif),
            if (on) "Pause monitoring" else "Resume monitoring",
            broadcast(ctx, ActionReceiver.ACTION_TOGGLE_MONITOR, 20),
        )
        if (Build.VERSION.SDK_INT >= 31) b.setAuthenticationRequired(true)
        return b.build()
    }

    private fun short(s: String, max: Int = 20) = if (s.length <= max) s else s.take(max - 1) + "…"

    private fun nm(ctx: Context) = ctx.getSystemService(NotificationManager::class.java)!!

    // ---------- status (monitor toggle) ----------

    /** [liveTotal] from the service's in-memory count (DB write may still be queued). */
    fun refreshStatus(ctx: Context, liveTotal: Int? = null) {
        val store = Store(ctx)
        val running = EwAccessibilityService.instance != null
        if (!running || store.get(Keys.STATUS_NOTIF_ON) != "1" || !canPost(ctx)) {
            nm(ctx).cancel(ID_STATUS)
            return
        }
        ensureChannels(ctx)
        val on = store.get(Keys.MONITOR_ON) == "1"
        val today = store.today()
        val total = liveTotal ?: store.dailyCounts(today).values.sumOf { it[0] }
        val n = Notification.Builder(ctx, CH_STATUS)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle(if (on) "$total reels today" else "Monitoring paused")
            .setContentText(if (on) "Counting Reels and Shorts" else "Nothing is counted until you resume")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(openApp(ctx))
            .addAction(toggleAction(ctx, on))
            .build()
        nm(ctx).notify(ID_STATUS, n)
    }

    // ---------- morning: top 3 ----------

    fun postMorning(ctx: Context) {
        if (!canPost(ctx)) return
        val store = Store(ctx)
        val today = store.today()
        store.rolloverTasks(LogicalDay.startOf(today, store.resetHour()))
        val tasks = store.openTasks(3)
        if (tasks.isEmpty()) {
            nm(ctx).cancel(ID_MORNING)
            return
        }
        ensureChannels(ctx)
        val style = Notification.InboxStyle()
        tasks.forEach { style.addLine(it.title) }
        val b = Notification.Builder(ctx, CH_REMIND)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle("Your top ${tasks.size} for today")
            .setContentText(tasks.joinToString(", ") { it.title })
            .setStyle(style)
            .setContentIntent(openApp(ctx))
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
        tasks.forEachIndexed { i, t ->
            b.addAction(
                action(
                    ctx,
                    "Done: ${short(t.title, 14)}",
                    broadcast(ctx, ActionReceiver.ACTION_TICK_TASK, 30 + i, t.id, ActionReceiver.SRC_MORNING),
                )
            )
        }
        nm(ctx).notify(ID_MORNING, b.build())
    }

    // ---------- evening: habits left ----------

    fun postEvening(ctx: Context) {
        if (!canPost(ctx)) return
        val store = Store(ctx)
        val left = store.habitsToday(store.today()).filter { !it.done }
        if (left.isEmpty()) {
            nm(ctx).cancel(ID_EVENING)
            return
        }
        ensureChannels(ctx)
        fun line(h: Store.HabitItem) = if (h.multi) "${h.name} ${h.count}/${h.target}" else h.name
        val style = Notification.InboxStyle()
        left.forEach { style.addLine(line(it)) }
        val b = Notification.Builder(ctx, CH_REMIND)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle(if (left.size == 1) "1 habit left today" else "${left.size} habits left today")
            .setContentText(left.joinToString(", ") { line(it) })
            .setStyle(style)
            .setContentIntent(openApp(ctx))
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
        left.take(3).forEachIndexed { i, h ->
            b.addAction(
                action(
                    ctx,
                    if (h.multi) "+1 ${short(h.name, 14)}" else "Done: ${short(h.name, 14)}",
                    broadcast(ctx, ActionReceiver.ACTION_TICK_HABIT, 40 + i, h.id, ActionReceiver.SRC_EVENING),
                )
            )
        }
        nm(ctx).notify(ID_EVENING, b.build())
    }

    // ---------- single habit reminder ----------

    /**
     * [fromAlarm]: a scheduled reminder. Interval reminders stay quiet when you're on track
     * (count already at what this point of the range asks for), so a missed slot that you
     * made up for never nags. Re-posts after "+1" use fromAlarm = false and always update.
     */
    fun postHabit(ctx: Context, habitId: Long, fromAlarm: Boolean = true) {
        if (!canPost(ctx)) return
        val store = Store(ctx)
        val h = store.habitsToday(store.today()).firstOrNull { it.id == habitId } ?: return
        if (h.done) {
            nm(ctx).cancel(ID_HABIT_BASE + habitId.toInt())
            return
        }
        if (fromAlarm && h.multi && onTrack(h)) return
        ensureChannels(ctx)
        val text = if (h.multi) {
            val left = h.target - h.count
            "${h.count} of ${h.target} today, $left to go. Tap +1 each time."
        } else {
            "Tick it when it's done."
        }
        val n = Notification.Builder(ctx, CH_REMIND)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle("Time for ${h.name}")
            .setContentText(text)
            .setContentIntent(openApp(ctx))
            .setAutoCancel(!h.multi)
            .setOnlyAlertOnce(!fromAlarm)
            .addAction(
                action(
                    ctx,
                    if (h.multi) "+1" else "Done",
                    broadcast(ctx, ActionReceiver.ACTION_TICK_HABIT, 5000 + habitId.toInt(), h.id, ActionReceiver.SRC_HABIT),
                )
            )
            .build()
        nm(ctx).notify(ID_HABIT_BASE + habitId.toInt(), n)
    }

    /** Count already covers the slots passed so far (e.g. 4 of 8 by the middle of the range). */
    private fun onTrack(h: Store.HabitItem): Boolean {
        val start = h.reminder ?: return false
        val slots = AlarmScheduler.slotMinutes(start, h.until, h.every) ?: return false
        val c = java.util.Calendar.getInstance()
        val nowMin = c.get(java.util.Calendar.HOUR_OF_DAY) * 60 + c.get(java.util.Calendar.MINUTE)
        val passed = slots.count { it <= nowMin + 1 }
        if (passed <= 0) return false
        val expected = kotlin.math.ceil(h.target.toDouble() * passed / slots.size).toInt()
        return h.count >= expected
    }

    // ---------- task reminder ----------

    fun postTask(ctx: Context, taskId: Long) {
        if (!canPost(ctx)) return
        val store = Store(ctx)
        store.rolloverTasks(LogicalDay.startOf(store.today(), store.resetHour()))
        val t = store.taskReminder(taskId) ?: return
        if (t.done) return
        ensureChannels(ctx)
        val n = Notification.Builder(ctx, CH_REMIND)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle(t.title)
            .setContentText(if (t.repeatDaily) "Daily task reminder" else "Task reminder")
            .setContentIntent(openApp(ctx))
            .setAutoCancel(true)
            .addAction(
                action(
                    ctx,
                    "Done",
                    broadcast(ctx, ActionReceiver.ACTION_TICK_TASK, REQ_TASK_DONE_BASE + taskId.toInt(), t.id, ActionReceiver.SRC_TASK),
                )
            )
            .build()
        nm(ctx).notify(ID_TASK_BASE + taskId.toInt(), n)
    }

    fun cancel(ctx: Context, id: Int) = nm(ctx).cancel(id)

    // ---------- F12 weekly summary ----------

    fun postWeekly(ctx: Context) {
        if (!canPost(ctx)) return
        val store = Store(ctx)
        val today = store.today()
        val thisWeek = store.reelsBetween(LogicalDay.minusDays(today, 6), today)
        val lastWeek = store.reelsBetween(LogicalDay.minusDays(today, 13), LogicalDay.minusDays(today, 7))
        val habits = store.habitDoneCountBetween(LogicalDay.minusDays(today, 6), today)
        val title = when {
            lastWeek == 0 -> "$thisWeek reels this week"
            thisWeek <= lastWeek -> {
                val pct = ((lastWeek - thisWeek) * 100.0 / lastWeek).roundToInt()
                "$pct% fewer reels than last week"
            }
            else -> {
                val pct = (abs(thisWeek - lastWeek) * 100.0 / lastWeek).roundToInt()
                "$pct% more reels than last week. Ew."
            }
        }
        ensureChannels(ctx)
        val n = Notification.Builder(ctx, CH_REMIND)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle(title)
            .setContentText("$thisWeek this week, $lastWeek last week. $habits habit ticks.")
            .setContentIntent(openApp(ctx))
            .setAutoCancel(true)
            .build()
        nm(ctx).notify(ID_WEEKLY, n)
    }
}
