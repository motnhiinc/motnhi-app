package com.motnhi.app.characterreader

/**
 * One page of the story reader playlist: its clips, in narration order.
 *
 * A page holds a list rather than a single clip because curated pages carry
 * several narration segments, and they cannot be joined in general — a page can
 * mix an `.mp3` from the backend with a `.caf` written by iOS speech synthesis.
 */
data class StoryReaderPage(
    val pageId: String,
    val pageNumber: Int,
    val audioFilePaths: List<String>,
)

object StoryReaderPages {
    /**
     * Returns null when the request is malformed in any way; the bridge maps that to
     * `audio_missing`. Strict by design: a page that silently lost its clips would
     * leave the character standing mute on the table.
     */
    fun parse(raw: Any?): List<StoryReaderPage>? {
        val list = raw as? List<*> ?: return null
        if (list.isEmpty()) return null

        return list.map { entry ->
            val map = entry as? Map<*, *> ?: return null
            val pageId = map["pageId"] as? String ?: return null
            val pageNumber = (map["pageNumber"] as? Number)?.toInt() ?: return null
            val paths = (map["audioFilePaths"] as? List<*>)
                ?.mapNotNull { it as? String }
                ?: return null
            if (paths.isEmpty()) return null
            StoryReaderPage(pageId, pageNumber, paths)
        }
    }

    fun clampIndex(requested: Int, size: Int): Int = requested.coerceIn(0, size - 1)
}
