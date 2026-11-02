package com.motnhi.app.characterreader

import org.junit.Assert.*
import org.junit.Test

class PreparingReaderSessionTest {
    @Test fun audioCanArriveBeforeTheActivitySubscribesButOnlyOnce() {
        val session = PreparingReaderSession("scan")
        val pages = listOf(StoryReaderPage("p1", 1, listOf("clip.mp3")))
        assertTrue(session.attach(pages))
        assertSame(pages, session.pages)
        assertFalse(session.attach(pages))
    }
    @Test fun closedSessionsNeverAcceptDelayedAudio() {
        val session = PreparingReaderSession("scan")
        var changes = 0
        session.onChanged = { changes++ }
        session.close()
        assertTrue(session.closed)
        assertEquals(1, changes)
        assertFalse(session.attach(listOf(StoryReaderPage("p1", 1, listOf("clip.mp3")))))
        assertNull(session.pages)
    }
}
