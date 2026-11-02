package com.motnhi.app.characterreader

import org.junit.Assert.*
import org.junit.Test

class ReaderPresentationPolicyTest {
    @Test fun automaticDepthEvidenceMustBeContinuousAndAtTheSameTarget() {
        val stable = ReaderSurfaceStability<String>(settleMillis = 350L)
        for (time in 0L..330L step 30) assertFalse(stable.update("floor", 0f, 0f, 0f, time))
        assertTrue(stable.update("floor", 0f, 0f, 0f, 360))
        assertFalse(stable.update(null, 0f, 0f, 0f, 390))
        assertFalse(stable.update("floor", 0f, 0f, 0f, 420))
        for (time in 450L..780L step 30) stable.update("floor", 0f, 0f, 0f, time)
        assertTrue(stable.update("floor", 0f, 0f, 0f, 810))
        assertFalse(stable.update("floor", 0.2f, 0f, 0f, 840))
    }

    @Test fun stationaryCameraCannotVerifyAnEarlyPlaneEvenAfterLongWait() {
        val verification = ReaderSurfaceVerification<String>()
        for (time in 0L..5000L step 50) {
            assertFalse(verification.update("floor", 0f, 0f, 0f, time))
        }
        assertTrue(verification.update("floor", 0f, 0.09f, 0f, 5050))
    }

    @Test fun refinedHeightRequiresFreshBaselineAndObservationWindow() {
        val verification = ReaderSurfaceVerification<String>()
        for (time in 0L..1500L step 50) {
            verification.update("floor", 0f, time / 15000f, 0f, time)
        }
        assertTrue(verification.update("floor", 0f, 0.1f, 0f, 1550))
        assertFalse(verification.update("floor", -0.1f, 0.1f, 0f, 1600))
        for (time in 1650L..3050L step 50) {
            assertFalse(verification.update("floor", -0.1f, 0.2f, 0f, time))
        }
        assertTrue(verification.update("floor", -0.1f, 0.2f, 0f, 3100))
        assertFalse(verification.update("table", 0.5f, 0.2f, 0f, 3150))
    }

    @Test fun lostTrackingAndFrameGapsDiscardSurfaceEvidence() {
        val verification = ReaderSurfaceVerification<String>()
        for (time in 0L..1500L step 50) {
            verification.update("floor", 0f, time / 15000f, 0f, time)
        }
        assertTrue(verification.update("floor", 0f, 0.1f, 0f, 1550))
        assertFalse(verification.update("floor", 0f, 0.1f, 0f, 1900))
        for (time in 1950L..3400L step 50) {
            verification.update("floor", 0f, 0.2f, 0f, time)
        }
        assertTrue(verification.update("floor", 0f, 0.2f, 0f, 3450))
        assertFalse(verification.update(null, 0f, 0.2f, 0f, 3500))
        assertFalse(verification.update("floor", 0f, 0.2f, 0f, 3550))
    }

    @Test fun measuredSurfaceMustSettleAndChangingFloorsResetsReadiness() {
        val stable = ReaderSurfaceStability<String>()
        for (time in 0L..650L step 50) assertFalse(stable.update("floor", 0f, 0f, 1f, time))
        assertTrue(stable.update("floor", 0.01f, 0f, 1f, 700))
        assertFalse(stable.update("table", 0.01f, 0f, 1f, 750))
        for (time in 800L..1400L step 50) assertFalse(stable.update("table", 0.01f, 0f, 1f, time))
        assertTrue(stable.update("table", 0.01f, 0f, 1f, 1450))
        assertFalse(stable.update("table", 0.01f, 0.1f, 1f, 1500))
    }

    @Test fun missingSurfaceOrFrameGapCannotReusePreviouslyReadyPlacement() {
        val stable = ReaderSurfaceStability<String>()
        for (time in 0L..700L step 50) stable.update("floor", 0f, 0f, 0f, time)
        assertTrue(stable.update("floor", 0f, 0f, 0f, 750))
        assertFalse(stable.update(null, 0f, 0f, 0f, 800))
        assertFalse(stable.update("floor", 0f, 0f, 0f, 850))
        for (time in 900L..1550L step 50) stable.update("floor", 0f, 0f, 0f, time)
        assertTrue(stable.update("floor", 0f, 0f, 0f, 1600))
        assertFalse(stable.update("floor", 0f, 0f, 0f, 2000))
        assertFalse(stable.update("floor", Float.NaN, 0f, 0f, 2050))
    }
    @Test fun cancelMoveHidesRetainedPreviewBeforeAnotherArFrame() {
        val placement = PlacementTransaction<String>()
        val retainedPreview = "candidate pose"
        assertEquals(retainedPreview, ReaderPresentationPolicy.visiblePreview(
            hasPlacement = false, moving = false, preview = retainedPreview))
        placement.confirm("original anchor")
        repeat(3) {
            placement.beginMove()
            assertEquals(retainedPreview, ReaderPresentationPolicy.visiblePreview(
                placement.committed != null, placement.moving, retainedPreview))
            placement.cancel()
            // Same candidate is deliberately retained, as it is until the next AR frame.
            assertNull(ReaderPresentationPolicy.visiblePreview(
                placement.committed != null, placement.moving, retainedPreview))
            assertEquals("original anchor", placement.committed)
        }
        placement.beginMove()
        placement.confirm("new anchor")
        assertNull(ReaderPresentationPolicy.visiblePreview(true, placement.moving, retainedPreview))
        assertNull(ReaderPresentationPolicy.visiblePreview<String>(true, true, null))
    }

    @Test fun placementRequiresEveryLiveGate() {
        assertTrue(ReaderPresentationPolicy.canPlace(true, true, true, true))
        for (missing in 0..3) {
            val gates = BooleanArray(4) { it != missing }
            assertFalse(ReaderPresentationPolicy.canPlace(gates[0], gates[1], gates[2], gates[3]))
        }
    }

    @Test fun trackingLossDebouncesAndRecoveryStartsANewWindow() {
        val tracking = TrackingLossDebouncer(1200)
        assertFalse(tracking.update(false, 0))
        assertFalse(tracking.update(false, 1199))
        assertTrue(tracking.update(false, 1200))
        assertFalse(tracking.update(true, 1201))
        assertFalse(tracking.update(false, 2000))
        assertTrue(tracking.update(false, 3200))
    }

    @Test fun moveCancelRetainsAnchorAndConfirmReleasesOnlyOldAnchor() {
        val placement = PlacementTransaction<String>()
        placement.beginMove()
        assertFalse(placement.moving)
        assertNull(placement.confirm("old"))
        repeat(10) {
            placement.beginMove()
            assertTrue(placement.moving)
            assertEquals("old", placement.committed)
            placement.cancel()
            assertFalse(placement.moving)
            assertEquals("old", placement.committed)
        }
        placement.beginMove()
        assertEquals("old", placement.confirm("new"))
        assertEquals("new", placement.committed)
        assertFalse(placement.moving)
    }

    @Test fun yawFacesViewerWithoutPitchOrRoll() {
        assertEquals(0f, ReaderPresentationPolicy.viewerYawDegrees(0f, 1f), 0.001f)
        assertEquals(90f, ReaderPresentationPolicy.viewerYawDegrees(1f, 0f), 0.001f)
        assertEquals(180f, ReaderPresentationPolicy.viewerYawDegrees(0f, -1f), 0.001f)
        assertEquals(-90f, ReaderPresentationPolicy.viewerYawDegrees(-1f, 0f), 0.001f)
        assertEquals(180f, ReaderPresentationPolicy.viewerYawDegrees(0f, 1f, 180f), 0.001f)
    }

    @Test fun unverifiedAnimationNamesNeverBecomeSpeakingGestures() {
        val clips = setOf("Idle", "Happy", "Eating", "ZZ_ALLAnim")
        assertEquals("Idle", ReaderPresentationPolicy.animationName(false, clips))
        assertEquals("Idle", ReaderPresentationPolicy.animationName(true, clips))
        assertNull(ReaderPresentationPolicy.animationName(true, emptySet()))
    }
}
