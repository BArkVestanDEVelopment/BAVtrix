package app.bavtrix

import android.content.SharedPreferences
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder

/** Live wallpaper: the rain on the home and lock screens. */
class RainWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = RainEngine()

    private inner class RainEngine : Engine() {
        private val renderer = RainRenderer(this@RainWallpaperService)
        private val handler = Handler(Looper.getMainLooper())
        private var visible = false
        private var lastMs = 0L

        private val prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
            renderer.config = SettingsStore.load(this@RainWallpaperService)
        }

        private val tick = object : Runnable {
            override fun run() {
                if (!visible) return
                val now = SystemClock.uptimeMillis()
                if (lastMs != 0L) renderer.advance((now - lastMs).coerceIn(1L, 250L).toFloat())
                lastMs = now
                drawFrame()
                handler.postDelayed(this, 33)
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            renderer.config = SettingsStore.load(this@RainWallpaperService)
            SettingsStore.prefs(this@RainWallpaperService).registerOnSharedPreferenceChangeListener(prefsListener)
        }

        override fun onDestroy() {
            visible = false
            handler.removeCallbacks(tick)
            SettingsStore.prefs(this@RainWallpaperService).unregisterOnSharedPreferenceChangeListener(prefsListener)
            super.onDestroy()
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            renderer.setSize(width, height)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            this.visible = visible
            handler.removeCallbacks(tick)
            if (visible) {
                lastMs = 0L
                handler.post(tick)
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
