package com.motnhi.app.characterreader

import android.media.MediaPlayer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowMediaPlayer
import org.robolectric.shadows.util.DataSource

/** Drive the same callbacks as the native overlay, without starting camera/ARCore. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ReaderUiTransitionsTest {
    private fun field(name: String) = CharacterReaderActivity::class.java.getDeclaredField(name)
        .apply { isAccessible = true }
    private fun CharacterReaderActivity.call(name: String): Any? =
        CharacterReaderActivity::class.java.getDeclaredMethod(name).apply { isAccessible = true }.invoke(this)
    private fun CharacterReaderActivity.player() = field("mediaPlayer").get(this) as MediaPlayer
    private fun CharacterReaderActivity.ui() = field("ui").get(this) as ReaderUiState

    private fun withReader(clipCount: Int = 1, check: (CharacterReaderActivity, ReaderUiState) -> Unit) {
        val reader = Robolectric.buildActivity(CharacterReaderActivity::class.java).get()
        val paths = (0 until clipCount).map { "/cache/ui-clip$it.mp3" }
        paths.forEach { ShadowMediaPlayer.addMediaInfo(DataSource.toDataSource(it), ShadowMediaPlayer.MediaInfo(10_000, 0)) }
        field("pages").set(reader, listOf(StoryReaderPage("p1", 1, paths)))
        field("placed").setBoolean(reader, true)
        field("resumed").setBoolean(reader, true)
        reader.ui().apply { controlsVisible = true; trackingReady = true }
        assertEquals(true, reader.call("preparePlayer"))
        assertEquals(true, reader.call("startPlayer"))
        try { check(reader, reader.ui()) } finally { reader.call("releaseAudio") }
    }

    @Test fun moreAdjustmentsAndDoneNeverResumeNarration() = withReader { reader, state ->
        assertEquals(ReaderPlaybackState.READING, state.playback)
        state.openPanel(ReaderPanel.MORE) { reader.call("interruptPlayback") }
        assertFalse(reader.player().isPlaying)
        assertEquals(ReaderPlaybackState.PAUSED, state.playback)
        state.panel = ReaderPanel.ADJUSTMENTS
        state.panel = ReaderPanel.MORE
        state.dismissPanel()
        assertFalse(reader.player().isPlaying)
        assertEquals(ReaderPlaybackState.PAUSED, state.playback)
        reader.call("togglePlayback")
        assertTrue(reader.player().isPlaying)
    }

    @Test fun completedPageSurvivesSheetAndListeningCancellation() = withReader { reader, state ->
        val completed = reader.player()
        val completion = shadowOf(completed).onCompletionListener
        state.openPanel(ReaderPanel.MORE) { reader.call("interruptPlayback") }
        completion.onCompletion(completed)
        assertEquals(ReaderPanel.MORE, state.panel)
        assertEquals(ReaderPlaybackState.COMPLETED, state.playback)
        state.dismissPanel()
        state.openPanel(ReaderPanel.VOICE) { reader.call("interruptPlayback") }
        state.listening = true
        reader.call("interruptPlayback")
        state.dismissPanel()
        assertFalse(state.listening)
        assertEquals(ReaderPlaybackState.COMPLETED, state.playback)
        assertFalse(reader.player().isPlaying)
    }

    @Test fun intermediateCompletionInSheetPreloadsButDoesNotPlay() = withReader(2) { reader, state ->
        val completed = reader.player()
        state.openPanel(ReaderPanel.MORE) { reader.call("interruptPlayback") }
        shadowOf(completed).onCompletionListener.onCompletion(completed)
        assertNotSame(completed, reader.player())
        assertEquals(ReaderPlaybackState.PAUSED, state.playback)
        state.dismissPanel()
        assertFalse(reader.player().isPlaying)
        reader.call("togglePlayback")
        assertTrue(reader.player().isPlaying)
    }

    @Test fun movingAndCancelRetainCommittedPlacementAndTransform() = withReader { reader, state ->
        val original = Any()
        val placement = PlacementTransaction<Any>().apply { confirm(original) }
        state.transform = ReaderTransform().adjust(1.2f, 30f)
        val transform = state.transform
        state.openPanel(ReaderPanel.MORE) { reader.call("interruptPlayback") }
        state.beginMove { reader.call("interruptPlayback") }
        placement.beginMove()
        state.placeRequested = true
        state.cancelMove()
        placement.cancel()
        assertSame(original, placement.committed)
        assertEquals(transform, state.transform)
        assertFalse(state.moving)
        assertFalse(state.placeRequested)
        assertEquals(ReaderPanel.NONE, state.panel)
        assertFalse(reader.player().isPlaying)
    }

    @Test fun trackingRecoveryDoesNotRestartOrDiscardCompletion() = withReader { reader, state ->
        val completed = reader.player()
        state.trackingReady = false
        state.needsReposition = true
        reader.call("interruptPlayback")
        shadowOf(completed).onCompletionListener.onCompletion(completed)
        state.trackingReady = true
        state.needsReposition = false
        reader.call("maybeAutoStart")
        assertEquals(ReaderPlaybackState.COMPLETED, state.playback)
        assertFalse(reader.player().isPlaying)
    }

    @Test fun openingSheetConsumesPendingAutomaticStartEvenWhilePreparing() = withReader { reader, state ->
        reader.call("pausePlayback")
        state.preparingNarration = true
        field("automaticStartPending").setBoolean(reader, true)
        field("placedAt").setLong(reader, -1000)
        state.openPanel(ReaderPanel.MORE) { reader.call("interruptPlayback") }
        assertEquals(ReaderPlaybackState.PREPARING, state.playback)
        state.dismissPanel()
        state.preparingNarration = false
        reader.call("maybeAutoStart")
        assertFalse(reader.player().isPlaying)
    }

    @Test fun voiceCancellationFromPausedStateNeverRestarts() = withReader { reader, state ->
        state.openPanel(ReaderPanel.VOICE) { reader.call("interruptPlayback") }
        state.listening = true
        reader.call("interruptPlayback")
        state.dismissPanel()
        assertEquals(ReaderPlaybackState.PAUSED, state.playback)
        assertFalse(reader.player().isPlaying)
        assertFalse(field("pendingVoice").getBoolean(reader))
    }

    @Test fun pageNavigationClearsCompletionButDoesNotPlayFromSheet() = withReader { reader, state ->
        val path = "/cache/ui-next.mp3"
        ShadowMediaPlayer.addMediaInfo(DataSource.toDataSource(path), ShadowMediaPlayer.MediaInfo(10_000, 0))
        field("pages").set(reader, listOf(StoryReaderPage("p1", 1, listOf("/cache/ui-clip0.mp3")),
            StoryReaderPage("p2", 2, listOf(path))))
        field("storyMode").setBoolean(reader, true)
        state.openPanel(ReaderPanel.MORE) { reader.call("interruptPlayback") }
        state.readingComplete = true
        CharacterReaderActivity::class.java.getDeclaredMethod("goToPage", Int::class.javaPrimitiveType)
            .apply { isAccessible = true }.invoke(reader, 1)
        assertFalse(state.readingComplete)
        assertEquals(ReaderPanel.MORE, state.panel)
        assertFalse(reader.player().isPlaying)
        assertFalse(state.canGoNext)
        assertTrue(state.canGoPrevious)
    }

    @Test fun completionActionsDistinguishScannedLibraryAndFinalPage() {
        assertEquals(ReaderCompletionAction.SCAN, readerCompletionAction(canScan = true, canGoNext = false))
        assertEquals(ReaderCompletionAction.NEXT, readerCompletionAction(canScan = false, canGoNext = true))
        assertEquals(ReaderCompletionAction.EXIT, readerCompletionAction(canScan = false, canGoNext = false))
    }
}
