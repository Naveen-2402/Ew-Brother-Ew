package com.ewbrother.app.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.OvershootInterpolator
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * Floating counter over Instagram and YouTube.
 * A dark disc with a ring that fills toward the daily limit (green, orange, red), the count in
 * the middle and a small caption. It pops when a reel is counted.
 * Drag to move (position is remembered), tap to open the detail card, long-press to hide
 * until you leave the app.
 */
class Bubble(
    private val ctx: Context,
    private val onMoved: (x: Int, y: Int) -> Unit,
    private val onLongPress: () -> Unit,
) {
    /** What the bubble shows. [left] is null when the daily limit is off. */
    data class State(
        val total: Int,
        val instagram: Int,
        val youtube: Int,
        val color: Int,
        val progress: Float,
        val nextPauseIn: Int,
        val left: Int?,
    )

    private val wm = ctx.getSystemService(WindowManager::class.java)!!
    private val handler = Handler(Looper.getMainLooper())
    private var root: LinearLayout? = null
    private var disc: DiscView? = null
    private var detail: TextView? = null
    private var params: WindowManager.LayoutParams? = null
    private var expanded = false
    private var lastTotal = -1

    val isShowing: Boolean get() = root != null

    fun show(sizeKey: String, savedX: Int, savedY: Int) {
        if (root != null) return
        val sizeDp = when (sizeKey) {
            "small" -> 44f
            "large" -> 68f
            else -> 56f
        }
        val size = OverlayStyle.dpi(ctx, sizeDp)
        val metrics = ctx.resources.displayMetrics

        val circle = DiscView(ctx, showCaption = sizeKey != "small").apply {
            elevation = OverlayStyle.dp(ctx, 6f)
        }
        val info = TextView(ctx).apply {
            setTextColor(OverlayStyle.CHALK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = OverlayStyle.font(ctx, 560)
            setLineSpacing(OverlayStyle.dp(ctx, 3f), 1f)
            visibility = View.GONE
            val padH = OverlayStyle.dpi(ctx, 14f)
            val padV = OverlayStyle.dpi(ctx, 10f)
            setPadding(padH, padV, padH, padV)
            background = OverlayStyle.pill(
                withAlpha(OverlayStyle.BRINJAL, 0xF0),
                OverlayStyle.dp(ctx, 18f),
                withAlpha(OverlayStyle.CHALK, 0x22),
                OverlayStyle.dpi(ctx, 1f),
            )
            elevation = OverlayStyle.dp(ctx, 6f)
        }
        val layout = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            // Room for the shadow and the pop animation.
            val pad = OverlayStyle.dpi(ctx, 6f)
            setPadding(pad, pad, pad, pad)
            clipChildren = false
            clipToPadding = false
            addView(circle, LinearLayout.LayoutParams(size, size))
            addView(info, LinearLayout.LayoutParams(-2, -2).apply { marginStart = OverlayStyle.dpi(ctx, 8f) })
        }

        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        // Clamp a saved position to the current screen (rotation or a resolution change can
        // otherwise leave the bubble off-screen where it can't be dragged back).
        val maxX = (metrics.widthPixels - size).coerceAtLeast(0)
        val maxY = (metrics.heightPixels - size).coerceAtLeast(0)
        p.x = (if (savedX >= 0) savedX else metrics.widthPixels - size - OverlayStyle.dpi(ctx, 12f)).coerceIn(0, maxX)
        p.y = (if (savedY >= 0) savedY else (metrics.heightPixels * 0.28f).toInt()).coerceIn(0, maxY)

        attachTouch(layout, p)
        try {
            wm.addView(layout, p)
        } catch (e: Exception) {
            return
        }
        root = layout
        disc = circle
        detail = info
        params = p
        expanded = false
        lastTotal = -1
    }

    fun update(s: State) {
        val d = disc ?: return
        d.count = s.total.toString()
        d.caption = if (s.left != null) "of ${s.total + s.left}" else "reels"
        d.ringColor = s.color
        d.progress = s.progress
        d.invalidate()
        // A small pop when a new reel is counted (not on first show).
        if (lastTotal >= 0 && s.total > lastTotal) {
            d.animate().cancel()
            d.scaleX = 1f
            d.scaleY = 1f
            d.animate().scaleX(1.16f).scaleY(1.16f).setDuration(110).withEndAction {
                d.animate().scaleX(1f).scaleY(1f).setDuration(260).setInterpolator(OvershootInterpolator(2.5f)).start()
            }.start()
        }
        lastTotal = s.total
        detail?.text = detailText(s)
    }

    private fun detailText(s: State): CharSequence {
        val b = SpannableStringBuilder()
        fun dot(color: Int) {
            val start = b.length
            b.append("● ")
            b.setSpan(ForegroundColorSpan(color), start, b.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        fun muted(text: String) {
            val start = b.length
            b.append(text)
            b.setSpan(ForegroundColorSpan(OverlayStyle.TEXT_MUTED_APP), start, b.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        dot(OverlayStyle.TONGUE)
        b.append("${s.instagram}")
        muted(" Reels")
        b.append("    ")
        dot(OverlayStyle.SKY)
        b.append("${s.youtube}")
        muted(" Shorts")
        b.append("\n")
        muted(if (s.nextPauseIn == 1) "Pause after the next one" else "Pause in ${s.nextPauseIn}")
        if (s.left != null) {
            muted("  ·  ")
            if (s.left <= 0) {
                val start = b.length
                b.append("Limit reached")
                b.setSpan(ForegroundColorSpan(OverlayStyle.CHILLI), start, b.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            } else {
                muted("${s.left} left today")
            }
        }
        return b
    }

    fun hide() {
        root?.let {
            try {
                wm.removeView(it)
            } catch (ignored: Exception) {
            }
        }
        root = null
        disc = null
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
                        val m = ctx.resources.displayMetrics
                        p.x = (startX + dx).toInt().coerceIn(0, (m.widthPixels - v.width).coerceAtLeast(0))
                        p.y = (startY + dy).toInt().coerceIn(0, (m.heightPixels - v.height).coerceAtLeast(0))
                        try {
                            wm.updateViewLayout(v, p)
                        } catch (ignored: Exception) {
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
                        v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        v.performClick()
                    }
                }
            }
            true
        }
    }

    private fun withAlpha(color: Int, alpha: Int) =
        Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))

    /** The round counter: dark disc, faint track, coloured progress arc, number and caption. */
    private class DiscView(context: Context, private val showCaption: Boolean) : View(context) {
        var count = "0"
        var caption = "reels"
        var ringColor = OverlayStyle.PISTA
        var progress = 0f
            set(value) {
                field = value.coerceIn(0f, 1f)
            }

        private val stroke = OverlayStyle.dp(context, 3.5f)
        private val discPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = OverlayStyle.BRINJAL }
        private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            color = Color.argb(0x33, 0xF2, 0xEC, 0xE3)
        }
        private val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }
        private val numberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = OverlayStyle.CHALK
            textAlign = Paint.Align.CENTER
            typeface = OverlayStyle.font(context, 780, 80)
        }
        private val captionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = OverlayStyle.TEXT_MUTED_APP
            textAlign = Paint.Align.CENTER
            typeface = OverlayStyle.font(context, 600)
        }
        private val box = RectF()

        override fun onDraw(canvas: Canvas) {
            val size = minOf(width, height).toFloat()
            val cx = width / 2f
            val cy = height / 2f
            canvas.drawCircle(cx, cy, size / 2f, discPaint)

            val inset = stroke / 2f + OverlayStyle.dp(context, 3f)
            box.set(cx - size / 2f + inset, cy - size / 2f + inset, cx + size / 2f - inset, cy + size / 2f - inset)
            canvas.drawArc(box, 0f, 360f, false, track)
            arc.color = ringColor
            if (progress > 0f) canvas.drawArc(box, -90f, 360f * progress, false, arc)

            // Shrink long numbers so "1000" still fits inside the ring.
            numberPaint.textSize = size * (if (count.length >= 4) 0.27f else 0.34f)
            numberPaint.color = if (progress >= 1f) ringColor else OverlayStyle.CHALK
            if (showCaption) {
                captionPaint.textSize = size * 0.15f
                val numY = cy + size * 0.05f
                canvas.drawText(count, cx, numY, numberPaint)
                canvas.drawText(caption, cx, numY + captionPaint.textSize * 1.25f, captionPaint)
            } else {
                val y = cy - (numberPaint.descent() + numberPaint.ascent()) / 2f
                canvas.drawText(count, cx, y, numberPaint)
            }
        }
    }
}
