package com.motnhi.app

import com.motnhi.app.scananypage.ScannerPreviewGeometry
import com.motnhi.app.scananypage.ScannerRect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.hypot

class ScannerPreviewGeometryTest {
    @Test fun everyQuarterTurnFillsTheViewportWithoutStretchingTheBuffer() {
        val viewports = listOf(1080 to 2400, 2400 to 1080, 1536 to 2048)
        val buffers = listOf(1920 to 1080, 1440 to 1080, 1280 to 720)
        for ((w, h) in viewports) for ((bufferW, bufferH) in buffers)
            for (sensor in listOf(0, 90, 180, 270)) for (display in listOf(0, 90, 180, 270)) {
            val points = ScannerPreviewGeometry.textureCorners(w, h, bufferW, bufferH, sensor, display)
            val xs = points.indices.filter { it % 2 == 0 }.map { points[it] }
            val ys = points.indices.filter { it % 2 == 1 }.map { points[it] }
            assertTrue(xs.min() <= 0.01f && xs.max() >= w - 0.01f)
            assertTrue(ys.min() <= 0.01f && ys.max() >= h - 0.01f)
            assertEquals(w / 2f, xs.average().toFloat(), 0.01f)
            assertEquals(h / 2f, ys.average().toFloat(), 0.01f)
            val naturalW = (if (sensor == 90 || sensor == 270) bufferH else bufferW).toFloat()
            val naturalH = (if (sensor == 90 || sensor == 270) bufferW else bufferH).toFloat()
            val horizontalScale = hypot(points[2] - points[0], points[3] - points[1]) / naturalW
            val verticalScale = hypot(points[6] - points[0], points[7] - points[1]) / naturalH
            assertEquals(horizontalScale, verticalScale, 0.001f)
        }
    }

    @Test fun portraitDoesNotRotateTheAlreadyOrientedSensorTextureAgain() {
        val points = ScannerPreviewGeometry.textureCorners(1080, 1920, 1920, 1080, 90, 0)
        assertEquals(0f, points[0], 0.01f)
        assertEquals(0f, points[1], 0.01f)
        assertEquals(1080f, points[2], 0.01f)
        assertEquals(0f, points[3], 0.01f)
    }

    @Test fun displayQuarterTurnHasTheExpectedDirection() {
        val points = ScannerPreviewGeometry.textureCorners(1920, 1080, 1920, 1080, 90, 90)
        assertEquals(0f, points[0], 0.01f)
        assertEquals(1080f, points[1], 0.01f)
        assertEquals(0f, points[2], 0.01f)
        assertEquals(0f, points[3], 0.01f)
    }

    @Test fun guideMapsIntoTheSnapshotAndCropRoundingStaysInsideIt() {
        val guide = ScannerPreviewGeometry.mapGuide(ScannerRect(100f, 200f, 900f, 1400f), 1000, 2000, 500, 1000)
        assertEquals(ScannerRect(50f, 100f, 450f, 700f), guide)
        val crop = ScannerPreviewGeometry.cropBounds(ScannerRect(-0.2f, 1.8f, 502f, 998.1f), 500, 1000)
        assertEquals(0, crop.x)
        assertEquals(1, crop.y)
        assertEquals(500, crop.width)
        assertEquals(998, crop.height)
    }

    @Test(expected = IllegalArgumentException::class)
    fun anEmptyCropIsRejected() {
        ScannerPreviewGeometry.cropBounds(ScannerRect(0f, 0f, 0f, 0f), 100, 100)
    }
}
