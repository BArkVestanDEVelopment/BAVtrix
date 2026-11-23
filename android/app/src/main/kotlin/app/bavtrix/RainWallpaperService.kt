package app.bavtrix

import android.content.SharedPreferences
import android.graphics.Canvas
import android.view.Choreographer
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder

/** Live wallpaper: the rain on the home and lock screens. */
class RainWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = RainEngine()

    private inner class RainEngine : Engine() {
        private val renderer = RainRenderer(this@RainWallpaperService)
        private var visible = false
        private var lastNanos = 0L

        private val prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
            renderer.config = SettingsStore.load(this@RainWallpaperService)
        }

        private val tick = object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                if (!visible) return
                Choreographer.getInstance().postFrameCallback(this)
                // The wallpaper runs all day: 30 frames per second keep the battery use low (the rain steps every 100+ ms anyway).
                if (lastNanos != 0L && frameTimeNanos - lastNanos < 30_000_000L) return
                if (lastNanos != 0L) {
                    renderer.advance(((frameTimeNanos - lastNanos) / 1_000_000f).coerceIn(1f, 250f))
                }
                lastNanos = frameTimeNanos
                drawFrame()
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            renderer.config = SettingsStore.load(this@RainWallpaperService)
            SettingsStore.prefs(this@RainWallpaperService).registerOnSharedPreferenceChangeListener(prefsListener)
        }

        override fun onDestroy() {
            visible = false
            Choreographer.getInstance().removeFrameCallback(tick)
            SettingsStore.prefs(this@RainWallpaperService).unregisterOnSharedPreferenceChangeListener(prefsListener)
            super.onDestroy()
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            renderer.setSize(width, height)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            this.visible = visible
            Choreographer.getInstance().removeFrameCallback(tick)
            if (visible) {
                lastNanos = 0L
                Choreographer.getInstance().postFrameCallback(tick)
            }
        }

        private fun drawFrame() {
            val holder = surfaceHolder
            var canvas: Canvas? = null
            try {
                canvas = holder.lockHardwareCanvas()
                if (canvas != null) renderer.draw(canvas)
            } catch (e: Exception) {
                // Fall through: some devices cannot lock a hardware canvas on this surface.
            } finally {
                if (canvas != null) holder.unlockCanvasAndPost(canvas)
            }
        }
    }
}
