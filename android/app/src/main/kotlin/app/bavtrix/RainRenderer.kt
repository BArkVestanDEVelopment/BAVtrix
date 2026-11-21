package app.bavtrix

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LightingColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.Typeface
import app.bavtrix.core.GlyphData
import app.bavtrix.core.CellFlag
import app.bavtrix.core.Palette
import app.bavtrix.core.depthLevel
import app.bavtrix.core.RainConfig
import app.bavtrix.core.RainSim
import kotlin.math.ceil
import kotlin.math.max

/** Draws the rain; shared by the in-app view, the live wallpaper and the screensaver. */
class RainRenderer(context: Context) {
    private val appContext = context.applicationContext
    private val density = context.resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    private var sim: RainSim? = null
    private var width = 0
    private var height = 0
    private var cellW = 8f
    private var cellH = 14f
    private var ascent = 11f
    private var glyphs: GlyphBitmaps? = null
    private var specialChars = CharArray(0)

    // The picture that shows through the glyphs (the desktop version's wallpaper effect).
    private var picture: Bitmap? = null
    private var pictureShader: BitmapShader? = null
    private val filters = HashMap<Int, ColorFilter>()

    var config: RainConfig = RainConfig()
        set(value) {
            if (value == field) return
            val relayout = field.glyphSize != value.glyphSize ||
                field.specialStrings != value.specialStrings
            val pictureChanged = field.usePicture != value.usePicture ||
                field.pictureVersion != value.pictureVersion ||
                field.pictureCover != value.pictureCover
            field = value
            if (relayout) {
                rebuildMetrics()
                rebuildSim()
            } else {
                sim?.config = value
            }
            if (pictureChanged) reloadPicture()
        }

    init {
        rebuildMetrics()
    }

    private fun rebuildMetrics() {
        specialChars = config.specialChars
        val bitmaps = GlyphBitmaps(config.glyphSize * density)
        glyphs = bitmaps
        cellW = bitmaps.cellW.toFloat()
        cellH = bitmaps.cellH.toFloat()
        // The few special glyphs (the greeting text) use the system monospaced font.
        paint.typeface = Typeface.MONOSPACE
        paint.textSize = config.glyphSize * density
        ascent = -paint.fontMetrics.ascent
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

    private fun reloadPicture() {
        picture?.recycle()
        picture = if (config.usePicture) PictureStore.load(appContext) else null
        buildShader()
    }

    /** Scales the picture to fit the surface (or to cover it, per setting) and wraps it in a shader. */
    private fun buildShader() {
        val raw = picture
        if (raw == null || width <= 0 || height <= 0) {
            pictureShader = null
            return
        }
        val fitW = width / raw.width.toFloat()
        val fitH = height / raw.height.toFloat()
        val scale = if (config.pictureCover) max(fitW, fitH) else minOf(fitW, fitH)
        val matrix = Matrix().apply {
            postScale(scale, scale)
            postTranslate((width - raw.width * scale) / 2f, (height - raw.height * scale) / 2f)
        }
        pictureShader = BitmapShader(raw, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).also {
            it.setLocalMatrix(matrix)
        }
    }

    fun setSize(w: Int, h: Int) {
        if (w == width && h == height) return
        width = w
        height = h
        rebuildSim()
        if (config.usePicture && picture == null) picture = PictureStore.load(appContext)
        buildShader()
    }

    fun advance(dtMs: Float) {
        sim?.advance(dtMs)
    }

    /**
     * Colour filter for a glyph painted with the picture shader: the picture is dimmed to the
     * cell's brightness and the cell's own colour is added, so dark parts of the picture give the
     * normal green glyph and bright parts show up in the picture's colours (like the OR blend on
     * the desktop).
     */
    private fun filterFor(color: Int, blend: Int): ColorFilter {
        val key = (blend shl 24) or (color and 0x00FFFFFF)
        filters[key]?.let { return it }
        if (filters.size > 4000) filters.clear()
        val r = (color shr 16) and 0xFF
        val g = (color shr 8) and 0xFF
        val b = color and 0xFF
        val f = when (blend) {
            // OR: the picture keeps its brightness and the cell's own (possibly dim) colour is added.
            1 -> LightingColorFilter(Color.WHITE, Color.rgb(r, g, b))
            // AND: the picture is multiplied by the cell colour (picture tinted by the rain).
            2 -> LightingColorFilter(Color.rgb(r, g, b), Color.BLACK)
            // Copy: the glyph shows the picture itself.
            else -> LightingColorFilter(Color.rgb(r, g, b), Color.BLACK)
        }
        filters[key] = f
        return f
    }

    fun draw(canvas: Canvas) {
        val bg = config.bg
        canvas.drawColor((0xFF shl 24) or (bg.r shl 16) or (bg.g shl 8) or bg.b)
        val s = sim ?: return
        val shader = pictureShader
        paint.shader = shader
        val x0 = (width - s.cols * cellW) / 2f
        val y0 = (height - s.rows * cellH) / 2f
        for (row in 0 until s.rows) {
            for (col in 0 until s.cols) {
                val idx = row * s.cols + col
                val color = Palette.color(s, idx, row)
                if (color == Palette.NONE) continue
                val special = s.flags[idx] and CellFlag.SPECIAL_GLYPH != 0
                val g = s.glyph[idx]
                if (special && g >= specialChars.size) continue
                if (!special && g >= GlyphData.shapes.size) continue
                if (shader != null) {
                    // Copy: the cell's depth dims the picture (far streams and trail ends are darker).
                    val tint = if (config.pictureBlend == 0) {
                        val v = (Palette.depthLevel(s, idx, row) * 255).toInt()
                        Color.rgb(v, v, v)
                    } else color
                    paint.colorFilter = filterFor(tint, config.pictureBlend)
                    paint.alpha = (color ushr 24)
                } else {
                    paint.colorFilter = null
                    paint.color = color
                }
                if (special) {
                    canvas.drawText(specialChars, g, 1, x0 + col * cellW, y0 + row * cellH + ascent, paint)
                } else {
                    val bmp = glyphs?.bitmaps?.get(g) ?: continue
                    canvas.drawBitmap(bmp, x0 + col * cellW, y0 + row * cellH, paint)
                }
            }
        }
        paint.shader = null
        paint.colorFilter = null
    }
}
