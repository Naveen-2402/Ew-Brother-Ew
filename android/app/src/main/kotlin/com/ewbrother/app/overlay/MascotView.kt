package com.ewbrother.app.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View

/**
 * The "ew" mascot drawn in code: one eye squeezed shut, one brow up, wavy grimace,
 * tongue out. Same geometry as the launcher icon and lib/ui/core/widgets/mascot.dart
 * (designed on a 52x52 grid centred on the face).
 */
class MascotView(context: Context, private val faceColor: Int = OverlayStyle.PISTA) : View(context) {
    private val face = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = faceColor }
    private val tongue = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = OverlayStyle.TONGUE }
    private val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayStyle.BRINJAL
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val inkFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = OverlayStyle.BRINJAL }
    private val path = Path()

    override fun onDraw(canvas: Canvas) {
        val s = minOf(width, height) / 52f
        canvas.save()
        canvas.translate((width - 52f * s) / 2f, (height - 52f * s) / 2f)
        canvas.scale(s, s)
        ink.strokeWidth = 3f

        canvas.drawCircle(26f, 26f, 26f, face)

        // Tongue (under the mouth line)
        path.reset()
        path.moveTo(28f, 38f)
        path.quadTo(28.5f, 47f, 33f, 47f)
        path.quadTo(37.5f, 47f, 37f, 38f)
        path.close()
        canvas.drawPath(path, tongue)

        path.reset()
        // Left brow, pulled down
        path.moveTo(9f, 15f); path.lineTo(19f, 18.5f)
        // Left eye squeezed shut ">"
        path.moveTo(11f, 21f); path.lineTo(18f, 23.5f); path.lineTo(11f, 26f)
        // Right brow, raised
        path.moveTo(31f, 13f); path.quadTo(36.5f, 8.5f, 43f, 12f)
        // Wavy grimace
        path.moveTo(14f, 38f)
        path.quadTo(18f, 34f, 22f, 38f)
        path.quadTo(26f, 42f, 30f, 38f)
        path.quadTo(34f, 34f, 38f, 38f)
        canvas.drawPath(path, ink)

        // Right eye
        canvas.drawCircle(36.5f, 23f, 3.5f, inkFill)
        canvas.restore()
    }
}
