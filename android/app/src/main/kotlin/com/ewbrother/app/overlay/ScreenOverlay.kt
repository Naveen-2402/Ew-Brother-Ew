package com.ewbrother.app.overlay

import android.content.Context
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.ceil

/**
 * One full-screen overlay at a time: the 5-second pause, the daily-limit block,
 * the smart interrupt ("What's your goal?") and the focus-mode block.
 *
 * Shown as TYPE_ACCESSIBILITY_OVERLAY from the accessibility service: no
 * "display over other apps" permission needed and it appears in well under 300 ms.
 * The countdown uses wall-clock time (not ValueAnimator), so turning off system
 * animations cannot skip it.
 */
class ScreenOverlay(private val ctx: Context) {

    data class Spec(
        val headline: String,
        val lines: List<String>,
        /** Full countdown length; 0 = no countdown. */
        val totalMs: Long,
        /** Remaining countdown (less than total when a pause is resumed). */
        val remainingMs: Long,
        /** Unlocks when the countdown reaches 0. null = no primary button. */
        val primary: String?,
        val secondary: String,
        /** true = calm pause colours, false = app colours. */
        val calm: Boolean,
        val choices: List<String> = emptyList(),
        val onPrimary: () -> Unit = {},
        val onSecondary: () -> Unit = {},
    )

    private val wm = ctx.getSystemService(WindowManager::class.java)!!
    private val audio = ctx.getSystemService(AudioManager::class.java)!!
    private val handler = Handler(Looper.getMainLooper())
    private var root: View? = null
    private var tick: Runnable? = null
    private var focusRequest: AudioFocusRequest? = null

    /** Uptime when the current countdown ends, or 0. */
    var deadline: Long = 0L
        private set

    val isShowing: Boolean get() = root != null

    fun show(spec: Spec) {
        dismiss()
        val calmBg = if (spec.calm) OverlayStyle.TIDE else OverlayStyle.BRINJAL
        val raised = if (spec.calm) OverlayStyle.TIDE_RAISED else OverlayStyle.SURFACE
        val textColor = if (spec.calm) OverlayStyle.TEXT else OverlayStyle.CHALK
        val muted = OverlayStyle.TEXT_MUTED
        val accent = if (spec.calm) OverlayStyle.RING else OverlayStyle.PISTA
        fun dp(v: Float) = OverlayStyle.dpi(ctx, v)

        val frame = object : FrameLayout(ctx) {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                // Back does nothing: use the buttons.
                if (event.keyCode == KeyEvent.KEYCODE_BACK) return true
                return super.dispatchKeyEvent(event)
            }
        }
        frame.setBackgroundColor(calmBg)
        frame.isClickable = true // swallow touches so the reel underneath can't be used
        frame.isFocusable = true
        frame.isFocusableInTouchMode = true

        val column = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28f), dp(40f), dp(28f), dp(32f))
        }
        frame.addView(column, FrameLayout.LayoutParams(MATCH, MATCH))
        frame.setOnApplyWindowInsetsListener { _, insets ->
            val (top, bottom) = barInsets(insets)
            column.setPadding(dp(28f), dp(24f) + top, dp(28f), dp(24f) + bottom)
            insets
        }

        column.addView(View(ctx), LinearLayout.LayoutParams(MATCH, 0, 1f))

        column.addView(MascotView(ctx), LinearLayout.LayoutParams(dp(84f), dp(84f)))

        column.addView(
            text(spec.headline, 26f, 700, textColor).apply { gravity = Gravity.CENTER },
            LinearLayout.LayoutParams(MATCH, WRAP).apply { topMargin = dp(20f) },
        )

        var ring: RingView? = null
        if (spec.totalMs > 0) {
            ring = RingView(ctx)
            column.addView(ring, LinearLayout.LayoutParams(dp(168f), dp(168f)).apply { topMargin = dp(28f) })
        }

        spec.lines.forEachIndexed { i, line ->
            column.addView(
                text(line, 16f, 420, muted).apply {
                    gravity = Gravity.CENTER
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                },
                LinearLayout.LayoutParams(MATCH, WRAP).apply { topMargin = dp(if (i == 0) 24f else 6f) },
            )
        }

        if (spec.choices.isNotEmpty()) {
            val chips = ArrayList<TextView>()
            spec.choices.forEach { label ->
                val chip = text(label, 16f, 560, textColor).apply {
                    gravity = Gravity.CENTER
                    minHeight = dp(48f)
                    background = OverlayStyle.pill(raised, dp(24f).toFloat())
                }
                chip.setOnClickListener {
                    chips.forEach { c -> c.background = OverlayStyle.pill(raised, dp(24f).toFloat()) }
                    chip.background = OverlayStyle.pill(raised, dp(24f).toFloat(), accent, dp(2f))
                    chip.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                }
                chips.add(chip)
                column.addView(chip, LinearLayout.LayoutParams(MATCH, WRAP).apply { topMargin = dp(10f) })
            }
        }

        column.addView(View(ctx), LinearLayout.LayoutParams(MATCH, 0, 1f))

        var primaryView: TextView? = null
        if (spec.primary != null) {
            val p = text(spec.primary, 17f, 680, OverlayStyle.BRINJAL).apply {
                gravity = Gravity.CENTER
                background = OverlayStyle.pill(accent, dp(28f).toFloat())
            }
            p.setOnClickListener {
                if (deadline == 0L || SystemClock.uptimeMillis() >= deadline) {
                    dismiss()
                    spec.onPrimary()
                }
            }
            primaryView = p
            column.addView(p, LinearLayout.LayoutParams(MATCH, dp(56f)))
        }

        val secondary = text(spec.secondary, 17f, 600, textColor).apply {
            gravity = Gravity.CENTER
            background = OverlayStyle.pill(0, dp(28f).toFloat(), raised, dp(2f))
        }
        secondary.setOnClickListener {
            dismiss()
            spec.onSecondary()
        }
        column.addView(
            secondary,
            LinearLayout.LayoutParams(MATCH, dp(56f)).apply { topMargin = dp(if (primaryView != null) 10f else 0f) },
        )

        val params = WindowManager.LayoutParams(
            MATCH,
            MATCH,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.OPAQUE,
        )
        params.gravity = Gravity.TOP or Gravity.START

        frame.alpha = 0f
        try {
            wm.addView(frame, params)
        } catch (e: Exception) {
            return
        }
        root = frame
        frame.requestFocus()
        frame.animate().alpha(1f).setDuration(200).start()
        holdAudio()

        if (spec.totalMs > 0 && ring != null) {
            val total = spec.totalMs
            deadline = SystemClock.uptimeMillis() + spec.remainingMs.coerceAtLeast(0)
            primaryView?.alpha = 0.35f
            val r = ring
            val pv = primaryView
            val loop = object : Runnable {
                override fun run() {
                    val left = (deadline - SystemClock.uptimeMillis()).coerceAtLeast(0)
                    r.progress = left.toFloat() / total
                    r.label = ceil(left / 1000.0).toInt().toString()
                    if (left > 0) {
                        handler.postDelayed(this, 32)
                    } else {
                        deadline = 0L
                        pv?.animate()?.alpha(1f)?.setDuration(200)?.start()
                        frame.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    }
                }
            }
            tick = loop
            handler.post(loop)
        } else {
            deadline = 0L
        }
    }

    /** Remaining countdown in ms (0 when none). */
    fun remainingMs(): Long =
        if (deadline == 0L) 0L else (deadline - SystemClock.uptimeMillis()).coerceAtLeast(0)

    fun dismiss() {
        tick?.let { handler.removeCallbacks(it) }
        tick = null
        deadline = 0L
        root?.let { v ->
            try {
                wm.removeView(v)
            } catch (ignored: Exception) {
            }
        }
        root = null
        releaseAudio()
    }

    /** Transient audio focus makes Instagram/YouTube pause playback behind the overlay. */
    private fun holdAudio() {
        if (focusRequest != null) return
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setOnAudioFocusChangeListener { }
            .build()
        try {
            audio.requestAudioFocus(req)
            focusRequest = req
        } catch (ignored: Exception) {
        }
    }

    private fun releaseAudio() {
        focusRequest?.let {
            try {
                audio.abandonAudioFocusRequest(it)
            } catch (ignored: Exception) {
            }
        }
        focusRequest = null
    }

    @Suppress("DEPRECATION")
    private fun barInsets(insets: WindowInsets): Pair<Int, Int> =
        if (Build.VERSION.SDK_INT >= 30) {
            val bars = insets.getInsets(WindowInsets.Type.systemBars())
            bars.top to bars.bottom
        } else {
            insets.systemWindowInsetTop to insets.systemWindowInsetBottom
        }

    private fun text(value: String, sp: Float, weight: Int, color: Int) = TextView(ctx).apply {
        text = value
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
        typeface = OverlayStyle.font(ctx, weight)
        includeFontPadding = false
        setLineSpacing(0f, 1.15f)
    }

    private companion object {
        const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
    }
}
