package com.storybookar.storybook_ar.characterreader

import android.app.Activity

object CharacterReaderResultMapper {
    const val EXTRA_TERMINAL_CODE = "storybook_ar.character_reader.TERMINAL_CODE"

    /** Story-reader only: the page the child was on when the reader closed. */
    const val EXTRA_LAST_PAGE_ID = "storybook_ar.character_reader.LAST_PAGE_ID"

    /** Story-reader only: every page that actually began playing, for session events. */
    const val EXTRA_PAGES_READ = "storybook_ar.character_reader.PAGES_READ"

    const val COMPLETED = "completed"
    const val CANCELLED = "cancelled"

    private val failureCodes = setOf(
        CANCELLED,
        "ar_unsupported",
        "ar_failed",
        "audio_missing",
        "model_missing",
        "model_load_failed",
        "audio_failed",
    )

    /**
     * Takes the already-extracted terminal-code extra rather than the [android.content.Intent]
     * itself, so this stays a pure function that JVM unit tests can exercise without a mocked
     * Android framework. Mirrors [ScannerFailureMapper.activityResultFailureCode], which takes
     * primitives for the same reason. Intent unwrapping belongs to the caller.
     */
    fun terminalCode(resultCode: Int, terminalCodeExtra: String?): String {
        val code = terminalCodeExtra
        if (code != null && (code == COMPLETED || code in failureCodes)) return code
        if (resultCode == Activity.RESULT_CANCELED) return CANCELLED
        return "ar_failed"
    }
}
