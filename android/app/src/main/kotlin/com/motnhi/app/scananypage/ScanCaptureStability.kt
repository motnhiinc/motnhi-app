package com.motnhi.app.scananypage

/** Compares against the start of a dwell, not just the preceding frame. */
internal class ScanCaptureStability {
    private var text: Set<String>? = null
    private var box: FloatArray? = null
    private var since = 0L
    private var last = 0L

    fun reset() { text = null; box = null; since = 0; last = 0 }

    fun observe(words: String, bounds: FloatArray?, quality: Boolean, now: Long): Float {
        if (!quality || bounds == null || bounds.size != 4 || words.isBlank() ||
            bounds.any { !it.isFinite() }) { reset(); return 0f }
        val previous = box
        // Live OCR can vary punctuation, accents and a few words on a stationary page.
        // Compare with the dwell's original text so successive changes cannot drift to a new page.
        val tokens = java.text.Normalizer.normalize(words.lowercase(java.util.Locale.ROOT),
            java.text.Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
            .split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.toSet()
        val baseline = text
        val sameText = baseline != null && tokens.isNotEmpty() &&
            tokens.count { it in baseline }.toFloat() / maxOf(tokens.size, baseline.size) >= 0.8f
        if (!sameText || previous == null || now - last > 700 || now < last ||
            bounds.indices.any { kotlin.math.abs(bounds[it] - previous[it]) > 0.025f }) {
            text = tokens; box = bounds.copyOf(); since = now
        }
        last = now
        return ((now - since) / 1600f).coerceIn(0f, 1f)
    }
}
