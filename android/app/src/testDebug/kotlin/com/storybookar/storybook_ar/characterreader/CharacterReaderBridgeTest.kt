package com.storybookar.storybook_ar.characterreader

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

    override fun isPresentable() = presentable

    override fun launchReader(audioPath: String): Boolean {
        launches += audioPath
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
    }
}
