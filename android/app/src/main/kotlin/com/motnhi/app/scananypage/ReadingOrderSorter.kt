package com.motnhi.app.scananypage

import android.graphics.Rect
import com.google.mlkit.vision.text.Text
import kotlin.math.abs

data class TextLineBox(
    val left: Int,
    val top: Int,
    val right: Int,
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

    fun join(lines: List<RecognizedTextLine>, imageHeight: Int): String =
        ordered(lines, imageHeight).joinToString(separator = "\n") { it.text }

    fun ordered(lines: List<RecognizedTextLine>, imageHeight: Int): List<RecognizedTextLine> {
        val sortedLines = lines.mapNotNull { line ->
            val text = line.text.trim()
            val box = line.box
            if (text.isEmpty() || box == null) {
                null
            } else {
                SortableTextLine(
                    text = text,
                    box = box,
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
            .map { RecognizedTextLine(it.text, it.box) }
    }

    fun normalizedLine(line: RecognizedTextLine, width: Int, height: Int): Map<String, Any>? {
        val box = line.box ?: return null
        val left = box.left.coerceIn(0, width)
        val top = box.top.coerceIn(0, height)
        val right = box.right.coerceIn(0, width)
        val bottom = box.bottom.coerceIn(0, height)
        if (right <= left || bottom <= top) return null
        return mapOf(
            "text" to line.text,
            "left" to left.toDouble() / width,
            "top" to top.toDouble() / height,
            "width" to (right - left).toDouble() / width,
            "height" to (bottom - top).toDouble() / height,
        )
    }

    private data class SortableTextLine(
        val text: String,
        val box: TextLineBox,
        val left: Int,
        val midY: Double,
    )
}

private fun Rect.toTextLineBox(): TextLineBox =
    TextLineBox(left = left, top = top, right = right, bottom = bottom)
