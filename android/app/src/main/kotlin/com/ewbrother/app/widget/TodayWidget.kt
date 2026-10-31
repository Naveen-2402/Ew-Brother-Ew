package com.ewbrother.app.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.ewbrother.app.R
import com.ewbrother.app.data.Keys
import com.ewbrother.app.data.LogicalDay
import com.ewbrother.app.data.Store
import com.ewbrother.app.notify.ActionReceiver
import com.ewbrother.app.notify.Notifier
import com.ewbrother.app.overlay.OverlayStyle

/** F7: reels today, tasks left, habits done; tap a task or habit to tick it. */
class TodayWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val ctx = context.applicationContext
        val pending = goAsync()
        Store.runIo {
            try {
                updateAll(ctx)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        private val TASK_VIEWS = intArrayOf(R.id.w_task1, R.id.w_task2, R.id.w_task3)
        private val HABIT_VIEWS = intArrayOf(R.id.w_habit1, R.id.w_habit2, R.id.w_habit3, R.id.w_habit4)

        @Volatile
        private var lastPush = 0L

        /** Cheap enough to call after every change; reel-count pushes are throttled to 1 per 3 s. */
        fun updateAll(ctx: Context, throttled: Boolean = false) {
            val now = System.currentTimeMillis()
            if (throttled && now - lastPush < 3000) return
            lastPush = now
            val manager = AppWidgetManager.getInstance(ctx)
            val ids = manager.getAppWidgetIds(ComponentName(ctx, TodayWidget::class.java))
            if (ids.isEmpty()) return
            val views = build(ctx)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun build(ctx: Context): RemoteViews {
            val store = Store(ctx)
            val settings = store.settings()
            val resetHour = settings[Keys.DAY_RESET_HOUR]?.toIntOrNull() ?: 4
            val today = LogicalDay.keyFor(System.currentTimeMillis(), resetHour)
            store.rolloverTasks(LogicalDay.startOf(today, resetHour))

            val reels = store.dailyCounts(today).values.sumOf { it[0] }
            val limit = settings[Keys.LIMIT_REELS]?.toIntOrNull() ?: 100
            val tasks = store.openTasks(3)
            val left = store.tasksLeft()
            val habits = store.habitsToday(today)
            val done = habits.count { it.done }

            val v = RemoteViews(ctx.packageName, R.layout.widget_today)
            v.setTextViewText(R.id.w_reels, reels.toString())
            v.setTextColor(R.id.w_reels, OverlayStyle.progressColor(reels, limit))
            v.setTextViewText(R.id.w_tasks_left, if (left == 1) "1 task left" else "$left tasks left")
            v.setTextViewText(R.id.w_habits_done, "$done of ${habits.size} habits")
            v.setOnClickPendingIntent(R.id.w_header, Notifier.openApp(ctx))

            TASK_VIEWS.forEachIndexed { i, viewId ->
                val t = tasks.getOrNull(i)
                if (t == null) {
                    v.setViewVisibility(viewId, View.GONE)
                } else {
                    v.setViewVisibility(viewId, View.VISIBLE)
                    v.setTextViewText(viewId, "○  ${t.title}")
                    v.setOnClickPendingIntent(
                        viewId,
                        Notifier.broadcast(ctx, ActionReceiver.ACTION_TICK_TASK, 3000 + i, t.id, ActionReceiver.SRC_WIDGET),
                    )
                }
            }

            HABIT_VIEWS.forEachIndexed { i, viewId ->
                val h = habits.getOrNull(i)
                if (h == null) {
                    v.setViewVisibility(viewId, View.GONE)
                } else {
                    v.setViewVisibility(viewId, View.VISIBLE)
                    v.setTextViewText(viewId, if (h.done) "✓ ${h.name}" else h.name)
                    v.setTextColor(viewId, if (h.done) OverlayStyle.BRINJAL else OverlayStyle.CHALK)
                    v.setInt(
                        viewId,
                        "setBackgroundResource",
                        if (h.done) R.drawable.widget_chip_done_bg else R.drawable.widget_chip_bg,
                    )
                    v.setOnClickPendingIntent(
                        viewId,
                        Notifier.broadcast(ctx, ActionReceiver.ACTION_TICK_HABIT, 3100 + i, h.id, ActionReceiver.SRC_WIDGET),
                    )
                }
            }

            v.setViewVisibility(R.id.w_empty, if (tasks.isEmpty() && habits.isEmpty()) View.VISIBLE else View.GONE)
            return v
        }
    }
}
