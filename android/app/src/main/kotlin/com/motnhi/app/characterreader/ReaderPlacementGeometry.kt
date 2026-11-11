package com.motnhi.app.characterreader

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/** Keep geometry arithmetic independent of Filament so offset assets can be regression tested. */
internal data class ReaderModelGeometry(
    val scale: Float,
    val x: Float,
    val y: Float,
    val z: Float,
    val footprintRadius: Float,
) {
    companion object {
        fun fromBounds(center: FloatArray, half: FloatArray): ReaderModelGeometry {
            require(center.size == 3 && half.size == 3)
            require(center.all { it.isFinite() } && half.all { it.isFinite() && it >= 0f })
            val extent = 2f * half.max()
            require(extent > 0f)
            val scale = 0.35f / extent
            return ReaderModelGeometry(scale, -center[0] * scale,
                -(center[1] - half[1]) * scale, -center[2] * scale,
                // Rotation-independent disk enclosing the model's horizontal bounds + 1 cm margin.
                sqrt(half[0] * half[0] + half[2] * half[2]) * scale + 0.01f)
        }
    }
}

internal enum class ReaderDepthAgreement { UNAVAILABLE, MATCH, CONFLICT }

internal object ReaderPlacementGeometry {
    /** ARCore polygons are convex; the center must be inside and clear every edge. */
    fun diskFits(polygon: java.nio.FloatBuffer, x: Float, z: Float, radius: Float): Boolean {
        val start = polygon.position()
        val count = polygon.remaining() / 2
        if (count < 3 || !x.isFinite() || !z.isFinite() || !radius.isFinite() || radius < 0f) return false
        var positive = false
        var negative = false
        for (i in 0 until count) {
            val next = (i + 1) % count
            val ax = polygon.get(start + 2 * i)
            val az = polygon.get(start + 2 * i + 1)
            if (!ax.isFinite() || !az.isFinite()) return false
            val dx = polygon.get(start + 2 * next) - ax
            val dz = polygon.get(start + 2 * next + 1) - az
            val lengthSquared = dx * dx + dz * dz
            if (!lengthSquared.isFinite() || lengthSquared <= 0f) return false
            val cross = dx * (z - az) - dz * (x - ax)
            positive = positive || cross > 0f
            negative = negative || cross < 0f
            if (positive && negative) return false
            if (cross * cross + 0.00000001f < radius * radius * lengthSquared) return false
        }
        return true
    }

    /** ARCore depth is camera-space Z, NOT the ray length returned by HitResult.distance. */
    fun depthAgreement(expectedCameraDepth: Float, measuredDepth: Float?): ReaderDepthAgreement {
        if (measuredDepth == null || !measuredDepth.isFinite() || measuredDepth <= 0f ||
            !expectedCameraDepth.isFinite() || expectedCameraDepth <= 0f) {
            return ReaderDepthAgreement.UNAVAILABLE
        }
        return if (abs(expectedCameraDepth - measuredDepth) <= max(0.04f, expectedCameraDepth * 0.03f))
            ReaderDepthAgreement.MATCH else ReaderDepthAgreement.CONFLICT
    }

    /** Explicit placement needs a live, stable target, not a camera-motion baseline. */
    fun manualPlacement(liveHit: Boolean, targetSettled: Boolean, modelReady: Boolean,
        agreement: ReaderDepthAgreement): Boolean =
        liveHit && targetSettled && modelReady && agreement != ReaderDepthAgreement.CONFLICT

    fun automaticPlacement(automatic: Boolean, moving: Boolean, ready: Boolean,
        depthSupported: Boolean?, agreement: ReaderDepthAgreement, requireDepth: Boolean = true): Boolean =
        automatic && !moving && ready &&
            (!requireDepth || depthSupported == false || agreement == ReaderDepthAgreement.MATCH)

    fun supportedContact(tracked: Boolean, inPolygon: Boolean, planeLocalHeight: Float): Boolean =
        tracked && inPolygon && planeLocalHeight.isFinite() && abs(planeLocalHeight) <= 0.03f
}
