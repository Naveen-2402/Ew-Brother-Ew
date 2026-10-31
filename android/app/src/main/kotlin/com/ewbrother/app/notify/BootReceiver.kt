package com.ewbrother.app.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.ewbrother.app.data.Store
import com.ewbrother.app.widget.TodayWidget

/** Alarms are cleared on reboot and on app update; put them back. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return
        val ctx = context.applicationContext
        val pending = goAsync()
        Store.runIo {
            try {
                AlarmScheduler.scheduleAll(ctx)
                TodayWidget.updateAll(ctx)
            } finally {
                pending.finish()
            }
        }
    }
}
