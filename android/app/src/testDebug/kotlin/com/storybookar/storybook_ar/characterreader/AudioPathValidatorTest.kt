package com.storybookar.storybook_ar.characterreader

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class AudioPathValidatorTest {
    private lateinit var root: File
    private lateinit var cacheDir: File

    @Before
    fun setUp() {
        root = Files.createTempDirectory("reader_audio_test_").toFile()
        cacheDir = File(root, "cache").apply { mkdirs() }
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    @Test
    fun acceptsExactNarrationFileBelowResolvedCacheDirectory() {
        val nested = File(cacheDir, "nested").apply { mkdirs() }
        val audio = File(nested, AudioPathValidator.EXPECTED_FILENAME).apply {
            writeBytes(byteArrayOf(1))
        }

        assertEquals(
            audio.canonicalFile,
            AudioPathValidator(cacheDir).validate(audio.path),
        )
    }

    @Test
    fun rejectsWrongFilenameRelativePathAndSiblingPrefixDirectory() {
        val validator = AudioPathValidator(cacheDir)
        val wrongName = File(cacheDir, "narration.mp3").apply { writeBytes(byteArrayOf(1)) }
        val sibling = File(root, "cache-escape").apply { mkdirs() }
        val siblingAudio = File(sibling, AudioPathValidator.EXPECTED_FILENAME).apply {
            writeBytes(byteArrayOf(1))
        }

        assertNull(validator.validate(wrongName.path))
        assertNull(validator.validate(AudioPathValidator.EXPECTED_FILENAME))
        assertNull(validator.validate(siblingAudio.path))
    }

    @Test
    fun rejectsSymlinkThatEscapesCacheDirectory() {
        val outside = File(root, "outside").apply { mkdirs() }
        val outsideAudio = File(outside, AudioPathValidator.EXPECTED_FILENAME).apply {
            writeBytes(byteArrayOf(1))
        }
        val link = File(cacheDir, AudioPathValidator.EXPECTED_FILENAME)
        Files.createSymbolicLink(link.toPath(), outsideAudio.toPath())

        assertNull(AudioPathValidator(cacheDir).validate(link.path))
    }

    @Test
    fun rejectsDirectoryWithExpectedFilename() {
        val directory = File(cacheDir, AudioPathValidator.EXPECTED_FILENAME).apply {
            mkdirs()
        }

        assertNull(AudioPathValidator(cacheDir).validate(directory.path))
    }
}
