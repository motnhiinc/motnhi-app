package com.motnhi.app.characterreader

/** Main-thread, process-local handoff. No audio/text is persisted across sessions.
 * The bridge can receive narration before the activity has finished launching. */
internal class PreparingReaderSession(val id: String) {
    var pages: List<StoryReaderPage>? = null
        private set
    var closed = false
        private set
    var onChanged: (() -> Unit)? = null

    fun attach(value: List<StoryReaderPage>): Boolean {
        if (closed || pages != null || value.isEmpty()) return false
        pages = value
        onChanged?.invoke()
        return true
    }

    fun close() {
        closed = true
        onChanged?.invoke()
    }
}

internal object PreparingReaderSessions {
    var active: PreparingReaderSession? = null
}
