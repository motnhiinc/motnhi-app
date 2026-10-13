package com.motnhi.app.scananypage

import org.junit.Assert.*
import org.junit.Test

class PageLimitsTest {
    @Test fun unicodeCodePointsAndDistinctFailures() {
        assertEquals("no_text", PageLimits.failureCode(listOf(" ")))
        assertEquals("page_too_long", PageLimits.failureCode(List(41) { "chữ" }))
        assertEquals("page_too_long", PageLimits.failureCode(listOf("ế".repeat(4001))))
        assertNull(PageLimits.failureCode(listOf("😀".repeat(4000))))
        assertNull(PageLimits.failureCode(List(40) { "Tiếng Việt" }))
    }
}
