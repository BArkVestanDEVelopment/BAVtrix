package app.bavtrix

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File

/** The picture that shows through the glyphs: a downscaled private copy of the user's choice. */
object PictureStore {
    private const val FILE = "picture.jpg"
    private const val MAX_SIDE = 2400

    fun file(context: Context): File = File(context.filesDir, FILE)

    /** Decodes [uri] (scaled down to at most ~2400 px) and stores it. Returns false on failure. */
    fun save(context: Context, uri: Uri): Boolean = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (bounds.outWidth / sample > MAX_SIDE || bounds.outHeight / sample > MAX_SIDE) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap = context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, options)
        }
        if (bitmap == null) {
            false
        } else {
            file(context).outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }
            true
        }
    } catch (e: Exception) {
        false
    }

    fun load(context: Context): Bitmap? {
        val f = file(context)
        return if (f.exists()) BitmapFactory.decodeFile(f.path) else null
    }

    fun delete(context: Context) {
        file(context).delete()
    }
}
