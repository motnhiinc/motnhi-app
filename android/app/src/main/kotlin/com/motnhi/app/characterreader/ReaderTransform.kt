package com.motnhi.app.characterreader

/** Relative to 0.35 m authored normalization. Conservative limits need device tuning. */
internal data class ReaderTransform(val scale: Float = 1f, val yaw: Float = 0f) {
    fun adjust(zoom: Float, rotation: Float): ReaderTransform = copy(
        scale = if (zoom.isFinite() && zoom > 0f) (scale * zoom).coerceIn(0.5f, 1.5f) else scale,
        yaw = if (rotation.isFinite()) ((yaw + rotation) % 360f + 360f) % 360f else yaw,
    )
}

/** No geometry visibility is gated on depth: missing/unsupported depth means flat camera. */
internal object ReaderDepthPolicy {
    // Unknown capability is OFF too. Both initial and reactive configuration must use this.
    fun requestAutomatic(requested: Boolean, supported: Boolean?) = requested && supported == true

    fun enable(requested: Boolean, supported: Boolean, configured: Boolean, tracked: Boolean,
        validImage: Boolean) = requested && supported && configured && tracked && validImage
}

/** First-occurrence native monotonic timing; null means not observed, never a fabricated zero. */
internal class ReaderDiagnostics(private val started: Long) {
    private val observations = linkedMapOf<String, Long>()
    fun mark(name: String, now: Long): Boolean {
        if (name in observations) return false
        observations[name] = (now - started).coerceAtLeast(0)
        return true
    }
    fun elapsed(name: String): Long? = observations[name]
}
