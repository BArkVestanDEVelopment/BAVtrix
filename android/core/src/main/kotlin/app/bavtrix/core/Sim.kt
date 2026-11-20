package app.bavtrix.core

import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min

object CellFlag {
    const val ON = 1
    const val HEAD = 2
    const val SPECIAL_STREAM = 4
    const val SPECIAL_GLYPH = 8

    /** Short flash of a trail character (drawn with the head colour for one frame). */
    const val FLASH = 16
}

/** Head position and trail length of a stream, looked up by the renderer through [RainSim.sid]. */
class Slot(var head: Int = 0, var len: Int = 0)

private class Stream(
    val col: Int,
    val slot: Int,
    var head: Int,
    val len: Int,
    val speed: Float,
    val shade: Int,
    val specialIdx: Int,
    val specialStart: Int,
) {
    var acc = 0f

    /** True while this stream is the one running down its column. */
    var ownsColumn = true
}

class RainSim(val cols: Int, val rows: Int, initial: RainConfig, seed: Long) {
    // Cell data in parallel arrays (index = row * cols + col).
    val glyph = IntArray(cols * rows)
    val flags = IntArray(cols * rows)

    /** Per-stream brightness (depth effect), 0..255. */
    val shade = IntArray(cols * rows)

    /** Slot of the stream that drew the cell. */
    val sid = IntArray(cols * rows)
    val slots = ArrayList<Slot>()

    private val freeSlots = ArrayList<Int>()
    private val streams = ArrayList<Stream>()
    private val occupied = BooleanArray(cols)
    private val rng = Rng(seed)
    private var charsetCount = 1
    private var specialStrings: List<List<Int>> = emptyList()

    var config: RainConfig = initial
        set(value) {
            field = value
            rebuildDerived()
        }

    init {
        rebuildDerived()
    }

    val streamCount: Int get() = streams.size

    private fun rebuildDerived() {
        charsetCount = max(config.charsetChars.size, 1)
        specialStrings = config.specialIndexStrings
    }

    private fun clearOwn(col: Int, row: Int, id: Int) {
        if (row < 0 || row >= rows) return
        val idx = row * cols + col
        if (flags[idx] != 0 && sid[idx] == id) {
            flags[idx] = 0
            glyph[idx] = 0
            shade[idx] = 0
            sid[idx] = 0
        }
    }

    private fun spawn(dtMs: Float) {
        val p = config
        val d = min(max(p.spawnRate, 0.01f), 0.97f)
        // Trail length range. Denser rain also gets longer streams by default.
        val autoMax = max((rows * (0.3f + 0.5f * d)).toInt(), 12)
        val tmax = max(if (p.trailMax > 0) p.trailMax else autoMax, 3)
        val tmin = min(max(p.trailMin, 2), tmax)
        val avgSpeed = (1 + p.speedVariance) / 2
        // A column is busy while the head of its stream is on screen; after that the next
        // stream may start while the old trail is still fading out below.
        val headMs = max(rows * p.refreshMs / avgSpeed, 1f)
        val rate = d / ((1 - d) * headMs)
        val chance = 1 - exp(-rate * dtMs)

        for (col in 0 until cols) {
            if (streams.size >= p.maxStream) break
            if (occupied[col] || rng.unit() > chance) continue

            val slot: Int
            if (freeSlots.isNotEmpty()) {
                slot = freeSlots.removeAt(freeSlots.size - 1)
            } else {
                slots.add(Slot())
                slot = slots.size - 1
            }
            occupied[col] = true

            var specialIdx = -1
            var specialStart = 0
            if (specialStrings.isNotEmpty() && rng.unit() < p.specialProbability) {
                specialIdx = rng.below(specialStrings.size)
                val len = specialStrings[specialIdx].size
                specialStart = rng.below(max(rows - len, 1))
            }

            val sv = p.speedVariance
            val speed = 1 + rng.unit() * (sv - 1)
            // Depth: faster streams look closer (brighter), with some random variation.
            val near = if (sv > 1) (speed - 1) / (sv - 1) else 0.5f
            val depth = 0.55f * near + 0.45f * rng.unit()
            val len = if (p.monotonousCleanup) max(p.backTrace, 2) else tmin + rng.below(tmax - tmin + 1)
            val head = -1 - rng.below(8)
            slots[slot].head = head
            slots[slot].len = len
            streams.add(
                Stream(
                    col, slot, head, len, speed, min(45 + 210 * depth, 255f).toInt(),
                    specialIdx, specialStart,
                ),
            )
        }
    }

    /** Moves one stream down by a row; returns false when it has left the screen. */
    private fun step(s: Stream): Boolean {
        val col = s.col
        val id = s.slot
        s.head += 1
        val head = s.head
        slots[id].head = head

        if (head - 1 in 0 until rows) {
            val idx = (head - 1) * cols + col
            if (sid[idx] == id) flags[idx] = flags[idx] and CellFlag.HEAD.inv()
        }
        if (head in 0 until rows) {
            var f = CellFlag.ON or CellFlag.HEAD or (if (s.specialIdx >= 0) CellFlag.SPECIAL_STREAM else 0)
            var g = rng.below(charsetCount)
            if (s.specialIdx >= 0) {
                val str = specialStrings[s.specialIdx]
                val off = head - s.specialStart
                if (off >= 0 && off < str.size) {
                    g = str[off]
                    f = f or CellFlag.SPECIAL_GLYPH
                }
            }
            val idx = head * cols + col
            glyph[idx] = g
            flags[idx] = f
            shade[idx] = s.shade
            sid[idx] = id
        }
        if (head >= rows && s.ownsColumn) {
            // The head has left the screen: the column may start a new stream.
            s.ownsColumn = false
            occupied[col] = false
        }
        // The end of the trail is erased as the head moves on.
        clearOwn(col, head - s.len, id)
        if (config.randomizedCleanup) {
            val hi = head - config.leading
            val lo = hi - config.spacePad
            val r = lo + rng.below(max(hi - lo + 1, 1))
            clearOwn(col, r, id)
        }
        return head - s.len < rows
    }

    private fun mutate(col: Int, row: Int, id: Int, flash: Boolean) {
        if (row < 0 || row >= rows) return
        val g = rng.below(charsetCount)
        val idx = row * cols + col
        if (flags[idx] and CellFlag.ON != 0 && sid[idx] == id && flags[idx] and CellFlag.SPECIAL_GLYPH == 0) {
            glyph[idx] = g
            if (flash) flags[idx] = flags[idx] or CellFlag.FLASH
        }
    }

    /** Random character changes inside the streams: this is what makes the rain shimmer. */
    private fun flicker(dtMs: Float) {
        for (i in flags.indices) flags[i] = flags[i] and CellFlag.FLASH.inv()
        val s = config.flicker
        val hs = config.headFlicker
        if (s <= 0f && hs <= 0f) return
        val k = min(max(dtMs / 33f, 0.3f), 3f)
        // 8 attempts per frame: at strength 0.5 about 4 characters of each trail change.
        val pMut = min(s * k, 1f)
        // Head shimmer: `hs` is the chance per 33 ms, so a 120 Hz screen does not strobe.
        val pHead = min(hs * dtMs / 33f, 1f)
        for (st in streams) {
            if (rng.unit() < pHead) mutate(st.col, st.head, st.slot, false)
            for (n in 0 until 8) {
                if (rng.unit() > pMut) continue
                val row = st.head - 1 - rng.below(max(st.len, 1))
                val flash = n < 2 && rng.unit() < s * 0.5f
                mutate(st.col, row, st.slot, flash)
            }
        }
    }

    /** Advances the simulation by [dtMs] milliseconds. */
    fun advance(dtMs: Float) {
        spawn(dtMs)
        flicker(dtMs)
        var i = 0
        while (i < streams.size) {
            val s = streams[i]
            s.acc += dtMs * s.speed
            val n = min((s.acc / config.refreshMs).toInt(), 64)
            s.acc = if (n == 64) 0f else s.acc - n * config.refreshMs
            var alive = true
            for (k in 0 until n) {
                if (!step(s)) {
                    alive = false
                    break
                }
            }
            if (alive) {
                i++
            } else {
                if (s.ownsColumn) occupied[s.col] = false
                freeSlots.add(s.slot)
                val last = streams.removeAt(streams.size - 1)
                if (i < streams.size) streams[i] = last
            }
        }
    }
}
