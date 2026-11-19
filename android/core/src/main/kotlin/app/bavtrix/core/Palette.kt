package app.bavtrix.core

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/** Final colour of a lit cell: depth shade, trail fade and head brightness applied. */
object Palette {
    /** Returned for empty cells. */
    const val NONE = 0

    private fun scale(c: Int, k: Int): Int = min((c * k + 127) / 255, 255)

    /** Packed 0xAARRGGBB colour of the cell at [idx] (row [row]), or [NONE] for empty cells. */
    fun color(sim: RainSim, idx: Int, row: Int): Int {
        val f = sim.flags[idx]
        if (f and CellFlag.ON == 0) return NONE
        val cfg = sim.config
        val bright = f and (CellFlag.HEAD or CellFlag.FLASH) != 0
        val special = f and CellFlag.SPECIAL_STREAM != 0
        val base = when {
            special && bright -> cfg.specialFg
            special -> cfg.specialFade
            bright -> cfg.fg
            else -> cfg.fade
        }

        // The trail fades out towards its end; the head keeps full brightness. 32 steps keep the
        // number of distinct colours small.
        val id = sim.sid[idx]
        val slot = if (id < sim.slots.size) sim.slots[id] else Slot()
        val age = max(slot.head - row, 0).toFloat()
        val len = max(slot.len, 1).toFloat()
        val fade = if (bright) 1f else {
            val v = 0.12f + 0.88f * min(max(1 - age / len, 0f), 1f).pow(1.3f)
            (v * 32).roundToInt() / 32f
        }
        val boost = if (bright) cfg.headBrightness else 1f
        val shade = min(sim.shade[idx] * fade * boost, 255f).toInt()
        var r = scale(base.r, shade)
        var g = scale(base.g, shade)
        var b = scale(base.b, shade)
        if (boost > 1f) {
            // Brighter than the configured colour: push it towards white.
            val t = min((boost - 1f) * 0.5f, 0.6f)
            r = (r + (255 - r) * t).toInt()
            g = (g + (255 - g) * t).toInt()
            b = (b + (255 - b) * t).toInt()
        }
        return Rgba(r, g, b, base.a).argb
    }
}

/**
 * Brightness of a lit cell for the picture effect (0.06..1): far streams (low depth shade) and the
 * fading end of a trail show the picture dimmer, so the picture gets depth like the rain itself.
 */
fun Palette.depthLevel(sim: RainSim, idx: Int, row: Int): Float {
    val f = sim.flags[idx]
    val bright = f and (CellFlag.HEAD or CellFlag.FLASH) != 0
    val id = sim.sid[idx]
    val slot = if (id < sim.slots.size) sim.slots[id] else Slot()
    val age = max(slot.head - row, 0).toFloat()
    val len = max(slot.len, 1).toFloat()
    val fade = if (bright) 1f else 0.12f + 0.88f * min(max(1 - age / len, 0f), 1f).pow(1.3f)
    val level = min(sim.shade[idx] * fade / 255f, 1f)
    val v = 0.06f + 0.94f * level.pow(2.2f)
    return (v * 32).roundToInt() / 32f
}
