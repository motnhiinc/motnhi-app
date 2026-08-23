package com.storybookar.storybook_ar.characterreader

import org.json.JSONArray
import org.json.JSONObject

/**
 * Carries the playlist across the Intent boundary.
 *
 * JSON rather than parallel array extras: the playlist is a list of lists, and flattening it into
 * primitive extras invites exactly the off-by-one this feature cannot afford. Kept out of
 * [CharacterReaderBridge] because `org.json` is an Android stub in JVM unit tests — the bridge
 * hands [ReaderHost] typed pages and never sees the wire format.
 */
object StoryReaderPageCodec {
    private const val KEY_PAGE_ID = "pageId"
    private const val KEY_PAGE_NUMBER = "pageNumber"
    private const val KEY_AUDIO_FILE_PATHS = "audioFilePaths"

    fun encode(pages: List<StoryReaderPage>): String {
        val array = JSONArray()
        for (page in pages) {
            val paths = JSONArray()
            for (path in page.audioFilePaths) paths.put(path)
            array.put(
                JSONObject()
                    .put(KEY_PAGE_ID, page.pageId)
                    .put(KEY_PAGE_NUMBER, page.pageNumber)
                    .put(KEY_AUDIO_FILE_PATHS, paths),
            )
        }
        return array.toString()
    }

    /** Returns an empty list when the payload is missing or malformed; the activity treats that as terminal. */
    fun decode(json: String?): List<StoryReaderPage> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val array = JSONArray(json)
            buildList {
                for (i in 0 until array.length()) {
                    val entry = array.optJSONObject(i) ?: return emptyList()
                    val pageId = entry.optString(KEY_PAGE_ID, "")
                    if (pageId.isEmpty()) return emptyList()
                    val paths = entry.optJSONArray(KEY_AUDIO_FILE_PATHS) ?: return emptyList()
                    val clips = buildList {
                        for (j in 0 until paths.length()) {
                            val path = paths.optString(j, "")
                            if (path.isEmpty()) return emptyList()
                            add(path)
                        }
                    }
                    if (clips.isEmpty()) return emptyList()
                    add(
                        StoryReaderPage(
                            pageId = pageId,
                            pageNumber = entry.optInt(KEY_PAGE_NUMBER, i + 1),
                            audioFilePaths = clips,
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
