package app.bavtrix.core

data class Rgba(val r: Int, val g: Int, val b: Int, val a: Int = 255) {
    /** Packed 0xAARRGGBB, as used by Android colors. */
    val argb: Int get() = (a shl 24) or (r shl 16) or (g shl 8) or b
}

/** All user settings. Names and meaning follow the Windows `default.cfg`. */
data class RainConfig(
    val maxStream: Int = 2000,
    val speedVariance: Float = 8f,
    val monotonousCleanup: Boolean = false,
    val backTrace: Int = 40,
    val randomizedCleanup: Boolean = false,
    val leading: Int = 10,
    val spacePad: Int = 30,
    /** Milliseconds a base-speed stream needs to move one row down. */
    val refreshMs: Float = 100f,
    val specialProbability: Float = 0.1f,
    /** Share of time a column carries a stream (rain density), 0..1. */
    val spawnRate: Float = 0.8f,
    /** Shimmer strength of trail characters, 0..1. */
    val flicker: Float = 0.3f,
    /** Chance per frame that a head symbol changes, 0..1. */
    val headFlicker: Float = 1f,
    /** Brightness of heads and flashes, 0.5..2. */
    val headBrightness: Float = 1.3f,
    val trailMin: Int = 16,
    /** 0 = automatic (grows with density). */
    val trailMax: Int = 0,
    val specialStrings: List<String> = listOf("Welcome to BAVtrix"),
    val fg: Rgba = Rgba(187, 255, 187),
    val fade: Rgba = Rgba(0, 128, 0),
    val bg: Rgba = Rgba(0, 0, 0),
    val specialFg: Rgba = Rgba(251, 255, 251),
    val specialFade: Rgba = Rgba(208, 244, 208, 128),
    /** The chosen picture shows through the glyphs (the desktop version's wallpaper effect). */
    val usePicture: Boolean = false,
    /** Bumped whenever the picture file is replaced, so renderers reload it. */
    val pictureVersion: Int = 0,
    /** true = fill the whole screen (crop the picture), false = fit the whole picture. */
    val pictureCover: Boolean = false,
    /** How the picture is mixed with the glyph colour: 0 = Copy, 1 = OR (add), 2 = AND (multiply). */
    val pictureBlend: Int = 0,
    /** Glyph size in dp (small glyphs = many columns, like on the desktop). */
    val glyphSize: Float = 9f,
) {

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
