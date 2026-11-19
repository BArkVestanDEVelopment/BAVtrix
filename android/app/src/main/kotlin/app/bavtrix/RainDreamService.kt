package app.bavtrix

import android.service.dreams.DreamService

/** Screensaver (Daydream): the rain while the device charges or is docked. */
class RainDreamService : DreamService() {
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isInteractive = false
        isFullscreen = true
        setContentView(RainView(this))
    }
}
