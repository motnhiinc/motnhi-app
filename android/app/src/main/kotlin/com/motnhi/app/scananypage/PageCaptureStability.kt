package com.motnhi.app.scananypage

import kotlin.math.abs

/** Stable OCR content and position, measured against the first frame, not slow drift. */
internal class PageCaptureStability(private val requiredFrames: Int = 5) {
    private var text = ""
    private var bounds = emptyList<Float>()
    private var count = 0

    fun reset() {
        text = ""
        bounds = emptyList()
        count = 0
    }

    fun observe(candidate: String, coordinates: List<Float>, acceptable: Boolean): Boolean {
        if (!acceptable || candidate.isBlank() || coordinates.size != 4 ||
            coordinates.any { !it.isFinite() || it !in 0f..1f }) {
            reset()
            return false
        }
        if (candidate != text || bounds.size != 4 ||
            coordinates.indices.any { abs(coordinates[it] - bounds[it]) > 0.015f }) {
            text = candidate
            bounds = coordinates.toList()
            count = 1
        } else {
            count++
        }
        return count >= requiredFrames
    }
}
