package com.motnhi.app.scananypage

import org.junit.Assert.assertEquals
import org.junit.Test

class ReadingOrderSorterTest {
    @Test
    fun sortsTopToBottomForTopLeftOriginBoxes() {
        val lines = listOf(
            line("Bottom", left = 10, top = 800, bottom = 880),
            line("Top", left = 10, top = 100, bottom = 180),
        )

        assertEquals("Top\nBottom", ReadingOrderSorter.join(lines, imageHeight = 1000))
    }

    @Test
    fun sortsLeftToRightWithinSharedRow() {
        val lines = listOf(
            line("right", left = 600, top = 100, bottom = 180),
            line("left", left = 100, top = 110, bottom = 190),
        )

        assertEquals("left\nright", ReadingOrderSorter.join(lines, imageHeight = 1000))
    }

    @Test
    fun comparesRowsAgainstFirstLineNotRunningCentroid() {
        // C is within tolerance of B (0.009) and of the running centroid of A+B (0.019) but not
        // of A (0.029), the row's first line. Both wrong rules therefore pull C into row one,
        // where its smaller left sorts it ahead of A and yields "C\nA\nB". The margins are wide
        // enough that float representation cannot flip a comparison at the 0.02 boundary.
        val lines = listOf(
            line("A", left = 100, top = 100, bottom = 100),
            line("B", left = 200, top = 120, bottom = 120),
            line("C", left = 50, top = 129, bottom = 129),
        )

        assertEquals("A\nB\nC", ReadingOrderSorter.join(lines, imageHeight = 1000))
    }

    @Test
    fun dropsWhitespaceAndLinesWithoutBoundingBoxesBeforeGrouping() {
        val lines = listOf(
            line("  Top  ", left = 10, top = 100, bottom = 180),
            RecognizedTextLine("Missing box", box = null),
            line("   ", left = 20, top = 110, bottom = 190),
            line("Bottom", left = 10, top = 700, bottom = 780),
        )

        assertEquals("Top\nBottom", ReadingOrderSorter.join(lines, imageHeight = 1000))
    }

    @Test
    fun preservesVietnameseDiacritics() {
        val lines = listOf(
            line("Chú thỏ ngắm ánh trăng.", left = 10, top = 100, bottom = 180),
        )

        assertEquals(
            "Chú thỏ ngắm ánh trăng.",
            ReadingOrderSorter.join(lines, imageHeight = 1000),
        )
    }

    private fun line(
        text: String,
        left: Int,
        top: Int,
        bottom: Int,
    ): RecognizedTextLine = RecognizedTextLine(
        text = text,
        box = TextLineBox(left = left, top = top, bottom = bottom),
    )
}
