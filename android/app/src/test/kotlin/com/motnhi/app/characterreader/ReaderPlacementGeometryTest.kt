package com.motnhi.app.characterreader

import org.junit.Assert.*
import org.junit.Test

class ReaderPlacementGeometryTest {
    @Test fun circularFootprintFitsWhereItsEnclosingSquareWouldNot() {
        // The circle fits this diamond-shaped patch, but its enclosing square does not.
        val polygon = java.nio.FloatBuffer.wrap(floatArrayOf(0f, 1f, 1f, 0f, 0f, -1f, -1f, 0f))
        assertTrue(ReaderPlacementGeometry.diskFits(polygon, 0f, 0f, .6f))
        assertFalse(ReaderPlacementGeometry.diskFits(polygon, 0f, 0f, .8f))
        assertFalse(ReaderPlacementGeometry.diskFits(polygon, .5f, 0f, .6f))
        assertFalse(ReaderPlacementGeometry.diskFits(polygon, 2f, 0f, .1f))
        assertEquals(0, polygon.position())
    }

    @Test fun manualTargetSettlesQuicklyButMotionAndMissingHitsStillBlock() {
        val manual = ReaderSurfaceStability<String>(250L, .06f, 4)
        val automatic = ReaderSurfaceStability<String>()
        for (time in 0L..200L step 50) {
            assertFalse(manual.update("table", 0f, 0f, 1f, time))
            assertFalse(automatic.update("table", 0f, 0f, 1f, time))
        }
        assertTrue(manual.update("table", .01f, 0f, 1f, 250))
        assertFalse(automatic.update("table", .01f, 0f, 1f, 250))
        assertFalse(manual.update("table", .2f, 0f, 1f, 300))
        assertFalse(manual.update(null, 0f, 0f, 0f, 350))
    }

    @Test fun stationaryPhoneCanPlaceManuallyButCannotAutoPlace() {
        val stability = ReaderSurfaceStability<String>()
        val verification = ReaderSurfaceVerification<String>()
        var settled = false
        var verified = false
        for (time in 0L..2000L step 50) {
            settled = stability.update("table", 0f, 0f, 1f, time)
            verified = verification.update("table", 0f, 0f, 0f, time)
        }
        val ready = ReaderPlacementGeometry.manualPlacement(true, settled, true, ReaderDepthAgreement.MATCH)
        assertTrue(ready)
        assertFalse(verified)
        assertFalse(ReaderPlacementGeometry.automaticPlacement(true, false, ready && verified,
            true, ReaderDepthAgreement.MATCH))
        // Losing the live target must immediately disable manual placement too.
        settled = stability.update(null, 0f, 0f, 0f, 2050)
        assertFalse(ReaderPlacementGeometry.manualPlacement(false, settled, true, ReaderDepthAgreement.MATCH))
    }

    @Test fun manualPlacementAllowsMissingDepthButRequiresLiveStableTargetAndModel() {
        assertTrue(ReaderPlacementGeometry.manualPlacement(true, true, true, ReaderDepthAgreement.UNAVAILABLE))
        assertFalse(ReaderPlacementGeometry.manualPlacement(true, true, true, ReaderDepthAgreement.CONFLICT))
        assertFalse(ReaderPlacementGeometry.manualPlacement(false, true, true, ReaderDepthAgreement.MATCH))
        assertFalse(ReaderPlacementGeometry.manualPlacement(true, false, true, ReaderDepthAgreement.MATCH))
        assertFalse(ReaderPlacementGeometry.manualPlacement(true, true, false, ReaderDepthAgreement.MATCH))
    }

    @Test fun offsetAndCenteredModelsHaveFeetAtZeroAtEveryUserScale() {
        for (center in listOf(floatArrayOf(0f, 0f, 0f), floatArrayOf(4f, 7f, -2f),
            floatArrayOf(0f, -3f, 0f))) {
            val half = floatArrayOf(1f, 2f, 0.5f)
            val geometry = ReaderModelGeometry.fromBounds(center, half)
            for (userScale in listOf(0.5f, 1f, 1.5f)) {
                assertEquals(0f, ((center[1] - half[1]) * geometry.scale + geometry.y) * userScale, 0.00001f)
                assertEquals(0f, (center[0] * geometry.scale + geometry.x) * userScale, 0.00001f)
                assertEquals(0f, (center[2] * geometry.scale + geometry.z) * userScale, 0.00001f)
                assertEquals(0.35f * userScale, half[1] * 2f * geometry.scale * userScale, 0.00001f)
            }
        }
    }

    @Test fun footprintContainsHorizontalCornersAtEveryHeading() {
        val half = floatArrayOf(2f, 1f, 3f)
        val geometry = ReaderModelGeometry.fromBounds(floatArrayOf(0f, 2f, 0f), half)
        for (angle in 0..360 step 15) {
            val radians = Math.toRadians(angle.toDouble())
            val x = (half[0] * kotlin.math.cos(radians) - half[2] * kotlin.math.sin(radians)) * geometry.scale
            val z = (half[0] * kotlin.math.sin(radians) + half[2] * kotlin.math.cos(radians)) * geometry.scale
            assertTrue(kotlin.math.sqrt(x * x + z * z) < geometry.footprintRadius)
        }
    }

    @Test fun invalidBoundsAreRejectedInsteadOfRenderingNaNTransforms() {
        for (half in listOf(floatArrayOf(0f, 0f, 0f), floatArrayOf(-1f, 1f, 1f),
            floatArrayOf(Float.NaN, 1f, 1f))) {
            assertThrows(IllegalArgumentException::class.java) {
                ReaderModelGeometry.fromBounds(floatArrayOf(0f, 0f, 0f), half)
            }
        }
    }

    @Test fun depthRejectsSurfacesInFrontOfAndBehindMeasuredGeometry() {
        assertEquals(ReaderDepthAgreement.MATCH, ReaderPlacementGeometry.depthAgreement(1f, 1.02f))
        assertEquals(ReaderDepthAgreement.CONFLICT, ReaderPlacementGeometry.depthAgreement(1f, 1.2f))
        assertEquals(ReaderDepthAgreement.CONFLICT, ReaderPlacementGeometry.depthAgreement(1f, 0.8f))
        for (missing in listOf(null, 0f, Float.NaN, Float.POSITIVE_INFINITY)) {
            assertEquals(ReaderDepthAgreement.UNAVAILABLE, ReaderPlacementGeometry.depthAgreement(1f, missing))
        }
    }

    @Test fun automaticPlacementNeverConfirmsMoveOrBypassesAvailableDepth() {
        assertTrue(ReaderPlacementGeometry.automaticPlacement(true, false, true, true, ReaderDepthAgreement.MATCH))
        assertTrue(ReaderPlacementGeometry.automaticPlacement(true, false, true, false, ReaderDepthAgreement.UNAVAILABLE))
        assertFalse(ReaderPlacementGeometry.automaticPlacement(true, false, true, true, ReaderDepthAgreement.UNAVAILABLE))
        assertFalse(ReaderPlacementGeometry.automaticPlacement(true, false, true, null, ReaderDepthAgreement.UNAVAILABLE))
        assertFalse(ReaderPlacementGeometry.automaticPlacement(true, true, true, false, ReaderDepthAgreement.UNAVAILABLE))
        assertFalse(ReaderPlacementGeometry.automaticPlacement(false, false, true, true, ReaderDepthAgreement.MATCH))
        assertFalse(ReaderPlacementGeometry.automaticPlacement(true, false, false, true, ReaderDepthAgreement.MATCH))
    }

    @Test fun trackingAnchorDoesNotProveFeetStillTouchSurface() {
        assertTrue(ReaderPlacementGeometry.supportedContact(true, true, 0.01f))
        assertFalse(ReaderPlacementGeometry.supportedContact(true, true, 0.05f))
        assertFalse(ReaderPlacementGeometry.supportedContact(true, true, -0.05f))
        assertFalse(ReaderPlacementGeometry.supportedContact(false, true, 0f))
        assertFalse(ReaderPlacementGeometry.supportedContact(true, false, 0f))
        assertFalse(ReaderPlacementGeometry.supportedContact(true, true, Float.NaN))
    }

    @Test fun depthDisabledCanAutoPlaceOnDepthCapablePhoneButStillRequiresVerifiedTarget() {
        for (supported in listOf(true, false, null)) {
            assertTrue(ReaderPlacementGeometry.automaticPlacement(true, false, true,
                supported, ReaderDepthAgreement.UNAVAILABLE, requireDepth = false))
            assertFalse(ReaderPlacementGeometry.automaticPlacement(true, false, false,
                supported, ReaderDepthAgreement.UNAVAILABLE, requireDepth = false))
            assertFalse(ReaderPlacementGeometry.automaticPlacement(true, true, true,
                supported, ReaderDepthAgreement.UNAVAILABLE, requireDepth = false))
        }
    }
}
