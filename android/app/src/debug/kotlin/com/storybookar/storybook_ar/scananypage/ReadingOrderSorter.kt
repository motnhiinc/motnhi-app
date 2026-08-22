package com.storybookar.storybook_ar.scananypage

import android.graphics.Rect
import com.google.mlkit.vision.text.Text
import kotlin.math.abs

data class TextLineBox(
    val left: Int,
    val top: Int,
    val bottom: Int,
) {
    fun midYFraction(imageHeight: Int): Double {
        require(imageHeight > 0) { "imageHeight must be positive" }
        return ((top + bottom) / 2.0) / imageHeight
    }
}

data class RecognizedTextLine(
    val text: String,
    val box: TextLineBox?,
) {
    companion object {
        fun fromMlKit(line: Text.Line): RecognizedTextLine {
            val rect = line.boundingBox
            return RecognizedTextLine(line.text, rect?.toTextLineBox())
        }
    }
}

object ReadingOrderSorter {
    // Provisional parity value from iOS. Do not retune before real-page validation.
    private const val ROW_TOLERANCE = 0.02

    fun join(lines: List<RecognizedTextLine>, imageHeight: Int): String {
        val sortedLines = lines.mapNotNull { line ->
            val text = line.text.trim()
            val box = line.box
            if (text.isEmpty() || box == null) {
                null
            } else {
                SortableTextLine(
                    text = text,
                    left = box.left,
                    midY = box.midYFraction(imageHeight),
                )
            }
        }.sortedBy { it.midY }

        val rows = mutableListOf<MutableList<SortableTextLine>>()
        for (line in sortedLines) {
            val matchingRow = rows.firstOrNull { row ->
                abs(row.first().midY - line.midY) <= ROW_TOLERANCE
            }
            if (matchingRow != null) {
                matchingRow.add(line)
            } else {
                rows.add(mutableListOf(line))
            }
        }

        return rows
            .sortedBy { it.firstOrNull()?.midY ?: 0.0 }
            .flatMap { row -> row.sortedBy { it.left } }
            .joinToString(separator = "\n") { it.text }
            .trim()
    }

    private data class SortableTextLine(
        val text: String,
        val left: Int,
        val midY: Double,
    )
}

private fun Rect.toTextLineBox(): TextLineBox =
    TextLineBox(left = left, top = top, bottom = bottom)
