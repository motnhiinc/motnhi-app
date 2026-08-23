package com.storybookar.storybook_ar.characterreader

import android.app.Activity
import android.content.Intent
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner

/** The bridge's view of the host activity: can it show something, and can it start the reader. */
interface ReaderHost {
    fun isPresentable(): Boolean

    /** Returns false if the reader could not be started, which the bridge maps to `ar_failed`. */
    fun launchReader(audioPath: String): Boolean

    /**
     * Starts the reader on a whole story. Serialisation lives in the implementation so the
     * bridge stays free of Android types and reachable from a JVM unit test.
     */
    fun launchStoryReader(pages: List<StoryReaderPage>, initialPageIndex: Int): Boolean
}

class ActivityReaderHost(
    private val activity: Activity,
    private val readerRequestCode: Int,
) : ReaderHost {
    override fun isPresentable(): Boolean {
        if (activity.isFinishing || activity.isDestroyed) return false
        val lifecycleOwner = activity as? LifecycleOwner ?: return true
        return lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
    }

    override fun launchReader(audioPath: String): Boolean =
        try {
            val intent = Intent(activity, CharacterReaderActivity::class.java)
                .putExtra(CharacterReaderActivity.EXTRA_AUDIO_FILE_PATH, audioPath)
            activity.startActivityForResult(intent, readerRequestCode)
            true
        } catch (_: RuntimeException) {
            false
        }

    override fun launchStoryReader(
        pages: List<StoryReaderPage>,
        initialPageIndex: Int,
    ): Boolean =
        try {
            val intent = Intent(activity, CharacterReaderActivity::class.java)
                .putExtra(
                    CharacterReaderActivity.EXTRA_PAGES_JSON,
                    StoryReaderPageCodec.encode(pages),
                )
                .putExtra(CharacterReaderActivity.EXTRA_INITIAL_PAGE_INDEX, initialPageIndex)
            activity.startActivityForResult(intent, readerRequestCode)
            true
        } catch (_: RuntimeException) {
            false
        }
}
