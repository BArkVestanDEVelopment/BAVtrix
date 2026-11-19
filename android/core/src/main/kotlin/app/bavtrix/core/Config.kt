package app.bavtrix.core

data class Rgba(val r: Int, val g: Int, val b: Int, val a: Int = 255) {
    /** Packed 0xAARRGGBB, as used by Android colors. */
    val argb: Int get() = (a shl 24) or (r shl 16) or (g shl 8) or b
}

/** All user settings. Names and meaning follow the Windows `default.cfg`. */
data class RainConfig(
    val maxStream: Int = 2000,
    val speedVariance: Float = 5f,
    val monotonousCleanup: Boolean = false,
    val backTrace: Int = 40,
    val randomizedCleanup: Boolean = false,
    val leading: Int = 10,
    val spacePad: Int = 30,
    /** Milliseconds a base-speed stream needs to move one row down. */
    val refreshMs: Float = 50f,
    val specialProbability: Float = 0.1f,
    /** Share of time a column carries a stream (rain density), 0..1. */
    val spawnRate: Float = 0.5f,
    /** Shimmer strength of trail characters, 0..1. */
    val flicker: Float = 0.25f,
    /** Chance per frame that a head symbol changes, 0..1. */
    val headFlicker: Float = 1f,
    /** Brightness of heads and flashes, 0.5..2. */
    val headBrightness: Float = 1.3f,
    val trailMin: Int = 8,
    /** 0 = automatic (grows with density). */
    val trailMax: Int = 0,
    val charset: String = "1234567890ABCDEFGHIJKLMNOPQRSUTVWXYZabcd",
    val specialStrings: List<String> = listOf("The matrix has you"),
    val fg: Rgba = Rgba(187, 255, 187),
    val fade: Rgba = Rgba(0, 128, 0),
    val bg: Rgba = Rgba(0, 0, 0),
    val specialFg: Rgba = Rgba(251, 255, 251),
    val specialFade: Rgba = Rgba(208, 244, 208, 128),
    /** Glyph size in dp. */
    val glyphSize: Float = 14f,
) {
    val charsetChars: CharArray get() = charset.toCharArray()

    /** Unique characters used by the special strings, in order of first use. */
    val specialChars: CharArray
        get() {
            val out = ArrayList<Char>()
            for (s in specialStrings) for (c in s) if (c !in out) out.add(c)
            return out.toCharArray()
        }

    /** Special strings as indices into [specialChars]. */
    val specialIndexStrings: List<List<Int>>
        get() {
            val chars = specialChars.toList()
            return specialStrings
                .map { s -> s.map { chars.indexOf(it) }.filter { it >= 0 } }
                .filter { it.isNotEmpty() }
        }
}
