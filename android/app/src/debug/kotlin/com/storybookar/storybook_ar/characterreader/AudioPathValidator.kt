package com.storybookar.storybook_ar.characterreader

import java.io.File

class AudioPathValidator(
    private val cacheDir: File,
) {
    fun validate(path: String?): File? {
        if (path.isNullOrBlank()) return null

        val requested = File(path)
        if (!requested.isAbsolute) return null
        if (requested.name != EXPECTED_FILENAME) return null

        val resolvedCache = runCatching { cacheDir.canonicalFile }.getOrNull() ?: return null
        val resolvedAudio = runCatching { requested.canonicalFile }.getOrNull() ?: return null
        if (resolvedAudio.name != EXPECTED_FILENAME) return null
        if (!resolvedAudio.isFile || !resolvedAudio.canRead()) return null

        var cursor: File? = resolvedAudio.parentFile
        while (cursor != null) {
            if (cursor == resolvedCache) return resolvedAudio
            cursor = cursor.parentFile
        }
        return null
    }

    companion object {
        const val EXPECTED_FILENAME = "scan_any_page_narration.mp3"
    }
}
