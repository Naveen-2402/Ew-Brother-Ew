package com.ewbrother.app.overlay

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue

/** Colours and type for native overlays. Same tokens as lib/ui/core/tokens.dart. */
object OverlayStyle {
    // Pause overlay: calm "night tide" blue, no flashing.
    val TIDE = Color.parseColor("#17283A")
    val TIDE_RAISED = Color.parseColor("#20364C")
    val RING = Color.parseColor("#8FB8DE")
    val RING_TRACK = Color.parseColor("#2B4560")
    val TEXT = Color.parseColor("#EAF2FA")
    val TEXT_MUTED = Color.parseColor("#9DB3C8")

    // App palette (bubble, gates).
    val BRINJAL = Color.parseColor("#1C1524")
    val SURFACE = Color.parseColor("#271E31")
    val CHALK = Color.parseColor("#F2ECE3")
    val PISTA = Color.parseColor("#A6E38E")
    val HALDI = Color.parseColor("#FFB547")
    val CHILLI = Color.parseColor("#FF5E57")
    val TONGUE = Color.parseColor("#F58BB0")

    private const val FONT = "flutter_assets/assets/fonts/BricolageGrotesque.ttf"
    private val cache = HashMap<String, Typeface>()

    /** Bricolage Grotesque from the Flutter assets, so overlays match the app. */
    fun font(ctx: Context, weight: Int, width: Int = 100): Typeface {
        val key = "$weight/$width"
        cache[key]?.let { return it }
        val tf = try {
            Typeface.Builder(ctx.assets, FONT)
                .setFontVariationSettings("'wght' $weight, 'wdth' $width")
                .build()
        } catch (e: Exception) {
            null
        } ?: if (weight >= 600) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        cache[key] = tf
        return tf
    }

    fun dp(ctx: Context, v: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, ctx.resources.displayMetrics)

    fun dpi(ctx: Context, v: Float): Int = dp(ctx, v).toInt()

    fun pill(fill: Int, radius: Float, stroke: Int? = null, strokeWidth: Int = 0): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius
            setColor(fill)
            if (stroke != null) setStroke(strokeWidth, stroke)
        }

    /** Green below 60% of the limit, orange to 85%, red after. */
    fun progressColor(total: Int, limit: Int): Int {
        val ratio = total.toFloat() / limit.coerceAtLeast(1)
        return when {
            ratio < 0.6f -> PISTA
            ratio < 0.85f -> HALDI
            else -> CHILLI
        }
    }
}
