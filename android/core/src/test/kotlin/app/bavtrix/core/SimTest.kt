package app.bavtrix.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SimTest {
    private fun run(sim: RainSim, seconds: Float, frameMs: Float = 33f) {
        var t = 0f
        while (t < seconds * 1000f) {
            sim.advance(frameMs)
            t += frameMs
        }
    }

    private fun lit(sim: RainSim): Int = sim.flags.count { it and CellFlag.ON != 0 }

    @Test
    fun rainAppearsAndFillsPartOfTheScreen() {
        val sim = RainSim(40, 80, RainConfig(), 1)
        run(sim, 20f)
        assertTrue(sim.streamCount > 0)
        assertTrue(lit(sim) > 0)
        assertTrue(lit(sim) < sim.flags.size)
    }

    @Test
    fun everyLitCellBelongsToAKnownSlot() {
        val sim = RainSim(30, 60, RainConfig(), 2)
        run(sim, 15f)
        val glyphLimit = maxOf(sim.config.charsetChars.size, sim.config.specialChars.size)
        for (i in sim.flags.indices) {
            if (sim.flags[i] and CellFlag.ON == 0) continue
            assertTrue(sim.sid[i] < sim.slots.size)
            assertTrue(sim.glyph[i] < glyphLimit)
        }
    }

    @Test
    fun densitySettingChangesCoverage() {
        val sparse = RainSim(50, 80, RainConfig(spawnRate = 0.1f), 3)
        val dense = RainSim(50, 80, RainConfig(spawnRate = 0.9f), 3)
        run(sparse, 40f)
        run(dense, 40f)
        assertTrue(lit(dense) > lit(sparse))
    }

    @Test
    fun sameSeedGivesSameRain() {
        val a = RainSim(20, 40, RainConfig(), 7)
        val b = RainSim(20, 40, RainConfig(), 7)
        run(a, 10f)
        run(b, 10f)
        assertContentEquals(a.glyph, b.glyph)
        assertContentEquals(a.flags, b.flags)
    }

    @Test
    fun streamsLeaveTheScreenAndSlotsAreRecycled() {
        val sim = RainSim(10, 20, RainConfig(maxStream = 5), 4)
        run(sim, 5f)
        assertTrue(sim.streamCount <= 5)
        run(sim, 120f)
        assertTrue(sim.slots.size < 100)
    }

    @Test
    fun paletteFadesTheTrailAndKeepsTheHeadBright() {
        val sim = RainSim(20, 60, RainConfig(), 5)
        run(sim, 20f)
        var headSum = 0
        var heads = 0
        var trailSum = 0
        var trails = 0
        for (row in 0 until sim.rows) {
            for (col in 0 until sim.cols) {
                val idx = row * sim.cols + col
                val c = Palette.color(sim, idx, row)
                if (c == Palette.NONE) continue
                val lum = ((c shr 16) and 0xFF) + ((c shr 8) and 0xFF) + (c and 0xFF)
                val f = sim.flags[idx]
                if (f and CellFlag.HEAD != 0) {
                    headSum += lum
                    heads++
                } else if (f and CellFlag.FLASH == 0) {
                    trailSum += lum
                    trails++
                }
            }
        }
        assertTrue(heads > 0 && trails > 0)
        assertTrue(headSum / heads > trailSum / trails)
    }

    @Test
    fun specialStringsAreIndexedIntoTheirOwnCharacterList() {
        val cfg = RainConfig(specialStrings = listOf("abc", "cab"))
        assertEquals(3, cfg.specialChars.size)
        assertEquals(listOf(listOf(0, 1, 2), listOf(2, 0, 1)), cfg.specialIndexStrings)
    }
}
