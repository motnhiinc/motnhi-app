package com.motnhi.app

import com.motnhi.app.scananypage.PageBoundaryDetector
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class PageBoundaryDetectorTest {
    private val size = 160

    private fun page(left: Int = 24, top: Int = 22, right: Int = 137, bottom: Int = 139): IntArray =
        IntArray(size * size) { index ->
            val x = index % size; val y = index / size
            when {
                x in left until right && y in top until bottom -> 225
                else -> 35
            }
        }

    @Test fun detectsFourOuterEdgesDespiteTextLikeLinesInside() {
        val gray = page()
        for (y in 44..110 step 12) for (x in 40..116) gray[y * size + x] = 30
        val detected = PageBoundaryDetector.detect(gray, size, size)
        assertNotNull(detected)
        assertEquals(24f / size, detected!!.topLeft.x, 0.055f)
        assertEquals(22f / size, detected.topLeft.y, 0.055f)
        assertEquals(137f / size, detected.bottomRight.x, 0.055f)
        assertEquals(139f / size, detected.bottomRight.y, 0.055f)
    }

    @Test fun rejectsAFrameWithoutAllFourEdges() {
        val gray = page()
        for (y in 0 until size) for (x in 137 until size) gray[y * size + x] = 225
        assertNull(PageBoundaryDetector.detect(gray, size, size))
    }

    @Test fun rejectsSmallOrUniformRegions() {
        assertNull(PageBoundaryDetector.detect(IntArray(size * size) { 130 }, size, size))
        assertNull(PageBoundaryDetector.detect(page(60, 60, 97, 98), size, size))
    }

    @Test fun detectsASecondPagePositionAfterMovement() {
        val detected = PageBoundaryDetector.detect(page(16, 15, 125, 127), size, size)
        assertNotNull(detected)
        assertEquals(16f / size, detected!!.topLeft.x, 0.055f)
    }

    @Test fun detectsTiltedPageWithFourConsistentEdges() {
        val gray = IntArray(size * size) { index ->
            val x = index % size; val y = index / size
            if (x >= 22 + 0.1 * (y - 80) && x <= 135 + 0.1 * (y - 80) &&
                y >= 24 + 0.05 * (x - 80) && y <= 137 + 0.05 * (x - 80)) 225 else 35
        }
        val detected = PageBoundaryDetector.detect(gray, size, size)
        assertNotNull(detected)
        assertEquals(true, detected!!.topLeft.x < detected.bottomLeft.x)
        assertEquals(true, detected.topLeft.y < detected.topRight.y)
    }
}
