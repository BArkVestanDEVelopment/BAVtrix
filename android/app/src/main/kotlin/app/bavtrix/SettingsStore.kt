package app.bavtrix

import android.content.Context
import android.content.SharedPreferences
import app.bavtrix.core.RainConfig
import app.bavtrix.core.Rgba

/** Settings shared by the app, the live wallpaper and the screensaver (one SharedPreferences file). */
object SettingsStore {
    // Versioned: bumping it makes everybody start from the new defaults.
    private const val FILE = "bavtrix_v2"

    fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private fun SharedPreferences.rgba(key: String, def: Rgba): Rgba {
        val v = getInt(key, def.argb)
        return Rgba((v shr 16) and 0xFF, (v shr 8) and 0xFF, v and 0xFF, (v ushr 24) and 0xFF)
    }

    fun load(context: Context): RainConfig {
        val p = prefs(context)
        val d = RainConfig()
        return d.copy(
            speedVariance = p.getFloat("speedVariance", d.speedVariance),
            refreshMs = p.getFloat("refreshMs", d.refreshMs),
            specialProbability = p.getFloat("specialProbability", d.specialProbability),
            spawnRate = p.getFloat("spawnRate", d.spawnRate),
            flicker = p.getFloat("flicker", d.flicker),
            headFlicker = p.getFloat("headFlicker", d.headFlicker),
            headBrightness = p.getFloat("headBrightness", d.headBrightness),
            trailMin = p.getInt("trailMin", d.trailMin),
            trailMax = p.getInt("trailMax", d.trailMax),
            glyphSize = p.getFloat("glyphSize", d.glyphSize),
            usePicture = p.getBoolean("usePicture", d.usePicture),
            pictureVersion = p.getInt("pictureVersion", d.pictureVersion),
            pictureCover = p.getBoolean("pictureCover", d.pictureCover),
            pictureBlend = p.getInt("pictureBlend", d.pictureBlend),
            fg = p.rgba("fg", d.fg),
            fade = p.rgba("fade", d.fade),
            bg = p.rgba("bg", d.bg),
        )
    }

    fun save(context: Context, c: RainConfig) {
        prefs(context).edit()
            .putFloat("speedVariance", c.speedVariance)
            .putFloat("refreshMs", c.refreshMs)
            .putFloat("specialProbability", c.specialProbability)
            .putFloat("spawnRate", c.spawnRate)
            .putFloat("flicker", c.flicker)
            .putFloat("headFlicker", c.headFlicker)
            .putFloat("headBrightness", c.headBrightness)
            .putInt("trailMin", c.trailMin)
            .putInt("trailMax", c.trailMax)
            .putFloat("glyphSize", c.glyphSize)
            .putBoolean("usePicture", c.usePicture)
            .putInt("pictureVersion", c.pictureVersion)
            .putBoolean("pictureCover", c.pictureCover)
            .putInt("pictureBlend", c.pictureBlend)
            .putInt("fg", c.fg.argb)
            .putInt("fade", c.fade.argb)
            .putInt("bg", c.bg.argb)
            .apply()
    }

    fun reset(context: Context) {
        prefs(context).edit().clear().apply()
    }
}
