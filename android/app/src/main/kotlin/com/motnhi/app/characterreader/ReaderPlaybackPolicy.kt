package com.motnhi.app.characterreader

/** Playback intent is independent of MediaPlayer.isPlaying (false when completion is delivered). */
internal object ReaderPlaybackPolicy {
    fun acceptsCompletion(terminal: Boolean, currentPlayer: Boolean): Boolean =
        !terminal && currentPlayer

    fun acceptsCallback(terminal: Boolean, currentPlayer: Boolean, playbackActive: Boolean): Boolean =
        !terminal && currentPlayer && playbackActive

    fun canStart(terminal: Boolean, placed: Boolean, moving: Boolean, trackingReady: Boolean): Boolean =
        !terminal && placed && !moving && trackingReady

    // Tracking gates starting/resuming, never the user's ability to pause existing narration.
    fun controlEnabled(speaking: Boolean, trackingReady: Boolean): Boolean = speaking || trackingReady
}
