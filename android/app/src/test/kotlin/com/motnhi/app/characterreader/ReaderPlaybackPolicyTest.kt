package com.motnhi.app.characterreader

import org.junit.Assert.*
import org.junit.Test

class ReaderPlaybackPolicyTest {
    @Test fun pauseRemainsAvailableDuringTrackingDebounceButResumeDoesNot() {
        assertTrue(ReaderPlaybackPolicy.controlEnabled(speaking = true, trackingReady = false))
        assertFalse(ReaderPlaybackPolicy.controlEnabled(speaking = false, trackingReady = false))
        assertTrue(ReaderPlaybackPolicy.controlEnabled(speaking = false, trackingReady = true))
        assertTrue(ReaderPlaybackPolicy.controlEnabled(speaking = true, trackingReady = true))
    }

    @Test fun errorsRequireLiveIntentAndTheCurrentPlayer() {
        assertTrue(ReaderPlaybackPolicy.acceptsCallback(false, true, true))
        // A terminal reader, released/replaced player, or move/lifecycle/user pause each suffices
        // to reject queued errors. Successful completion uses a separate identity-only gate.
        assertFalse(ReaderPlaybackPolicy.acceptsCallback(true, true, true))
        assertFalse(ReaderPlaybackPolicy.acceptsCallback(false, false, true))
        assertFalse(ReaderPlaybackPolicy.acceptsCallback(false, true, false))
        assertFalse(ReaderPlaybackPolicy.acceptsCallback(true, false, false))
    }
    @Test fun successfulCompletionRemainsValidAfterPauseButNotReplacementOrTerminal() {
        assertTrue(ReaderPlaybackPolicy.acceptsCompletion(false, true))
        assertFalse(ReaderPlaybackPolicy.acceptsCompletion(false, false))
        assertFalse(ReaderPlaybackPolicy.acceptsCompletion(true, true))
        assertFalse(ReaderPlaybackPolicy.acceptsCompletion(true, false))
    }

    @Test fun startingRequiresPlacementTrackingAndNoMoveOrTerminalTransition() {
        assertTrue(ReaderPlaybackPolicy.canStart(false, true, false, true))
        assertFalse(ReaderPlaybackPolicy.canStart(true, true, false, true))
        assertFalse(ReaderPlaybackPolicy.canStart(false, false, false, true))
        assertFalse(ReaderPlaybackPolicy.canStart(false, true, true, true))
        assertFalse(ReaderPlaybackPolicy.canStart(false, true, false, false))
    }

    @Test fun legitimateClipCompletionDuringTrackingLossCannotStartTheNextClip() {
        // Its completion is valid, so the Activity can prepare the next clip. The independent
        // start gate closes and that prepared clip remains paused rather than reporting failure.
        assertTrue(ReaderPlaybackPolicy.acceptsCallback(false, true, true))
        assertFalse(ReaderPlaybackPolicy.canStart(false, true, false, false))
        // Recovery changes only spatial readiness: it cannot revive paused playback intent or
        // accept an old error. Only a successful explicit start establishes new intent.
        assertFalse(ReaderPlaybackPolicy.acceptsCallback(false, true, false))
        assertTrue(ReaderPlaybackPolicy.canStart(false, true, false, true))
        assertFalse(ReaderPlaybackPolicy.acceptsCallback(false, false, true))
    }
}
