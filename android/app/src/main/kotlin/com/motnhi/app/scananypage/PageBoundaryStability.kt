package com.motnhi.app.scananypage

import kotlin.math.abs

/** Consecutive stable page corners; OCR wording does not affect the streak. */
internal class PageBoundaryStability(private val requiredFrames: Int = 4, private val tolerance: Float = 0.028f) {
    private var reference: PageQuad? = null
    private var count = 0
    val progress: Int get() = count

    fun reset() { reference = null; count = 0 }

    fun observe(candidate: PageQuad?): Boolean {
        if (candidate == null || candidate.corners().any { !it.x.isFinite() || !it.y.isFinite() }) {
            reset()
            return false
        }
        val previous = reference
        val same = previous != null && previous.corners().zip(candidate.corners()).all { (a, b) ->
            abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
        }
        if (same) count++ else { reference = candidate; count = 1 }
        return count >= requiredFrames
    }
}
