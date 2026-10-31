package com.ewbrother.app.overlay

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * Floating counter over Instagram and YouTube.
 * Drag to move (position is remembered), tap to expand the per-app split,
 * long-press to hide until you leave the app.
 */
class Bubble(
    private val ctx: Context,
    private val onMoved: (x: Int, y: Int) -> Unit,
    private val onLongPress: () -> Unit,
) {
    private val wm = ctx.getSystemService(WindowManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var root: LinearLayout? = null
    private var count: TextView? = null
    private var detail: TextView? = null
    private var params: WindowManager.LayoutParams? = null
    private var expanded = false

    val isShowing: Boolean get() = root != null

    fun show(sizeKey: String, savedX: Int, savedY: Int) {
        if (root != null) return
        val sizeDp = when (sizeKey) {
            "small" -> 40f
            "large" -> 64f
            else -> 52f
        }
        val size = OverlayStyle.dpi(ctx, sizeDp)
        val metrics = ctx.resources.displayMetrics

        val circle = TextView(ctx).apply {
            gravity = Gravity.CENTER
            setTextColor(OverlayStyle.BRINJAL)
            setTextSize(TypedValue.COMPLEX_UNIT_PX, size * 0.38f)
            typeface = OverlayStyle.font(ctx, 780, 80)
            includeFontPadding = false
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(OverlayStyle.PISTA)
            }
            elevation = OverlayStyle.dp(ctx, 4f)
        }
        val info = TextView(ctx).apply {
            setTextColor(OverlayStyle.CHALK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = OverlayStyle.font(ctx, 560)
            visibility = View.GONE
            val pad = OverlayStyle.dpi(ctx, 12f)
            setPadding(pad, pad / 2, pad, pad / 2)
            background = OverlayStyle.pill(OverlayStyle.SURFACE, OverlayStyle.dp(ctx, 16f))
        }
        val layout = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(circle, LinearLayout.LayoutParams(size, size))
            addView(info, LinearLayout.LayoutParams(-2, -2).apply { marginStart = OverlayStyle.dpi(ctx, 6f) })
        }

        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        p.x = if (savedX >= 0) savedX else metrics.widthPixels - size - OverlayStyle.dpi(ctx, 12f)
        p.y = if (savedY >= 0) savedY else (metrics.heightPixels * 0.28f).toInt()

        attachTouch(layout, p)
        try {
            wm.addView(layout, p)
        } catch (e: Exception) {
            return
        }
        root = layout
        count = circle
        detail = info
        params = p
        expanded = false
    }

    fun update(total: Int, instagram: Int, youtube: Int, color: Int) {
        count?.text = total.toString()
        (count?.background as? GradientDrawable)?.setColor(color)
        detail?.text = "Reels $instagram   Shorts $youtube"
    }

    fun hide() {
        root?.let {
            try {
                wm.removeView(it)
            } catch (_: Exception) {
            }
        }
        root = null
        count = null
        detail = null
        params = null
    }

    private fun attachTouch(view: View, p: WindowManager.LayoutParams) {
        val slop = ViewConfiguration.get(ctx).scaledTouchSlop
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragging = false
        var longFired = false
        val longPress = Runnable {
            longFired = true
            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            onLongPress()
        }

        view.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX
                    downY = e.rawY
                    startX = p.x
                    startY = p.y
                    dragging = false
                    longFired = false
                    handler.postDelayed(longPress, ViewConfiguration.getLongPressTimeout().toLong())
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (!dragging && (abs(dx) > slop || abs(dy) > slop)) {
                        dragging = true
                        handler.removeCallbacks(longPress)
                    }
                    if (dragging && root != null) {
                        p.x = (startX + dx).toInt().coerceAtLeast(0)
                        p.y = (startY + dy).toInt().coerceAtLeast(0)
                        try {
                            wm.updateViewLayout(v, p)
                        } catch (_: Exception) {
                        }
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPress)
                    if (dragging) {
                        onMoved(p.x, p.y)
                    } else if (!longFired && e.actionMasked == MotionEvent.ACTION_UP) {
                        expanded = !expanded
                        detail?.visibility = if (expanded) View.VISIBLE else View.GONE
                        v.performClick()
                    }
                }
            }
            true
        }
    }
}
