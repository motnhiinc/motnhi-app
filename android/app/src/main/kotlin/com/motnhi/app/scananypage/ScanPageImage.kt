package com.motnhi.app.scananypage

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream

/** The OCR bitmap and the displayed JPEG share exactly the same coordinate space. */
internal class ScanPageImage private constructor(
    val bitmap: Bitmap,
    val jpeg: ByteArray,
) {
    companion object {
        private const val MAX_DIMENSION = 3000
        private const val MAX_BYTES = 8 * 1024 * 1024

        fun fromUri(context: Context, uri: Uri): ScanPageImage {
            val resolver = context.contentResolver
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            val boundsStream = resolver.openInputStream(uri)
                ?: throw IllegalArgumentException("capture_failed")
            boundsStream.use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                throw IllegalArgumentException("capture_failed")
            }
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > MAX_DIMENSION) sample *= 2
            val bitmap = resolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply {
                    inSampleSize = sample
                })
            } ?: throw IllegalArgumentException("capture_failed")
            val exif = resolver.openInputStream(uri)?.use { ExifInterface(it) }
            val matrix = Matrix().apply {
                if (exif?.isFlipped == true) postScale(-1f, 1f)
                postRotate(exif?.rotationDegrees?.toFloat() ?: 0f)
            }
            val corrected = if (matrix.isIdentity) bitmap else
                Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (corrected !== bitmap) bitmap.recycle()
            val output = ByteArrayOutputStream()
            for (quality in listOf(85, 70, 55)) {
                output.reset()
                corrected.compress(Bitmap.CompressFormat.JPEG, quality, output)
                if (output.size() <= MAX_BYTES) break
            }
            if (output.size() > MAX_BYTES) {
                corrected.recycle()
                throw IllegalArgumentException("capture_failed")
            }
            return ScanPageImage(corrected, output.toByteArray())
        }
    }
}
