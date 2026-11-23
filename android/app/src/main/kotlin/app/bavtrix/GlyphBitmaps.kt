package app.bavtrix

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import app.bavtrix.core.GlyphData
import app.bavtrix.core.GlyphShape
import kotlin.math.ceil
import kotlin.math.max

/**
 * The rain glyphs, drawn from strokes (see GlyphData) once into a single alpha-only atlas bitmap.
 * One shared texture lets the GPU batch the thousands of glyph draws of a frame; the rain only
 * stamps rectangles of the atlas with a colour or a shader. No font file is involved.
 */
class GlyphBitmaps(glyphSizePx: Float) {
    val cellW: Int
    val cellH: Int
    val atlas: Bitmap
    /** The same atlas as white-with-alpha ARGB: multiplied with vertex colours by the batched draw. */
    val atlasArgb: Bitmap
    private val perRow = 16

    init {
        cellH = max(ceil(glyphSizePx * 1.15f).toInt(), 6)
        cellW = max(ceil(cellH * 0.62f).toInt(), 4)
        val count = GlyphData.shapes.size
        val rows = (count + perRow - 1) / perRow
        atlas = Bitmap.createBitmap(cellW * perRow, cellH * rows, Bitmap.Config.ALPHA_8)
        val canvas = Canvas(atlas)
        for (i in 0 until count) {
            render(GlyphData.shapes[i], canvas, (i % perRow) * cellW, (i / perRow) * cellH)
        }
        atlasArgb = Bitmap.createBitmap(atlas.width, atlas.height, Bitmap.Config.ARGB_8888)
        Canvas(atlasArgb).drawBitmap(atlas, 0f, 0f, Paint().apply { color = Color.WHITE })
    }

    /** Puts the atlas rectangle of glyph [index] into [out]. */
    fun srcRect(index: Int, out: Rect) {
        val left = (index % perRow) * cellW
        val top = (index / perRow) * cellH
        out.set(left, top, left + cellW, top + cellH)
    }

    private fun render(shape: GlyphShape, canvas: Canvas, ox: Int, oy: Int) {
        val lineWidth = max(1f, cellH * 0.095f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = lineWidth
            strokeCap = Paint.Cap.SQUARE
            strokeJoin = Paint.Join.MITER
            strokeMiter = 4f
        }
        // The glyph box inside the cell; the margins keep the square line caps inside the cell.
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
                val x = ox + marginX + gx * stepX
                val y = oy + marginY + stroke[i + 1] * stepY
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                i += 2
            }
            canvas.drawPath(path, paint)
        }
    }
}
