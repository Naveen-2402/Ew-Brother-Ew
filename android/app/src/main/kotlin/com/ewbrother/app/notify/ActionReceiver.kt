package com.ewbrother.app.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.ewbrother.app.MainActivity
import com.ewbrother.app.data.Keys
import com.ewbrother.app.data.Store
import com.ewbrother.app.service.EwAccessibilityService
import com.ewbrother.app.widget.TodayWidget

/** Notification buttons, widget taps and alarms. */
class ActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val ctx = context.applicationContext
        val id = intent.getLongExtra(EXTRA_ID, 0)
        val source = intent.getStringExtra(EXTRA_SOURCE) ?: ""
        val pending = goAsync()
        Store.runIo {
            try {
                handle(ctx, intent.action, id, source, intent.getStringExtra(EXTRA_KIND))
            } finally {
                pending.finish()
            }
        }
    }

    private fun handle(ctx: Context, action: String?, id: Long, source: String, kind: String?) {
        val store = Store(ctx)
        when (action) {
            ACTION_TICK_TASK -> {
                store.setTaskDone(id, System.currentTimeMillis())
                if (source == SRC_MORNING) Notifier.postMorning(ctx)
                afterDataChange(ctx)
            }
            ACTION_TICK_HABIT -> {
                val today = store.today()
                if (source == SRC_WIDGET) {
                    val current = store.habitsToday(today).firstOrNull { it.id == id }?.done ?: false
                    store.setHabitDone(id, today, !current)
                } else {
                    store.setHabitDone(id, today, true)
                }
                when (source) {
                    SRC_EVENING -> Notifier.postEvening(ctx)
                    SRC_HABIT -> Notifier.cancel(ctx, Notifier.ID_HABIT_BASE + id.toInt())
                }
                afterDataChange(ctx)
            }
            ACTION_TOGGLE_MONITOR -> {
                val on = store.get(Keys.MONITOR_ON) == "1"
                store.set(Keys.MONITOR_ON, if (on) "0" else "1")
                EwAccessibilityService.reloadFromAnyThread()
                Notifier.refreshStatus(ctx)
                MainActivity.notifyFlutter("settingsChanged")
            }
            ACTION_ALARM -> {
                when (kind) {
                    AlarmScheduler.KIND_MORNING -> Notifier.postMorning(ctx)
                    AlarmScheduler.KIND_EVENING -> Notifier.postEvening(ctx)
                    AlarmScheduler.KIND_WEEKLY -> Notifier.postWeekly(ctx)
                    AlarmScheduler.KIND_HABIT -> Notifier.postHabit(ctx, id)
                }
                AlarmScheduler.scheduleAll(ctx)
            }
        }
    }

    private fun afterDataChange(ctx: Context) {
        TodayWidget.updateAll(ctx)
        MainActivity.notifyFlutter("dataChanged")
    }

    companion object {
        const val ACTION_TICK_TASK = "com.ewbrother.app.TICK_TASK"
        const val ACTION_TICK_HABIT = "com.ewbrother.app.TICK_HABIT"
        const val ACTION_TOGGLE_MONITOR = "com.ewbrother.app.TOGGLE_MONITOR"
        const val ACTION_ALARM = "com.ewbrother.app.ALARM"
        const val EXTRA_ID = "id"
        const val EXTRA_SOURCE = "source"
        const val EXTRA_KIND = "kind"
        const val SRC_MORNING = "morning"
        const val SRC_EVENING = "evening"
        const val SRC_HABIT = "habit"
        const val SRC_WIDGET = "widget"
    }
}
