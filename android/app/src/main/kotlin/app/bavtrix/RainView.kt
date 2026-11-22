package app.bavtrix

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Canvas
import android.util.AttributeSet
import android.view.Choreographer
import android.view.View

/** A view that animates the rain; used by the main screen and the screensaver. */
class RainView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {
    private val renderer = RainRenderer(context)
    private var lastNanos = 0L
    private var running = false

    private val prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
        renderer.config = SettingsStore.load(context)
    }

    private val frame = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!running) return
            Choreographer.getInstance().postFrameCallback(this)
            // 60 frames per second at most, even on 90/120 Hz displays.
            if (lastNanos != 0L && frameTimeNanos - lastNanos < 15_000_000L) return
            if (lastNanos != 0L) {
                val dt = ((frameTimeNanos - lastNanos) / 1_000_000f).coerceIn(1f, 250f)
                renderer.advance(dt)
            }
            lastNanos = frameTimeNanos
            invalidate()
        }
    }

    init {
        renderer.config = SettingsStore.load(context)
        keepScreenOn = true
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        SettingsStore.prefs(context).registerOnSharedPreferenceChangeListener(prefsListener)
        renderer.config = SettingsStore.load(context)
        running = true
        lastNanos = 0L
        Choreographer.getInstance().postFrameCallback(frame)
    }

    override fun onDetachedFromWindow() {
        running = false
        SettingsStore.prefs(context).unregisterOnSharedPreferenceChangeListener(prefsListener)
        super.onDetachedFromWindow()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        renderer.setSize(w, h)
    }

    override fun onDraw(canvas: Canvas) {
        renderer.draw(canvas)
    }
}
