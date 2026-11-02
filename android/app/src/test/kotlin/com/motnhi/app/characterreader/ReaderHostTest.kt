package com.motnhi.app.characterreader

import android.app.Activity
import android.content.Intent
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ReaderHostTest {
    private fun verifyBothLaunchPaths(optIn: Boolean?) {
        val launch = Intent().apply {
            optIn?.let { putExtra(CharacterReaderActivity.EXTRA_EXPERIMENTAL_DEPTH, it) }
        }
        val controller = Robolectric.buildActivity(Activity::class.java, launch).setup()
        try {
            val activity = controller.get()
            val host = ActivityReaderHost(activity, 42)
            fun nextReaderIntent(): Intent {
                val started = shadowOf(activity).nextStartedActivityForResult
                assertNotNull(started)
                assertEquals(42, started.requestCode)
                assertEquals(CharacterReaderActivity::class.java.name, started.intent.component?.className)
                assertEquals(com.motnhi.app.BuildConfig.DEBUG && optIn == true,
                    started.intent.getBooleanExtra(CharacterReaderActivity.EXTRA_EXPERIMENTAL_DEPTH, false))
                return started.intent
            }
            assertTrue(host.launchReader("/cache/narration.mp3"))
            assertEquals("/cache/narration.mp3", nextReaderIntent().getStringExtra(
                CharacterReaderActivity.EXTRA_AUDIO_FILE_PATH))

            val pages = listOf(StoryReaderPage("page", 1, listOf("/cache/story.mp3")))
            assertTrue(host.launchStoryReader(pages, 0, "cute_doll_v01.glb"))
            val story = nextReaderIntent()
            assertEquals(StoryReaderPageCodec.encode(pages), story.getStringExtra(
                CharacterReaderActivity.EXTRA_PAGES_JSON))
            assertEquals(0, story.getIntExtra(CharacterReaderActivity.EXTRA_INITIAL_PAGE_INDEX, -1))
            assertEquals("cute_doll_v01.glb", story.getStringExtra(
                CharacterReaderActivity.EXTRA_MODEL_ASSET_FILE_NAME))
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test fun absentDebugOptInDefaultsOffForBothPaths() = verifyBothLaunchPaths(null)
    @Test fun explicitFalseClearsDebugOptInForBothPaths() = verifyBothLaunchPaths(false)
    @Test fun debugOptInIsForwardedForBothPaths() = verifyBothLaunchPaths(true)
}
