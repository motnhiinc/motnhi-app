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
    /** ARCore depth is camera-space Z, NOT the ray length returned by HitResult.distance. */
    fun depthAgreement(expectedCameraDepth: Float, measuredDepth: Float?): ReaderDepthAgreement {
        if (measuredDepth == null || !measuredDepth.isFinite() || measuredDepth <= 0f ||
            !expectedCameraDepth.isFinite() || expectedCameraDepth <= 0f) {
            return ReaderDepthAgreement.UNAVAILABLE
        }
        return if (abs(expectedCameraDepth - measuredDepth) <= max(0.04f, expectedCameraDepth * 0.03f))
            ReaderDepthAgreement.MATCH else ReaderDepthAgreement.CONFLICT
    }

    fun automaticPlacement(automatic: Boolean, moving: Boolean, ready: Boolean,
        depthSupported: Boolean?, agreement: ReaderDepthAgreement): Boolean =
        automatic && !moving && ready && (depthSupported == false || agreement == ReaderDepthAgreement.MATCH)

    fun supportedContact(tracked: Boolean, inPolygon: Boolean, planeLocalHeight: Float): Boolean =
        tracked && inPolygon && planeLocalHeight.isFinite() && abs(planeLocalHeight) <= 0.03f
}
