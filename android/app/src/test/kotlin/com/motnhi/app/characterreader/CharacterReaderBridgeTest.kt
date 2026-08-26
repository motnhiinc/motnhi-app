package com.motnhi.app.characterreader

import android.app.Activity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Covers the bridge's *use* of [ArCoreInstallPolicy], not the policy itself. The policy has its own
 * tests; what these pin is the wiring that was broken before: which flag the install is requested
 * with, that the attempt counter actually advances, and that a resume only re-drives an install
 * that is genuinely outstanding.
 */
class CharacterReaderBridgeTest {
    private lateinit var root: File
    private lateinit var cacheDir: File
    private lateinit var audioPath: String

    /** The validator hands the bridge a canonicalized file, so that is what the reader launches. */
    private lateinit var launchedPath: String

    private lateinit var arCore: FakeArCoreGateway
    private lateinit var host: FakeReaderHost
    private lateinit var scheduler: InlineScheduler
    private lateinit var result: RecordingResult

    @Before
    fun setUp() {
        root = Files.createTempDirectory("reader_bridge_test_").toFile()
        cacheDir = File(root, "cache").apply { mkdirs() }
        val audio = File(cacheDir, AudioPathValidator.EXPECTED_FILENAME)
            .apply { writeBytes(byteArrayOf(1)) }
        audioPath = audio.path
        launchedPath = audio.canonicalPath

        arCore = FakeArCoreGateway()
        host = FakeReaderHost()
        scheduler = InlineScheduler()
        result = RecordingResult()
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    private fun bridge() = CharacterReaderBridge(
        arCore = arCore,
        host = host,
        scheduler = scheduler,
        audioPathValidator = AudioPathValidator(cacheDir),
        readerRequestCode = READER_REQUEST_CODE,
    )

    private fun CharacterReaderBridge.open() =
        handle(MethodCall("openCharacterReader", mapOf("audioFilePath" to audioPath)), result)

    @Test
    fun promptsOnFirstInstallRequestAndConfirmsWithoutPromptingOnResume() {
        arCore.availability = ArCoreAvailabilityDecision.NeedsInstall
        arCore.outcomes = mutableListOf(
            ArCoreInstallOutcome.Requested,
            ArCoreInstallOutcome.Installed,
        )
        val bridge = bridge()

        bridge.open()
        assertEquals(listOf(true), arCore.installCalls)

        arCore.availability = ArCoreAvailabilityDecision.Supported
        bridge.onHostResume()

        // Second request must not re-prompt, or the user sees the install dialog twice.
        assertEquals(listOf(true, false), arCore.installCalls)
        assertEquals(listOf(launchedPath), host.launches)
        assertEquals(0, result.replies)
    }

    @Test
    fun stopsRequestingInstallAtTheBoundAndFailsInsteadOfLeavingTheCallPending() {
        arCore.availability = ArCoreAvailabilityDecision.NeedsInstall
        arCore.defaultOutcome = ArCoreInstallOutcome.Requested
        val bridge = bridge()

        bridge.open()
        repeat(5) { bridge.onHostResume() }

        assertEquals(ArCoreInstallPolicy.MAX_ATTEMPTS, arCore.installCalls.size)
        assertEquals(1, result.replies)
        assertEquals("ar_failed", result.errorCode)
        assertTrue(host.launches.isEmpty())
    }

    @Test
    fun declinedInstallRepliesCancelledSoDartTreatsItAsAUserCancel() {
        arCore.availability = ArCoreAvailabilityDecision.NeedsInstall
        arCore.outcomes = mutableListOf(
            ArCoreInstallOutcome.Requested,
            ArCoreInstallOutcome.Declined,
        )
        val bridge = bridge()

        bridge.open()
        bridge.onHostResume()

        assertEquals(1, result.replies)
        assertEquals("cancelled", result.errorCode)
    }

    @Test
    fun resumeAfterTheReaderFinishesDoesNotRequestInstallAgain() {
        arCore.availability = ArCoreAvailabilityDecision.Supported
        val bridge = bridge()

        bridge.open()
        assertEquals(listOf(launchedPath), host.launches)

        bridge.onActivityResult(READER_REQUEST_CODE, Activity.RESULT_CANCELED, null)
        bridge.onHostResume()

        assertTrue(arCore.installCalls.isEmpty())
        assertEquals(1, result.replies)
        assertEquals("cancelled", result.errorCode)
    }

    @Test
    fun repliesOnlyOnceWhenAnActivityResultArrivesTwice() {
        arCore.availability = ArCoreAvailabilityDecision.Supported
        val bridge = bridge()

        bridge.open()
        bridge.onActivityResult(READER_REQUEST_CODE, Activity.RESULT_CANCELED, null)
        bridge.onActivityResult(READER_REQUEST_CODE, Activity.RESULT_CANCELED, null)

        assertEquals(1, result.replies)
    }

    @Test
    fun releasesTheInProgressGateAfterAFailureSoALaterCallIsAccepted() {
        arCore.availability = ArCoreAvailabilityDecision.Unsupported
        val bridge = bridge()

        bridge.open()
        assertEquals("ar_unsupported", result.errorCode)

        val second = RecordingResult()
        arCore.availability = ArCoreAvailabilityDecision.Supported
        bridge.handle(
            MethodCall("openCharacterReader", mapOf("audioFilePath" to audioPath)),
            second,
        )

        assertEquals(0, second.replies)
        assertNull(second.errorCode)
        assertEquals(listOf(launchedPath), host.launches)
    }

    @Test
    fun failsTheCallWhenTheReaderCannotBeStarted() {
        // The refactor turned `catch (RuntimeException) -> finishError` into a boolean contract
        // split across two files. If the false branch stops replying, the Dart call hangs.
        arCore.availability = ArCoreAvailabilityDecision.Supported
        host.launchSucceeds = false
        val bridge = bridge()

        bridge.open()

        assertEquals(listOf(launchedPath), host.launches)
        assertEquals(1, result.replies)
        assertEquals("ar_failed", result.errorCode)
    }

    @Test
    fun rejectsTheCallWhenTheHostCannotPresentAndStillReleasesTheGate() {
        host.presentable = false
        val bridge = bridge()

        bridge.open()

        assertTrue(host.launches.isEmpty())
        assertEquals(1, result.replies)
        assertEquals("ar_failed", result.errorCode)

        val second = RecordingResult()
        host.presentable = true
        arCore.availability = ArCoreAvailabilityDecision.Supported
        bridge.handle(
            MethodCall("openCharacterReader", mapOf("audioFilePath" to audioPath)),
            second,
        )

        assertEquals(0, second.replies)
        assertEquals(listOf(launchedPath), host.launches)
    }

    @Test
    fun failsInsteadOfLaunchingIntoTheBackgroundWhenAPollResolvesLate() {
        // startActivityForResult is silently dropped from the background on Android 10+ without
        // throwing, so a late poll that launched anyway would hang the Dart call.
        arCore.availability = ArCoreAvailabilityDecision.Retry
        val bridge = bridge()

        bridge.open()
        host.presentable = false
        arCore.availability = ArCoreAvailabilityDecision.Supported
        scheduler.runNextDelayed()

        assertTrue(host.launches.isEmpty())
        assertEquals(1, result.replies)
        assertEquals("ar_failed", result.errorCode)
    }

    @Test
    fun boundsTransientAvailabilityPollingInsteadOfPollingForever() {
        arCore.availability = ArCoreAvailabilityDecision.Retry
        val bridge = bridge()

        bridge.open()
        var polls = 0
        while (scheduler.delayed.isNotEmpty() && polls < 100) {
            polls++
            scheduler.runNextDelayed()
        }

        assertEquals(1, result.replies)
        assertEquals("ar_failed", result.errorCode)
        assertTrue(polls in 1..20)
        assertEquals(200L, scheduler.lastDelayMs)
    }

    // ---- story reader ----

    /** Two clips on one page, which is the shape curated multi-segment pages produce. */
    private fun storyArguments(
        vararg clips: String,
        initialPageIndex: Int = 0,
        modelAssetBaseName: String? = null,
    ): Map<String, Any> = buildMap {
        put(
            "pages",
            listOf(
                mapOf(
                    "pageId" to "p1",
                    "pageNumber" to 1,
                    "audioFilePaths" to clips.toList(),
                ),
            ),
        )
        put("initialPageIndex", initialPageIndex)
        if (modelAssetBaseName != null) put("modelAssetBaseName", modelAssetBaseName)
    }

    private fun storyClip(name: String): String =
        File(cacheDir, name).apply { writeBytes(byteArrayOf(1)) }.path

    @Test
    fun openStoryReaderLaunchesWithEveryValidatedClip() {
        val first = storyClip("ar_story1_p1_s0.mp3")
        val second = storyClip("ar_story1_p1_s1.mp3")

        bridge().handle(MethodCall("openStoryReader", storyArguments(first, second)), result)

        assertEquals(1, host.storyLaunches.size)
        val (pages, initialIndex, modelFile) = host.storyLaunches.single()
        assertEquals(1, pages.size)
        assertEquals("p1", pages.single().pageId)
        assertEquals(
            listOf(File(first).canonicalPath, File(second).canonicalPath),
            pages.single().audioFilePaths,
        )
        assertEquals(0, initialIndex)
        // No model name on the arguments: the reader still gets a usable default.
        assertEquals(CharacterReaderActivity.MODEL_FILENAME, modelFile)
        assertEquals(0, result.replies)
    }

    @Test
    fun openStoryReaderRejectsAPlaylistContainingOneBadPath() {
        val good = storyClip("ar_story1_p1_s0.mp3")
        val outside = File(root, "ar_story1_p1_s1.mp3").apply { writeBytes(byteArrayOf(1)) }

        bridge().handle(
            MethodCall("openStoryReader", storyArguments(good, outside.path)),
            result,
        )

        assertTrue(host.storyLaunches.isEmpty())
        assertEquals(1, result.replies)
        assertEquals("audio_missing", result.errorCode)
    }

    @Test
    fun openStoryReaderClampsAnOutOfRangeInitialIndex() {
        val clip = storyClip("ar_story1_p1_s0.mp3")

        bridge().handle(
            MethodCall("openStoryReader", storyArguments(clip, initialPageIndex = 9)),
            result,
        )

        assertEquals(0, host.storyLaunches.single().second)
    }

    @Test
    fun openStoryReaderForwardsTheSelectedDollVariantToTheHost() {
        val clip = storyClip("ar_story1_p1_s0.mp3")

        bridge().handle(
            MethodCall(
                "openStoryReader",
                storyArguments(clip, modelAssetBaseName = "cute_doll_v01"),
            ),
            result,
        )

        assertEquals("cute_doll_v01.glb", host.storyLaunches.single().third)
    }

    @Test
    fun openStoryReaderFallsBackToTheFoxWhenTheBaseNameIsAPathTrick() {
        val clip = storyClip("ar_story1_p1_s0.mp3")

        bridge().handle(
            MethodCall(
                "openStoryReader",
                storyArguments(clip, modelAssetBaseName = "../evil"),
            ),
            result,
        )

        assertEquals(CharacterReaderActivity.MODEL_FILENAME, host.storyLaunches.single().third)
        assertEquals(0, result.replies)
    }

    @Test
    fun openStoryReaderDefaultsTheModelWhenTheKeyIsMissing() {
        val clip = storyClip("ar_story1_p1_s0.mp3")

        bridge().handle(MethodCall("openStoryReader", storyArguments(clip)), result)

        assertEquals(CharacterReaderActivity.MODEL_FILENAME, host.storyLaunches.single().third)
    }

    @Test
    fun openStoryReaderFallsBackToTheFoxWhenTheBaseNameHasInvalidCharacters() {
        val clip = storyClip("ar_story1_p1_s0.mp3")

        bridge().handle(
            MethodCall(
                "openStoryReader",
                storyArguments(clip, modelAssetBaseName = "CuteDoll"),
            ),
            result,
        )

        assertEquals(CharacterReaderActivity.MODEL_FILENAME, host.storyLaunches.single().third)
    }

    @Test
    fun openStoryReaderSharesTheSingleFlightGateWithTheCharacterReader() {
        val bridge = bridge()
        bridge.open()
        val second = RecordingResult()

        bridge.handle(
            MethodCall("openStoryReader", storyArguments(storyClip("ar_story1_p1_s0.mp3"))),
            second,
        )

        assertEquals(1, second.replies)
        assertEquals("reader_in_progress", second.errorCode)
    }

    @Test
    fun cancellingTheStoryReaderStillRepliesWithProgressOnTheSuccessChannel() {
        val bridge = bridge()
        bridge.handle(
            MethodCall("openStoryReader", storyArguments(storyClip("ar_story1_p1_s0.mp3"))),
            result,
        )

        bridge.finishStoryTerminal(
            code = CharacterReaderResultMapper.CANCELLED,
            lastPageId = "p3",
            pagesRead = listOf("p1", "p2", "p3"),
        )

        assertEquals(1, result.replies)
        assertNull(result.errorCode)
        val payload = result.successValue as Map<*, *>
        assertEquals("cancelled", payload["terminalCode"])
        assertEquals("p3", payload["lastPageId"])
        assertEquals(listOf("p1", "p2", "p3"), payload["pagesRead"])
    }

    @Test
    fun completingTheStoryReaderRepliesOnTheSuccessChannel() {
        val bridge = bridge()
        bridge.handle(
            MethodCall("openStoryReader", storyArguments(storyClip("ar_story1_p1_s0.mp3"))),
            result,
        )

        bridge.finishStoryTerminal(
            code = CharacterReaderResultMapper.COMPLETED,
            lastPageId = "p2",
            pagesRead = listOf("p1", "p2"),
        )

        val payload = result.successValue as Map<*, *>
        assertEquals("completed", payload["terminalCode"])
        assertEquals("p2", payload["lastPageId"])
    }

    @Test
    fun aRealStoryReaderFailureStillUsesTheErrorChannel() {
        val bridge = bridge()
        bridge.handle(
            MethodCall("openStoryReader", storyArguments(storyClip("ar_story1_p1_s0.mp3"))),
            result,
        )

        bridge.finishStoryTerminal(code = "model_missing", lastPageId = null, pagesRead = emptyList())

        assertEquals(1, result.replies)
        assertEquals("model_missing", result.errorCode)
        assertNull(result.successValue)
    }

    @Test
    fun theStoryReaderReleasesTheGateSoAnotherReaderCanOpen() {
        val bridge = bridge()
        bridge.handle(
            MethodCall("openStoryReader", storyArguments(storyClip("ar_story1_p1_s0.mp3"))),
            result,
        )
        bridge.finishStoryTerminal(
            code = CharacterReaderResultMapper.CANCELLED,
            lastPageId = "p1",
            pagesRead = listOf("p1"),
        )

        val second = RecordingResult()
        bridge.handle(MethodCall("openCharacterReader", mapOf("audioFilePath" to audioPath)), second)

        assertEquals(0, second.replies)
        assertEquals(listOf(launchedPath), host.launches)
    }

    // ---- capability probe ----

    @Test
    fun isStoryReaderSupportedAnswersWithoutTakingTheGate() {
        val bridge = bridge()

        bridge.handle(MethodCall("isStoryReaderSupported", null), result)

        assertEquals(1, result.replies)
        assertEquals(true, result.successValue)

        // The probe must not have consumed the single-flight gate.
        val second = RecordingResult()
        bridge.handle(MethodCall("openCharacterReader", mapOf("audioFilePath" to audioPath)), second)
        assertEquals(0, second.replies)
    }

    @Test
    fun isStoryReaderSupportedIsFalseOnlyWhenArCoreIsUnsupported() {
        arCore.availability = ArCoreAvailabilityDecision.Unsupported
        bridge().handle(MethodCall("isStoryReaderSupported", null), result)
        assertEquals(false, result.successValue)

        val transient = RecordingResult()
        arCore.availability = ArCoreAvailabilityDecision.Retry
        bridge().handle(MethodCall("isStoryReaderSupported", null), transient)
        assertEquals(true, transient.successValue)
    }

    @Test
    fun unknownMethodsAreNotImplemented() {
        bridge().handle(MethodCall("somethingElse", null), result)

        assertTrue(result.notImplementedCalls > 0)
    }

    private companion object {
        const val READER_REQUEST_CODE = 0x51A2
    }
}

private class FakeArCoreGateway : ArCoreGateway {
    var availability = ArCoreAvailabilityDecision.Supported
    var defaultOutcome = ArCoreInstallOutcome.Requested
    var outcomes = mutableListOf<ArCoreInstallOutcome>()
    val installCalls = mutableListOf<Boolean>()

    override fun checkAvailability() = availability

    override fun requestInstall(userRequestedInstall: Boolean): ArCoreInstallOutcome {
        installCalls += userRequestedInstall
        return if (outcomes.isEmpty()) defaultOutcome else outcomes.removeAt(0)
    }
}

private class FakeReaderHost : ReaderHost {
    var presentable = true
    var launchSucceeds = true
    val launches = mutableListOf<String>()
    val storyLaunches = mutableListOf<Triple<List<StoryReaderPage>, Int, String>>()

    override fun isPresentable() = presentable

    override fun launchReader(audioPath: String): Boolean {
        launches += audioPath
        return launchSucceeds
    }

    override fun launchStoryReader(
        pages: List<StoryReaderPage>,
        initialPageIndex: Int,
        modelAssetFileName: String,
    ): Boolean {
        storyLaunches += Triple(pages, initialPageIndex, modelAssetFileName)
        return launchSucceeds
    }
}

private class InlineScheduler : Scheduler {
    val delayed = mutableListOf<() -> Unit>()
    var lastDelayMs: Long? = null

    override fun runOnMain(action: () -> Unit) = action()

    override fun postDelayed(delayMs: Long, action: () -> Unit) {
        lastDelayMs = delayMs
        delayed += action
    }

    fun runNextDelayed() {
        delayed.removeAt(0).invoke()
    }
}

private class RecordingResult : MethodChannel.Result {
    var replies = 0
    var successValue: Any? = null
    var errorCode: String? = null
    var notImplementedCalls = 0

    override fun success(result: Any?) {
        replies++
        successValue = result
    }

    override fun error(code: String, message: String?, details: Any?) {
        replies++
        errorCode = code
    }

    override fun notImplemented() {
        replies++
        notImplementedCalls++
    }
}
