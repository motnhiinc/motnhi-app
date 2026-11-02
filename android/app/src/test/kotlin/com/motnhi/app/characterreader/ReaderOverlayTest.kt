package com.motnhi.app.characterreader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import com.motnhi.app.R
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import android.graphics.Bitmap
import android.graphics.Canvas
import java.io.File

/** Real native Compose semantics/layout, intentionally independent of Flutter and the AR renderer. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w390dp-h844dp")
class ReaderOverlayTest {
    @get:Rule val compose = createComposeRule()

    private fun show(state: ReaderUiState, fontScale: Float = 1f, scan: Boolean = false) {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                Box(Modifier.fillMaxSize()) {
                    ReaderOverlay(state, {}, {}, {}, {}, {
                        state.speaking = false
                        state.readLabel = R.string.reader_resume
                        state.listening = false
                    }, {}, {}, if (scan) ({}) else null)
                }
            }
        }
    }

    private fun placed() = ReaderUiState().apply { controlsVisible = true; trackingReady = true }

    @Test fun normalDockContainsPlaybackAndTalkWithSecondaryControlsHidden() {
        val state = placed().apply { speaking = true; readLabel = R.string.reader_pause }
        show(state)
        compose.onNodeWithText("Pause").assertIsDisplayed().assertHasClickAction()
        compose.onNodeWithText("Talk").assertIsDisplayed().assertHasClickAction()
        compose.onNodeWithText("Move buddy").assertDoesNotExist()
        compose.onNodeWithContentDescription("More controls").performClick()
        compose.onNodeWithText("Story controls").assertIsDisplayed()
        compose.onNodeWithText("Done").performClick()
        compose.onNodeWithText("Resume").assertIsDisplayed()
    }

    @Test fun listeningReplacesRatherThanStacksPlaybackControls() {
        show(placed().apply { panel = ReaderPanel.VOICE; listening = true })
        compose.onNodeWithText("What shall we do?").assertIsDisplayed()
        compose.onNodeWithText("Cancel listening").assertIsDisplayed()
        compose.onNodeWithText("Read").assertDoesNotExist()
        compose.onNodeWithText("Talk").assertDoesNotExist()
    }

    @Test fun scanCompletionHasScanAndReplayButNoInventedPageTotal() {
        show(placed().apply { readingComplete = true }, scan = true)
        compose.onNodeWithText("Scan next page").assertIsDisplayed()
        compose.onNodeWithText("Read this page again").assertIsDisplayed()
        compose.onAllNodesWithText("of", substring = true).assertCountEquals(0)
    }

    @Test fun finalLibraryCompletionOffersReplayAndExit() {
        show(placed().apply { readingComplete = true; pageLabel = "Page 6 of 6" })
        compose.onNodeWithText("Read again").assertIsDisplayed()
        compose.onNodeWithText("Exit reader").assertIsDisplayed()
        compose.onNodeWithText("Scan next page").assertDoesNotExist()
    }

    @Test fun preparationDisablesPlaybackAndTalkButKeepsContext() {
        show(placed().apply { preparingNarration = true })
        compose.onNodeWithText("Getting your story ready…").assertIsDisplayed()
        compose.onNodeWithText("Read").assertIsNotEnabled()
        compose.onNodeWithText("Talk").assertIsNotEnabled()
    }

    @Test fun voiceErrorsStayInDockWithRetryAndDismissal() {
        show(placed().apply { panel = ReaderPanel.VOICE; voiceStatus = R.string.reader_voice_permission })
        compose.onNodeWithText("Allow microphone access to talk to your friend. Reading controls still work.").assertIsDisplayed()
        compose.onNodeWithText("Try voice again").assertIsDisplayed()
        compose.onNodeWithText("Done").performClick()
        compose.onNodeWithText("Resume").assertIsDisplayed()
    }

    @Test fun enlargedTextKeepsBothPrimaryActionsReachable() {
        show(placed(), fontScale = 2f)
        compose.onNodeWithText("Read").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Talk").performScrollTo().assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "vi-w320dp-h480dp")
    fun vietnameseSheetScrollsAtLargeTextAndSmallHeight() {
        show(placed().apply { panel = ReaderPanel.MORE }, fontScale = 2f)
        compose.onNodeWithText("Nghe không cần AR").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Xong").performScrollTo().assertIsDisplayed().performClick()
        compose.onNodeWithText("Đọc").performScrollTo().assertIsDisplayed()
    }

    @Test
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun captureCoreScreensForVisualReview() {
        val state = placed().apply { speaking = true; readLabel = R.string.reader_pause; pageLabel = "Page 2 of 6"; canGoNext = true }
        show(state, scan = true)
        val directory = File("build/reader-ui-review").apply { mkdirs() }
        fun capture(name: String) {
            compose.waitForIdle()
            val view = (compose.onAllNodes(isRoot()).onLast().fetchSemanticsNode().root as ViewRootForTest).view
            val image = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            compose.runOnIdle { view.draw(Canvas(image)) }
            File(directory, "$name.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        capture("reading")
        compose.onNodeWithContentDescription("More controls").performClick()
        capture("controls")
        compose.onNodeWithText("Size & direction").performClick()
        capture("adjustments")
        compose.onNodeWithText("Done").performClick()
        compose.runOnIdle { state.panel = ReaderPanel.VOICE; state.listening = true }
        capture("listening")
        compose.runOnIdle { state.panel = ReaderPanel.NONE; state.listening = false; state.readingComplete = true; state.pageLabel = "" }
        capture("finished")
        compose.runOnIdle { state.needsReposition = true; state.trackingReady = false; state.guidance = R.string.reader_recover }
        capture("recovery")
    }
}
