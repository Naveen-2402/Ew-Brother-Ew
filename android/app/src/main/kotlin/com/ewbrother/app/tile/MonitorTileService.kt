package com.ewbrother.app.tile

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.ewbrother.app.MainActivity
import com.ewbrother.app.data.Keys
import com.ewbrother.app.data.Store
import com.ewbrother.app.notify.Notifier
import com.ewbrother.app.service.EwAccessibilityService

/** Quick Settings tile: turn reel monitoring on/off without opening the app. */
class MonitorTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        render()
    }

    override fun onClick() {
        super.onClick()
        // From the lock screen, unlock first: someone holding the phone can't switch it off.
        if (isLocked) unlockAndRun { toggle() } else toggle()
    }

    private fun toggle() {
        val store = Store(this)
        val on = store.get(Keys.MONITOR_ON) == "1"
        store.set(Keys.MONITOR_ON, if (on) "0" else "1")
        EwAccessibilityService.reloadFromAnyThread()
        Notifier.refreshStatus(this)
        MainActivity.notifyFlutter("settingsChanged")
        render()
    }

    private fun render() {
        val tile = qsTile ?: return
        val on = Store(this).get(Keys.MONITOR_ON) == "1"
        tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Reel monitor"
        tile.updateTile()
    }
}
