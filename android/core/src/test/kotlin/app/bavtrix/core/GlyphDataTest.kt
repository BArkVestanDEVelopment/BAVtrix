package app.bavtrix.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GlyphDataTest {
    @Test
    fun everyGlyphHasStrokesInsideTheGrid() {
        assertTrue(GlyphData.shapes.size >= 60)
        for (shape in GlyphData.shapes) {
            assertTrue(shape.strokes.isNotEmpty(), "${shape.id} has no strokes")
            for (stroke in shape.strokes) {
                assertTrue(stroke.size >= 4 && stroke.size % 2 == 0, "${shape.id}: bad stroke length")
                for (i in stroke.indices step 2) {
                    assertTrue(stroke[i] in 0 until GlyphData.COLS, "${shape.id}: x out of grid")
                    assertTrue(stroke[i + 1] in 0 until GlyphData.ROWS, "${shape.id}: y out of grid")
                }
            }
        }
    }

    @Test
    fun idsAreUnique() {
        val ids = GlyphData.shapes.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
    }
}