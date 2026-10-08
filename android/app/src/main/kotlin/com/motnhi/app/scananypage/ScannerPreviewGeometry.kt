package com.motnhi.app.scananypage

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max

internal data class ScannerRect(val left: Float, val top: Float, val right: Float, val bottom: Float)
internal data class ScannerCrop(val x: Int, val y: Int, val width: Int, val height: Int)

/** Geometry for a back-camera TextureView whose producer already orients the sensor buffer. */
internal object ScannerPreviewGeometry {
    @JvmStatic
    fun textureCorners(
        viewWidth: Int,
        viewHeight: Int,
        bufferWidth: Int,
        bufferHeight: Int,
        sensorOrientation: Int,
        displayDegrees: Int,
    ): FloatArray {
        require(viewWidth > 0 && viewHeight > 0 && bufferWidth > 0 && bufferHeight > 0)
        require(sensorOrientation in listOf(0, 90, 180, 270) && displayDegrees in listOf(0, 90, 180, 270))
        val sensorSwapped = sensorOrientation == 90 || sensorOrientation == 270
        val naturalWidth = (if (sensorSwapped) bufferHeight else bufferWidth).toFloat()
        val naturalHeight = (if (sensorSwapped) bufferWidth else bufferHeight).toFloat()
        val displaySwapped = displayDegrees == 90 || displayDegrees == 270
        val orientedWidth = if (displaySwapped) naturalHeight else naturalWidth
        val orientedHeight = if (displaySwapped) naturalWidth else naturalHeight
        val scale = max(viewWidth / orientedWidth, viewHeight / orientedHeight)
        val corners = floatArrayOf(0f, 0f, 1f, 0f, 1f, 1f, 0f, 1f)
        for (index in corners.indices step 2) {
            val x = (corners[index] - 0.5f) * naturalWidth
            val y = (corners[index + 1] - 0.5f) * naturalHeight
            // Correct the display's rotation only. Applying the sensor's quarter
            // turn here again makes the already-oriented texture appear sideways.
            val rotatedX = when (displayDegrees) { 90 -> y; 180 -> -x; 270 -> -y; else -> x }
            val rotatedY = when (displayDegrees) { 90 -> -x; 180 -> -y; 270 -> x; else -> y }
            corners[index] = viewWidth / 2f + rotatedX * scale
            corners[index + 1] = viewHeight / 2f + rotatedY * scale
        }
        return corners
    }

    @JvmStatic
    fun mapGuide(guide: ScannerRect, viewWidth: Int, viewHeight: Int, bitmapWidth: Int, bitmapHeight: Int): ScannerRect {
        require(viewWidth > 0 && viewHeight > 0 && bitmapWidth > 0 && bitmapHeight > 0)
        return ScannerRect(
            (guide.left * bitmapWidth / viewWidth).coerceIn(0f, bitmapWidth.toFloat()),
            (guide.top * bitmapHeight / viewHeight).coerceIn(0f, bitmapHeight.toFloat()),
            (guide.right * bitmapWidth / viewWidth).coerceIn(0f, bitmapWidth.toFloat()),
            (guide.bottom * bitmapHeight / viewHeight).coerceIn(0f, bitmapHeight.toFloat()),
        )
    }

    @JvmStatic
    fun cropBounds(guide: ScannerRect, bitmapWidth: Int, bitmapHeight: Int): ScannerCrop {
        require(bitmapWidth > 0 && bitmapHeight > 0)
        require(listOf(guide.left, guide.top, guide.right, guide.bottom).all { it.isFinite() })
        val left = floor(guide.left).toInt().coerceIn(0, bitmapWidth)
        val top = floor(guide.top).toInt().coerceIn(0, bitmapHeight)
        val right = ceil(guide.right).toInt().coerceIn(0, bitmapWidth)
        val bottom = ceil(guide.bottom).toInt().coerceIn(0, bitmapHeight)
        require(right > left && bottom > top)
        return ScannerCrop(left, top, right - left, bottom - top)
    }
}
