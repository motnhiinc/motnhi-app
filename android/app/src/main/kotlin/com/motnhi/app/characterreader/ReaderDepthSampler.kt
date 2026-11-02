package com.motnhi.app.characterreader

import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import com.google.ar.core.exceptions.NotYetAvailableException
import java.nio.ByteBuffer

/** Reused scratch storage; no retained Images or hit results across frames. */
internal class ReaderDepthSampler {
    private val view = FloatArray(2)
    private val texture = FloatArray(2)
    private val samples = IntArray(9)

    fun sample(frame: Frame, viewX: Float, viewY: Float): Float? {
        view[0] = viewX
        view[1] = viewY
        frame.transformCoordinates2d(Coordinates2d.VIEW, view, Coordinates2d.TEXTURE_NORMALIZED, texture)
        if (texture.any { !it.isFinite() || it < 0f || it >= 1f }) return null
        return try {
            frame.acquireDepthImage16Bits().use { image ->
                if (image.timestamp <= 0 || frame.timestamp < image.timestamp ||
                    frame.timestamp - image.timestamp > 250_000_000L) return null
                val plane = image.planes[0]
                samplePatch(plane.buffer, image.width, image.height, plane.rowStride,
                    plane.pixelStride, (texture[0] * image.width).toInt(),
                    (texture[1] * image.height).toInt())
            }
        } catch (_: NotYetAvailableException) {
            null
        }
    }

    /** Robust median, requiring a majority of valid, locally consistent measurements. */
    internal fun samplePatch(buffer: ByteBuffer, width: Int, height: Int, rowStride: Int,
        pixelStride: Int, x: Int, y: Int): Float? {
        var count = 0
        for (dy in -1..1) for (dx in -1..1) {
            val px = x + dx
            val py = y + dy
            if (px !in 0 until width || py !in 0 until height) continue
            val index = buffer.position() + py * rowStride + px * pixelStride
            if (index < 0 || index + 1 >= buffer.limit()) continue
            val mm = (buffer.get(index).toInt() and 255) or
                ((buffer.get(index + 1).toInt() and 255) shl 8)
            if (mm in 150..5000) samples[count++] = mm
        }
        if (count < 5) return null
        java.util.Arrays.sort(samples, 0, count)
        val median = samples[count / 2]
        val tolerance = maxOf(40, (median * 0.03f).toInt())
        if ((0 until count).count { kotlin.math.abs(samples[it] - median) <= tolerance } < 5) return null
        return median / 1000f
    }
}
