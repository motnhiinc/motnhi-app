package com.motnhi.app.characterreader

import kotlin.math.atan2

/** Pure policies independent of ARCore/Compose. */
internal object ReaderPresentationPolicy {
    /** Cancel must hide even a retained pose before the next AR frame clears it. */
    fun <T> visiblePreview(hasPlacement: Boolean, moving: Boolean, preview: T?): T? =
        if (!hasPlacement || moving) preview else null

    fun canPlace(cameraTracked: Boolean, planeTracked: Boolean, upward: Boolean, inPolygon: Boolean) =
        cameraTracked && planeTracked && upward && inPolygon

    fun viewerYawDegrees(dx: Float, dz: Float, forwardOffset: Float = 0f): Float =
        Math.toDegrees(atan2(dx, dz).toDouble()).toFloat() + forwardOffset

    // Dolls: Eye_01/Mouth_01 POSITION accessors are on +Z. Fox: Head world +Z,
    // Tail1..8 world -Z. All bundled variants therefore use a +Z authored front.
    fun forwardOffsetDegrees(asset: String): Float = when (asset) {
        "scan_any_page_character.glb",
        "cute_doll_v01.glb", "cute_doll_v02.glb", "cute_doll_v03.glb",
        "cute_doll_v04.glb", "cute_doll_v05.glb", "cute_doll_v06.glb" -> 0f
        else -> 0f // Unknown assets remain stable; do not infer animation from their clip order.
    }

    // All seven bundled assets have audited bounded-root Idle. There is NO talking clip:
    // narration changes the actual playback status, not the body's animation mapping.
    @Suppress("UNUSED_PARAMETER")
    fun animationName(speaking: Boolean, availableNames: Set<String>): String? =
        "Idle".takeIf { it in availableNames }
}

internal class TrackingLossDebouncer(private val delayMillis: Long = 1200L) {
    private var lostAt: Long? = null
    fun update(tracked: Boolean, nowMillis: Long): Boolean {
        if (tracked) {
            lostAt = null
            return false
        }
        val start = lostAt ?: nowMillis.also { lostAt = it }
        return nowMillis - start >= delayMillis
    }
}

/** Require parallax and stable height before trusting a newly reconstructed surface.
 * Target motion along a table is fine; changing its height is not.
 */
internal class ReaderSurfaceVerification<T> {
    private var surface: T? = null
    private var height = 0f
    private var cameraX = 0f
    private var cameraZ = 0f
    private var since = 0L
    private var last = 0L
    private var hasBaseline = false

    fun reset() { surface = null; hasBaseline = false }

    fun update(plane: T?, y: Float, x: Float, z: Float, nowMillis: Long): Boolean {
        if (plane == null || !y.isFinite() || !x.isFinite() || !z.isFinite()) {
            reset()
            return false
        }
        if (surface != plane || nowMillis < last || nowMillis - last > 200) {
            surface = plane
            height = y
            cameraX = x
            cameraZ = z
            since = nowMillis
            hasBaseline = false
        }
        if (kotlin.math.abs(y - height) > 0.02f) {
            // A refined plane must be observed again, not accepted using old evidence.
            height = y
            since = nowMillis
            cameraX = x
            cameraZ = z
            hasBaseline = false
        }
        last = nowMillis
        val dx = x - cameraX
        val dz = z - cameraZ
        hasBaseline = hasBaseline || dx * dx + dz * dz >= 0.08f * 0.08f
        return hasBaseline && nowMillis - since >= 1500L
    }
}

/** A live, bounded patch of the same plane must settle before placement is enabled. */
internal class ReaderSurfaceStability<T>(
    private val settleMillis: Long = 700L,
    private val toleranceMeters: Float = 0.04f,
) {
    private var surface: T? = null
    private var origin = floatArrayOf(0f, 0f, 0f)
    private var since = 0L
    private var last = 0L
    private var samples = 0

    fun reset() { surface = null; samples = 0 }

    fun update(plane: T?, x: Float, y: Float, z: Float, nowMillis: Long): Boolean {
        if (plane == null || !x.isFinite() || !y.isFinite() || !z.isFinite()) {
            reset()
            return false
        }
        val distanceSquared = (x - origin[0]) * (x - origin[0]) +
            (y - origin[1]) * (y - origin[1]) + (z - origin[2]) * (z - origin[2])
        if (surface != plane || nowMillis - last > 200 || nowMillis < last ||
            distanceSquared > toleranceMeters * toleranceMeters) {
            surface = plane
            origin = floatArrayOf(x, y, z)
            since = nowMillis
            samples = 0
        }
        last = nowMillis
        samples++
        return samples >= 10 && nowMillis - since >= settleMillis
    }
}

/** Cancel retains the old placement; confirm returns the anchor to release. */
internal class PlacementTransaction<T> {
    var committed: T? = null
        private set
    var moving = false
        private set
    fun beginMove() { if (committed != null) moving = true }
    fun cancel() { moving = false }
    fun confirm(value: T): T? {
        val previous = committed
        committed = value
        moving = false
        return previous
    }
}
