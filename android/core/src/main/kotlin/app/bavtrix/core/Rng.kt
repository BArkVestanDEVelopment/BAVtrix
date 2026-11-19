package app.bavtrix.core

/** Small deterministic xorshift generator (same family as the Windows and Apple versions). */
class Rng(seed: Long) {
    private var state: ULong = seed.toULong() or 1UL

    fun next(): ULong {
        var x = state
        x = x xor (x shl 13)
        x = x xor (x shr 7)
        x = x xor (x shl 17)
        state = x
        return x * 0x2545F4914F6CDD1DUL
    }

    /** Uniform integer in 0 until n (0 when n <= 0). */
    fun below(n: Int): Int = if (n <= 0) 0 else ((next() shr 11) % n.toULong()).toInt()

    /** Uniform float in 0..1 (exclusive). */
    fun unit(): Float = (next() shr 40).toFloat() / (1 shl 24).toFloat()
}
