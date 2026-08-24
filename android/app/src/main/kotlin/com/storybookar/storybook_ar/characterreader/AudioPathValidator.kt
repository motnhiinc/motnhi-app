package com.storybookar.storybook_ar.characterreader

import java.io.File

class AudioPathValidator(
    private val cacheDir: File,
) {
    fun validate(path: String?): File? {
        if (path.isNullOrBlank()) return null

        val requested = File(path)
        if (!requested.isAbsolute) return null
        if (!isAllowedName(requested.name)) return null

        val resolvedCache = runCatching { cacheDir.canonicalFile }.getOrNull() ?: return null
        val resolvedAudio = runCatching { requested.canonicalFile }.getOrNull() ?: return null
        // Checked again after symlink resolution: the pre-resolution name is caller-supplied,
        // and a symlink with an allowed name can point at something else entirely.
        if (!isAllowedName(resolvedAudio.name)) return null
        if (!resolvedAudio.isFile || !resolvedAudio.canRead()) return null

        var cursor: File? = resolvedAudio.parentFile
        while (cursor != null) {
            if (cursor == resolvedCache) return resolvedAudio
            cursor = cursor.parentFile
        }
        return null
    }

    companion object {
        /** The single-clip name the scan-any-page flow has always used. */
        const val EXPECTED_FILENAME = "scan_any_page_narration.mp3"

        /**
         * Per-segment clips prepared for the story reader:
         * `ar_<sanitizedStoryId>_p<pageNumber>_s<sortOrder>.<ext>`.
         *
         * Anchored deliberately: an unanchored pattern would also accept
         * `evil_ar_abc_p1_s0.mp3`. The extension set covers every container the Dart
         * side can produce - mp3 from the backend, wav from Android speech synthesis,
         * caf from iOS (which cannot encode mp3).
         */
        private val STORY_SEGMENT_FILENAME =
            Regex("""^ar_[A-Za-z0-9]{1,32}_p\d{1,4}_s\d{1,4}\.(mp3|wav|caf|m4a)$""")

        fun isAllowedName(name: String): Boolean =
            name == EXPECTED_FILENAME || STORY_SEGMENT_FILENAME.matches(name)
    }
}
