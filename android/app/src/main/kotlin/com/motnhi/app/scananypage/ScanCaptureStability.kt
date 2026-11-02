package com.motnhi.app.scananypage

/** Compares against the start of a dwell, not just the preceding frame. */
internal class ScanCaptureStability {
    private var text: String? = null
    private var box: FloatArray? = null
    private var since = 0L
    private var last = 0L

    fun reset() { text = null; box = null; since = 0; last = 0 }

    fun observe(words: String, bounds: FloatArray?, quality: Boolean, now: Long): Float {
        if (!quality || bounds == null || bounds.size != 4 || words.isBlank() ||
            bounds.any { !it.isFinite() }) { reset(); return 0f }
        val previous = box
        if (text != words || previous == null || now - last > 700 || now < last ||
            bounds.indices.any { kotlin.math.abs(bounds[it] - previous[it]) > 0.025f }) {
            text = words; box = bounds.copyOf(); since = now
        }
        last = now
        return ((now - since) / 1600f).coerceIn(0f, 1f)
    }
}
