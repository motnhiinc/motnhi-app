package com.motnhi.app

import com.motnhi.app.scananypage.PageBoundaryStability
import com.motnhi.app.scananypage.PagePoint
import com.motnhi.app.scananypage.PageQuad
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PageBoundaryStabilityTest {
    private fun quad(dx: Float = 0f) = PageQuad(
        PagePoint(0.12f + dx, 0.12f), PagePoint(0.88f + dx, 0.12f),
        PagePoint(0.88f + dx, 0.86f), PagePoint(0.12f + dx, 0.86f),
    )

    @Test fun smallJitterCapturesWithoutAnyTextGate() {
        val stability = PageBoundaryStability()
        assertFalse(stability.observe(quad()))
        assertFalse(stability.observe(quad(0.01f)))
        assertFalse(stability.observe(quad(-0.008f)))
        assertTrue(stability.observe(quad(0.005f)))
    }

    @Test fun missingOrMovedPageAndLayoutChangeResetTheStreak() {
        val stability = PageBoundaryStability()
        repeat(3) { assertFalse(stability.observe(quad())) }
        assertFalse(stability.observe(quad(0.08f)))
        assertFalse(stability.observe(null))
        repeat(2) { assertFalse(stability.observe(quad())) }
        stability.reset()
        repeat(3) { assertFalse(stability.observe(quad())) }
        assertTrue(stability.observe(quad()))
    }
}
