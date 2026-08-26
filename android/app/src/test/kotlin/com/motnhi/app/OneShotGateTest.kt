package com.motnhi.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OneShotGateTest {
    @Test
    fun oneShotGateCanOnlyBeClaimedOnce() {
        val gate = OneShotGate()

        assertTrue(gate.claim())
        assertFalse(gate.claim())
    }

    @Test
    fun oneAtATimeGateRejectsDuplicateCallsUntilFinished() {
        val gate = OneAtATimeGate()

        assertTrue(gate.tryStart())
        assertTrue(gate.isInProgress())
        assertFalse(gate.tryStart())
        assertTrue(gate.finish())
        assertFalse(gate.isInProgress())
        assertTrue(gate.tryStart())
    }

    @Test
    fun oneAtATimeGateDropsLateFinishWhenNoCallIsPending() {
        val gate = OneAtATimeGate()

        assertFalse(gate.finish())
    }
}
