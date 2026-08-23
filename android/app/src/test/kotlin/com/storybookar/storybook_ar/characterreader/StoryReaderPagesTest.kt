package com.storybookar.storybook_ar.characterreader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StoryReaderPagesTest {
    private fun page(id: String, pageNumber: Int = 1, vararg paths: String) =
        mapOf(
            "pageId" to id,
            "pageNumber" to pageNumber,
            "audioFilePaths" to paths.toList(),
        )

    @Test
    fun parsesAWellFormedRequest() {
        val parsed = StoryReaderPages.parse(listOf(page("p1", 1, "a.mp3", "b.mp3")))

        assertEquals(1, parsed!!.size)
        assertEquals("p1", parsed[0].pageId)
        assertEquals(1, parsed[0].pageNumber)
        assertEquals(listOf("a.mp3", "b.mp3"), parsed[0].audioFilePaths)
    }

    @Test
    fun parsesSeveralPagesInOrder() {
        val parsed = StoryReaderPages.parse(
            listOf(page("p1", 1, "a.mp3"), page("p2", 2, "b.mp3")),
        )

        assertEquals(listOf("p1", "p2"), parsed!!.map { it.pageId })
    }

    @Test
    fun rejectsAPageWithNoAudioPaths() {
        assertNull(StoryReaderPages.parse(listOf(page("p1"))))
    }

    @Test
    fun rejectsAnEmptyPageList() {
        assertNull(StoryReaderPages.parse(emptyList<Any>()))
    }

    @Test
    fun rejectsANonList() {
        assertNull(StoryReaderPages.parse("nope"))
        assertNull(StoryReaderPages.parse(null))
    }

    @Test
    fun rejectsAPageMissingItsId() {
        val malformed = mapOf(
            "pageNumber" to 1,
            "audioFilePaths" to listOf("a.mp3"),
        )

        assertNull(StoryReaderPages.parse(listOf(malformed)))
    }

    @Test
    fun rejectsAPageMissingItsNumber() {
        val malformed = mapOf(
            "pageId" to "p1",
            "audioFilePaths" to listOf("a.mp3"),
        )

        assertNull(StoryReaderPages.parse(listOf(malformed)))
    }

    @Test
    fun rejectsAPageWhoseSecondEntryIsMalformed() {
        val parsed = StoryReaderPages.parse(
            listOf(page("p1", 1, "a.mp3"), mapOf("pageId" to "p2")),
        )

        assertNull(parsed)
    }

    @Test
    fun clampsTheInitialIndexIntoRange() {
        assertEquals(0, StoryReaderPages.clampIndex(-3, 2))
        assertEquals(1, StoryReaderPages.clampIndex(9, 2))
        assertEquals(1, StoryReaderPages.clampIndex(1, 2))
        assertEquals(0, StoryReaderPages.clampIndex(0, 1))
    }
}
