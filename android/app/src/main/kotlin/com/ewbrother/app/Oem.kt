package com.ewbrother.app

import android.content.ComponentName
import android.content.Intent
import android.os.Build

/**
 * Phone-maker differences. Stock Android (Pixel, Motorola, Nokia, ...) needs nothing extra;
 * several Android skins add their own background-kill and autostart switches with their own
 * settings pages. Every page here is tried in order and falls back to App info, so an unknown
 * phone or a renamed page never breaks anything.
 */
object Oem {
    const val XIAOMI = "xiaomi"
    const val SAMSUNG = "samsung"
    const val OPPO = "oppo" // also Realme and OnePlus (ColorOS based)
    const val VIVO = "vivo" // also iQOO
    const val HUAWEI = "huawei" // also Honor
    const val OTHER = "other"

    val family: String by lazy {
        val m = "${Build.MANUFACTURER} ${Build.BRAND}".lowercase()
        when {
            listOf("xiaomi", "redmi", "poco").any { it in m } -> XIAOMI
            "samsung" in m -> SAMSUNG
            listOf("oppo", "realme", "oneplus").any { it in m } -> OPPO
            listOf("vivo", "iqoo").any { it in m } -> VIVO
            listOf("huawei", "honor").any { it in m } -> HUAWEI
            else -> OTHER
        }
    }

    private fun page(pkg: String, cls: String) = Intent().setComponent(ComponentName(pkg, cls))

    /** The maker's "autostart" / "auto launch" page, best match first. Empty on stock Android. */
    fun autostartPages(): List<Intent> = when (family) {
        XIAOMI -> listOf(page("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"))
        OPPO -> listOf(
            page("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            page("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
            page("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
        )
        VIVO -> listOf(
            page("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            page("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
        )
        HUAWEI -> listOf(
            page("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            page("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
        )
        else -> emptyList()
    }

    /** The maker's own per-app battery page, if it has one apps can open. */
    fun batteryPages(packageName: String, label: String): List<Intent> = when (family) {
        XIAOMI -> listOf(
            page("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")
                .putExtra("package_name", packageName)
                .putExtra("package_label", label),
        )
        else -> emptyList()
    }
}
