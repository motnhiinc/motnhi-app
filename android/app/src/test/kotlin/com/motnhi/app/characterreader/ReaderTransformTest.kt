package com.motnhi.app.characterreader

import org.junit.Assert.*
import org.junit.Test

class ReaderTransformTest {
    @Test fun limitsAndInvalidInputsAreSafe() {
        assertEquals(1.5f, ReaderTransform().adjust(100f, 0f).scale)
        assertEquals(0.5f, ReaderTransform().adjust(0.001f, 0f).scale)
        for (invalid in listOf(Float.NaN, Float.POSITIVE_INFINITY, -1f, 0f)) {
            assertEquals(1f, ReaderTransform().adjust(invalid, 0f).scale)
        }
        assertEquals(ReaderTransform(), ReaderTransform().adjust(Float.NaN, Float.NaN))
    }
    @Test fun yawWrapsAndScaleRemainsIndependent() {
        assertEquals(345f, ReaderTransform().adjust(1f, -15f).yaw)
        assertEquals(15f, ReaderTransform().adjust(1f, 735f).yaw)
        assertEquals(1f, ReaderTransform().adjust(1f, 90f).scale)
    }
    @Test fun moveCancelAndConfirmDoNotMutateTransform() {
        val transform = ReaderTransform().adjust(1.2f, 45f)
        val transaction = PlacementTransaction<String>()
        transaction.confirm("original")
        repeat(10) { transaction.beginMove(); transaction.cancel() }
        assertEquals("original", transaction.committed)
        transaction.beginMove(); transaction.confirm("next")
        assertEquals(ReaderTransform(1.2f, 45f), transform)
    }
    @Test fun depthRequiresEveryCapabilityAndLiveFrameGate() {
        assertTrue(ReaderDepthPolicy.enable(true, true, true, true, true))
        for (missing in 0..4) {
            val gates = BooleanArray(5) { it != missing }
            assertFalse(ReaderDepthPolicy.enable(gates[0], gates[1], gates[2], gates[3], gates[4]))
        }
    }
    @Test fun depthConfigurationWaitsForCapabilityAndRetainsOptInAfterDiscovery() {
        // Init must be DISABLED, never unsupported AUTOMATIC. The typed parameter and
        // session callback share this decision rather than fighting after initialization.
        for (supported in listOf(null, false, true)) {
            assertFalse(ReaderDepthPolicy.requestAutomatic(false, supported))
        }
        assertFalse(ReaderDepthPolicy.requestAutomatic(true, null))
        assertFalse(ReaderDepthPolicy.requestAutomatic(true, false))
        assertTrue(ReaderDepthPolicy.requestAutomatic(true, true))
        repeat(3) { assertTrue(ReaderDepthPolicy.requestAutomatic(true, true)) }
    }
    @Test fun diagnosticsAreFirstOccurrenceAndUnavailableIsNull() {
        val diagnostics = ReaderDiagnostics(100)
        assertNull(diagnostics.elapsed("validDepth"))
        assertTrue(diagnostics.mark("firstFrame", 140))
        assertFalse(diagnostics.mark("firstFrame", 240))
        assertEquals(40L, diagnostics.elapsed("firstFrame"))
    }
}
