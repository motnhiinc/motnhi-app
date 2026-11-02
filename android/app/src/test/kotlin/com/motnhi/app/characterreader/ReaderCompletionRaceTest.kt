package com.motnhi.app.characterreader

import android.media.MediaPlayer
import com.motnhi.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowMediaPlayer
import org.robolectric.shadows.util.DataSource

/** Exercise the real Activity callback/preload path without camera, Compose or ARCore startup. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ReaderCompletionRaceTest {
    private fun field(name: String) = CharacterReaderActivity::class.java.getDeclaredField(name)
        .apply { isAccessible = true }
    private fun CharacterReaderActivity.call(name: String): Any? =
        CharacterReaderActivity::class.java.getDeclaredMethod(name).apply { isAccessible = true }.invoke(this)
    private fun CharacterReaderActivity.player() = field("mediaPlayer").get(this) as MediaPlayer
    private fun CharacterReaderActivity.ui() = field("ui").get(this) as ReaderUiState

    private fun withReader(clipCount: Int = 2, check: (CharacterReaderActivity) -> Unit) {
        val controller = Robolectric.buildActivity(CharacterReaderActivity::class.java)
        val reader = controller.get()
        val paths = (0 until clipCount).map { "/cache/clip$it.mp3" }
        paths.forEach { ShadowMediaPlayer.addMediaInfo(DataSource.toDataSource(it),
            ShadowMediaPlayer.MediaInfo(10_000, 0)) }
        field("pages").set(reader, listOf(StoryReaderPage("p1", 1, paths)))
        field("placed").set(reader, true)
        field("resumed").set(reader, true)
        reader.ui().trackingReady = true
        assertEquals(true, reader.call("preparePlayer"))
        assertEquals(true, reader.call("startPlayer"))
        try { check(reader) } finally { reader.call("releaseAudio") }
    }

    private fun verifyPausedSuccess(moving: Boolean, lifecyclePause: Boolean = false) = withReader { reader ->
        val completed = reader.player()
        val completion = shadowOf(completed).onCompletionListener
        // The platform has completed playback, but delivery of its success listener is queued.
        shadowOf(completed).state = ShadowMediaPlayer.State.PLAYBACK_COMPLETED
        reader.call(if (lifecyclePause) "onPause" else "pausePlayback")
        reader.ui().moving = moving
        completion.onCompletion(completed)
        val next = reader.player()
        assertNotSame(completed, next)
        assertEquals(1, field("clipIndex").getInt(reader))
        assertFalse(next.isPlaying)
        assertFalse(reader.ui().speaking)
        assertEquals(R.string.reader_resume, reader.ui().readLabel)
        assertEquals(DataSource.toDataSource("/cache/clip1.mp3"), shadowOf(next).dataSource)
        // Replaced-player success cannot advance a second time.
        completion.onCompletion(completed)
        assertSame(next, reader.player())
        assertEquals(1, field("clipIndex").getInt(reader))
        reader.ui().moving = false // Cancelling/confirming move itself must not resume.
        assertFalse(next.isPlaying)
        field("resumed").set(reader, true) // Explicit Resume is a foreground user action.
        reader.call("togglePlayback") // Explicit Resume starts the preloaded next clip.
        assertTrue(next.isPlaying)
        assertTrue(reader.ui().speaking)
    }

    @Test fun queuedSuccessAfterPausePreloadsNextAndWaitsForExplicitResume() = verifyPausedSuccess(false)
    @Test fun queuedSuccessAfterMovePreloadsNextAndWaitsForExplicitResume() = verifyPausedSuccess(true)
    @Test fun queuedSuccessAfterLifecyclePauseWaitsForExplicitResume() = verifyPausedSuccess(false, true)

    @Test fun pausedFinalSuccessResetsOnceAndRemainsFinishedWithoutAutoplay() = withReader(1) { reader ->
        val completed = reader.player()
        val completion = shadowOf(completed).onCompletionListener
        reader.call("pausePlayback")
        completion.onCompletion(completed)
        val replay = reader.player()
        assertNotSame(completed, replay)
        assertEquals(0, field("clipIndex").getInt(reader))
        assertEquals(R.string.reader_complete, reader.ui().playbackStatus)
        assertEquals(R.string.reader_read, reader.ui().readLabel)
        assertFalse(replay.isPlaying)
        completion.onCompletion(completed)
        assertSame(replay, reader.player())
        assertFalse(replay.isPlaying)
    }

    @Test fun terminalSuccessAndPausedErrorsRemainIgnored() = withReader { reader ->
        val current = reader.player()
        reader.call("pausePlayback")
        shadowOf(current).invokeErrorListener(1, 0)
        assertEquals(R.string.reader_paused, reader.ui().playbackStatus)
        field("terminal").setBoolean(reader, true)
        shadowOf(current).onCompletionListener.onCompletion(current)
        assertSame(current, reader.player())
        assertEquals(0, field("clipIndex").getInt(reader))
        assertFalse(reader.ui().speaking)
    }

    @Test fun automaticStartWaitsForAudioPlacementAndTrackingAndNeverRestartsAfterPause() = withReader { reader ->
        reader.call("pausePlayback")
        field("automaticStartPending").setBoolean(reader, true)
        field("placedAt").setLong(reader, -1000L)
        reader.ui().preparingNarration = true
        reader.call("maybeAutoStart")
        assertFalse(reader.player().isPlaying)
        reader.ui().preparingNarration = false
        field("placed").setBoolean(reader, false)
        reader.call("maybeAutoStart")
        assertFalse(reader.player().isPlaying)
        field("placed").setBoolean(reader, true)
        reader.ui().trackingReady = false
        reader.call("maybeAutoStart")
        assertFalse(reader.player().isPlaying)
        reader.ui().trackingReady = true
        reader.call("maybeAutoStart")
        assertTrue(reader.player().isPlaying)
        reader.call("pausePlayback")
        reader.call("maybeAutoStart")
        assertFalse(reader.player().isPlaying)
    }

    @Test fun backgroundingConsumesPendingAutomaticStartUntilExplicitPlay() = withReader { reader ->
        reader.call("pausePlayback")
        field("automaticStartPending").setBoolean(reader, true)
        field("placedAt").setLong(reader, -1000L)
        reader.call("onPause")
        reader.call("maybeAutoStart")
        assertFalse(reader.player().isPlaying)
        field("resumed").setBoolean(reader, true)
        reader.call("maybeAutoStart")
        assertFalse(reader.player().isPlaying)
        reader.call("togglePlayback")
        assertTrue(reader.player().isPlaying)
    }
}
