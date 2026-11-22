package app.bavtrix

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import app.bavtrix.core.GlyphData
import app.bavtrix.core.GlyphShape
import kotlin.math.ceil
import kotlin.math.max

/**
 * The rain glyphs, drawn from strokes (see GlyphData) into small alpha-only bitmaps once, so the
 * rain only has to stamp them with a colour or a shader every frame. No font file is involved.
 */
class GlyphBitmaps(glyphSizePx: Float) {
    val cellW: Int
    val cellH: Int
    val bitmaps: List<Bitmap>

    init {
        cellH = max(ceil(glyphSizePx * 1.15f).toInt(), 6)
        cellW = max(ceil(cellH * 0.62f).toInt(), 4)
        bitmaps = GlyphData.shapes.map { render(it) }
    }

    private fun render(shape: GlyphShape): Bitmap {
        val bmp = Bitmap.createBitmap(cellW, cellH, Bitmap.Config.ALPHA_8)
        val canvas = Canvas(bmp)
        val lineWidth = max(1f, cellH * 0.095f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = lineWidth
            strokeCap = Paint.Cap.SQUARE
            strokeJoin = Paint.Join.MITER
            strokeMiter = 4f
        }
        // The glyph box inside the cell; the margins keep the square line caps inside the bitmap.
        val marginX = max(cellW * 0.12f, lineWidth / 2f + 0.5f)
        val marginY = max(cellH * 0.09f, lineWidth / 2f + 0.5f)
        val stepX = (cellW - 2 * marginX) / (GlyphData.COLS - 1)
        val stepY = (cellH - 2 * marginY) / (GlyphData.ROWS - 1)
        for (stroke in shape.strokes) {
            if (stroke.size < 4) continue
            val path = Path()
            var i = 0
            while (i + 1 < stroke.size) {
                val gx = if (shape.mirror) GlyphData.COLS - 1 - stroke[i] else stroke[i]
                val x = marginX + gx * stepX
                val y = marginY + stroke[i + 1] * stepY
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                i += 2
            }
            canvas.drawPath(path, paint)
        }
        return bmp
    }
}