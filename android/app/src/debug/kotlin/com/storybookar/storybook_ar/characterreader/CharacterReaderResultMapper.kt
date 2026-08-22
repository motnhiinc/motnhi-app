package com.storybookar.storybook_ar.characterreader

import android.app.Activity

object CharacterReaderResultMapper {
    const val EXTRA_TERMINAL_CODE = "storybook_ar.character_reader.TERMINAL_CODE"
    const val COMPLETED = "completed"

    private val failureCodes = setOf(
        "cancelled",
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
        if (resultCode == Activity.RESULT_CANCELED) return "cancelled"
        return "ar_failed"
    }
}
