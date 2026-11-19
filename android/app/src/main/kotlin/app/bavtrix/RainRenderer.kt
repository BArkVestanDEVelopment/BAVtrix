package app.bavtrix

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import app.bavtrix.core.CellFlag
import app.bavtrix.core.Palette
import app.bavtrix.core.RainConfig
import app.bavtrix.core.RainSim
import kotlin.math.ceil
import kotlin.math.max

/** Draws the rain; shared by the in-app view, the live wallpaper and the screensaver. */
class RainRenderer(context: Context) {
    private val density = context.resources.displayMetrics.density
    private val matrixTypeface: Typeface = try {
        Typeface.createFromAsset(context.assets, "MatrixCodeFont.ttf")
    } catch (e: Exception) {
        Typeface.MONOSPACE
    }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    private var sim: RainSim? = null
    private var width = 0
    private var height = 0
    private var cellW = 8f
    private var cellH = 14f
    private var ascent = 11f
    private var chars = CharArray(0)
    private var specialChars = CharArray(0)

    var config: RainConfig = RainConfig()
        set(value) {
            if (value == field) return
            val relayout = field.glyphSize != value.glyphSize ||
                field.charset != value.charset ||
                field.specialStrings != value.specialStrings
            field = value
            if (relayout) {
                rebuildMetrics()
                rebuildSim()
            } else {
                sim?.config = value
            }
        }

    init {
        rebuildMetrics()
    }

    private fun rebuildMetrics() {
        chars = config.charsetChars
        specialChars = config.specialChars
        paint.typeface = matrixTypeface
        paint.textSize = config.glyphSize * density
        var widest = 1f
        for (c in chars) widest = max(widest, paint.measureText(c.toString()))
        val m = paint.fontMetrics
        cellW = max(ceil(widest), 4f)
        ascent = -m.ascent
        cellH = max(ceil(m.descent - m.ascent), 6f)
    }

    private fun rebuildSim() {
        if (width <= 0 || height <= 0) return
        sim = RainSim(
            cols = (width / cellW).toInt(),
            rows = (height / cellH).toInt(),
            initial = config,
            seed = System.nanoTime(),
        )
    }

    fun setSize(w: Int, h: Int) {
        if (w == width && h == height) return
        width = w
        height = h
        rebuildSim()
    }

    fun advance(dtMs: Float) {
        sim?.advance(dtMs)
    }

    fun draw(canvas: Canvas) {
        val bg = config.bg
        canvas.drawColor((0xFF shl 24) or (bg.r shl 16) or (bg.g shl 8) or bg.b)
        val s = sim ?: return
        val x0 = (width - s.cols * cellW) / 2f
        val y0 = (height - s.rows * cellH) / 2f
        for (row in 0 until s.rows) {
            for (col in 0 until s.cols) {
                val idx = row * s.cols + col
                val color = Palette.color(s, idx, row)
                if (color == Palette.NONE) continue
                val special = s.flags[idx] and CellFlag.SPECIAL_GLYPH != 0
                val table = if (special) specialChars else chars
                val g = s.glyph[idx]
                if (g >= table.size) continue
                paint.typeface = if (special) Typeface.MONOSPACE else matrixTypeface
                paint.color = color
                canvas.drawText(table, g, 1, x0 + col * cellW, y0 + row * cellH + ascent, paint)
            }
        }
    }
}
