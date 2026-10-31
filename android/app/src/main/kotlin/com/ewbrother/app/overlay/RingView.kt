package com.ewbrother.app.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.View

/** Countdown ring that drains smoothly; the number in the middle is drawn separately. */
class RingView(context: Context) : View(context) {
    /** 1.0 = full ring, 0.0 = empty. */
    var progress: Float = 1f
        set(value) {
            field = value.coerceIn(0f, 1f)
            invalidate()
        }

    var label: String = ""
        set(value) {
            if (field != value) {
                field = value
                invalidate()
            }
        }

    private val stroke = OverlayStyle.dp(context, 10f)
    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        color = OverlayStyle.RING_TRACK
    }
    private val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        strokeCap = Paint.Cap.ROUND
        color = OverlayStyle.RING
    }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayStyle.TEXT
        textAlign = Paint.Align.CENTER
        typeface = OverlayStyle.font(context, 760, 80)
    }
    private val box = RectF()

    override fun onDraw(canvas: Canvas) {
        val size = minOf(width, height).toFloat()
        val pad = stroke / 2f + 2f
        val left = (width - size) / 2f
        val top = (height - size) / 2f
        box.set(left + pad, top + pad, left + size - pad, top + size - pad)
        canvas.drawArc(box, 0f, 360f, false, track)
        if (progress > 0f) canvas.drawArc(box, -90f, 360f * progress, false, arc)
        text.textSize = size * 0.42f
        val y = height / 2f - (text.descent() + text.ascent()) / 2f
        canvas.drawText(label, width / 2f, y, text)
    }
}
