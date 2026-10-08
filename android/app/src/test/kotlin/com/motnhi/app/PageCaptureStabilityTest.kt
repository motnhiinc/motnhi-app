package com.motnhi.app

import com.motnhi.app.scananypage.PageCaptureStability
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PageCaptureStabilityTest {
    private val bounds = listOf(0.1f, 0.2f, 0.9f, 0.7f)

    @Test fun capturesOnlyAfterFiveStableFrames() {
        val rule = PageCaptureStability()
        repeat(4) { assertFalse(rule.observe("A page of text", bounds, true)) }
        assertTrue(rule.observe("A page of text", bounds, true))
    }

    @Test fun movementTextChangesAndLostQualityResetTheStreak() {
        val rule = PageCaptureStability(3)
        repeat(2) { assertFalse(rule.observe("Page one", bounds, true)) }
        assertFalse(rule.observe("Page two", bounds, true))
        assertFalse(rule.observe("Page two", bounds.map { it + 0.02f }, true))
        assertFalse(rule.observe("Page two", bounds, false))
        repeat(2) { assertFalse(rule.observe("Page two", bounds, true)) }
        assertTrue(rule.observe("Page two", bounds, true))
    }

    @Test fun emptyOrInvalidFramesCannotCapture() {
        val rule = PageCaptureStability(1)
        assertFalse(rule.observe("", bounds, true))
        assertFalse(rule.observe("Page", listOf(Float.NaN, 0f, 1f, 1f), true))
        assertFalse(rule.observe("Page", listOf(-0.1f, 0f, 1f, 1f), true))
    }
}
