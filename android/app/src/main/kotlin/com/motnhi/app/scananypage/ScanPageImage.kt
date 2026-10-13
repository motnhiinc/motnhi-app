package com.motnhi.app.scananypage

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.os.SystemClock
import android.util.Log
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

        fun fromUri(context: Context, uri: Uri, attemptId: String = ""): ScanPageImage {
            val resolver = context.contentResolver
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            val boundsStream = resolver.openInputStream(uri)
                ?: throw IllegalArgumentException("image_decode_failed")
            boundsStream.use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                throw IllegalArgumentException("image_decode_failed")
            }
            var sample = 1
            val longest = maxOf(bounds.outWidth, bounds.outHeight)
            if (bounds.outWidth.toLong() * bounds.outHeight > 200_000_000L) {
                throw IllegalArgumentException("image_decode_failed")
            }
            // Keep at least the target detail, unlike rounding down to 2000px.
            while (longest / (sample * 2) >= MAX_DIMENSION) sample *= 2
            val target = minOf(longest, MAX_DIMENSION)
            val targetWidth = maxOf(1L, (bounds.outWidth.toLong() * target + longest - 1) / longest)
            val targetHeight = maxOf(1L, (bounds.outHeight.toLong() * target + longest - 1) / longest)
            val targetPixels = targetWidth * targetHeight
            val decodePixels = ((bounds.outWidth.toLong() + sample - 1) / sample) *
                ((bounds.outHeight.toLong() + sample - 1) / sample)
            // At most 128 MiB of decode + final ARGB storage (encoding is separate).
            if ((decodePixels + targetPixels) * 4 > 128L * 1024 * 1024) {
                throw IllegalArgumentException("image_decode_failed")
            }
            val decodeStart = SystemClock.elapsedRealtime()
            val bitmap = resolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply {
                    inSampleSize = sample
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                })
            } ?: throw IllegalArgumentException("image_decode_failed")
            Log.d("ScanStages", "attempt=$attemptId stage=decode elapsed_ms=${SystemClock.elapsedRealtime() - decodeStart}")
            var owned = bitmap
            var failureCode = "image_decode_failed"
            try {
                val orientationStart = SystemClock.elapsedRealtime()
                val exif = resolver.openInputStream(uri)?.use { ExifInterface(it) }
                val scale = target.toFloat() / maxOf(bitmap.width, bitmap.height)
                val matrix = Matrix().apply {
                    if (exif?.isFlipped == true) postScale(-1f, 1f)
                    postRotate(exif?.rotationDegrees?.toFloat() ?: 0f)
                    postScale(scale, scale)
                }
                Log.d("ScanStages", "attempt=$attemptId stage=orientation elapsed_ms=${SystemClock.elapsedRealtime() - orientationStart}")
                val resizeStart = SystemClock.elapsedRealtime()
                val corrected = if (matrix.isIdentity) bitmap else
                    Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                if (corrected !== bitmap) bitmap.recycle()
                owned = corrected
                Log.d("ScanStages", "attempt=$attemptId stage=resize_transform elapsed_ms=${SystemClock.elapsedRealtime() - resizeStart} width=${corrected.width} height=${corrected.height}")
                failureCode = "image_encode_failed"
                val encodeStart = SystemClock.elapsedRealtime()
                val output = ByteArrayOutputStream()
                for (quality in listOf(85, 70, 55)) {
                    output.reset()
                    if (!corrected.compress(Bitmap.CompressFormat.JPEG, quality, output)) {
                        throw IllegalArgumentException("image_encode_failed")
                    }
                    if (output.size() <= MAX_BYTES) break
                }
                if (output.size() == 0 || output.size() > MAX_BYTES) {
                    throw IllegalArgumentException("image_encode_failed")
                }
                Log.d("ScanStages", "attempt=$attemptId stage=jpeg_encode elapsed_ms=${SystemClock.elapsedRealtime() - encodeStart} bytes=${output.size()}")
                return ScanPageImage(corrected, output.toByteArray())
            } catch (error: Throwable) {
                if (!owned.isRecycled) owned.recycle()
                throw IllegalArgumentException(failureCode, error)
            }
        }
    }
}
