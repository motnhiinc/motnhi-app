package com.motnhi.app.scananypage

import org.junit.Assert.*
import org.junit.Test

class ScanCaptureStabilityTest {
    private val bounds = floatArrayOf(.1f, .1f, .9f, .9f)
    @Test fun capturesOnlyAfterContinuousReadableStableText() {
        val stability = ScanCaptureStability()
        for (time in 0L..1400L step 200) {
            assertTrue(stability.observe("A readable page", bounds, true, time) < 1)
        }
        assertEquals(1f, stability.observe("A readable page", bounds, true, 1600), 0f)
    }
    @Test fun poorQualityMissingTextNewPageAndFrameGapsResetDwell() {
        for (kind in listOf("quality", "missing", "newPage", "gap")) {
            val stability = ScanCaptureStability()
            for (time in 0L..1400L step 200) stability.observe("page", bounds, true, time)
            val progress = when (kind) {
                "quality" -> stability.observe("page", bounds, false, 1600)
                "missing" -> stability.observe("", null, true, 1600)
                "newPage" -> stability.observe("different", bounds, true, 1600)
                else -> stability.observe("page", bounds, true, 2200)
            }
            assertEquals(kind, 0f, progress, 0f)
        }
    }
    @Test fun slowDriftCannotAccumulateIntoCapture() {
        val stability = ScanCaptureStability()
        for (index in 0..20) {
            val moved = bounds.map { it + index * .005f }.toFloatArray()
            assertTrue(stability.observe("page", moved, true, index * 200L) < 1)
        }
    }
}
