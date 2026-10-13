package com.motnhi.app.scananypage

import android.graphics.Bitmap

/** Versioned observation ONLY. No threshold is a blur or retake decision. */
internal object PageQuality {
    fun assess(bitmap: Bitmap, lines: List<RecognizedTextLine>): Map<String, Any> {
        var samples = 0
        var bright = 0
        var edgeSum = 0.0
        var edgeSquared = 0.0
        val boxes = if (bitmap.width < 3 || bitmap.height < 3) emptyList() else lines.mapNotNull { it.box }
        fun luminance(x: Int, y: Int): Double {
            val color = bitmap.getPixel(x, y)
            return (0.2126 * ((color shr 16) and 255) + 0.7152 * ((color shr 8) and 255) + 0.0722 * (color and 255)) / 255.0
        }
        for (box in boxes) {
            val left = box.left.coerceIn(1, bitmap.width - 2)
            val right = box.right.coerceIn(left, bitmap.width - 2)
            val top = box.top.coerceIn(1, bitmap.height - 2)
            val bottom = box.bottom.coerceIn(top, bitmap.height - 2)
            val stride = maxOf(1, (right - left) / 100)
            for (y in top..bottom step stride) for (x in left..right step stride) {
                val center = luminance(x, y)
                val laplacian = luminance(x - 1, y) + luminance(x + 1, y) + luminance(x, y - 1) + luminance(x, y + 1) - 4 * center
                edgeSum += laplacian
                edgeSquared += laplacian * laplacian
                if (center >= 0.98) bright++
                samples++
            }
        }
        return mutableMapOf<String, Any>(
            "version" to 1,
            "mode" to "observational",
            "textRegionSamples" to samples,
        ).apply {
            if (samples > 0) {
                put("sharpness", edgeSquared / samples - (edgeSum / samples) * (edgeSum / samples))
                put("brightFraction", bright.toDouble() / samples)
                put("textHeightFraction", boxes.map { (it.bottom - it.top).toDouble() / bitmap.height }.average())
            }
        }
    }
}
