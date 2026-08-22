package com.storybookar.storybook_ar.characterreader

import android.app.Activity
import android.content.Intent
import com.storybookar.storybook_ar.OneAtATimeGate
import com.storybookar.storybook_ar.OneShotGate
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the `openCharacterReader` call: validates the audio path, gets ARCore into a usable state,
 * launches the reader, and replies exactly once.
 *
 * Everything Android-shaped is behind [ArCoreGateway], [ReaderHost] and [Scheduler] so the flow
 * itself is reachable from a JVM unit test. Build the production wiring with [create].
 */
class CharacterReaderBridge internal constructor(
    private val arCore: ArCoreGateway,
    private val host: ReaderHost,
    private val scheduler: Scheduler,
    private val audioPathValidator: AudioPathValidator,
    private val readerRequestCode: Int,
) {
    private val inProgressGate = OneAtATimeGate()
    private var channel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var replyGate: OneShotGate? = null
    private var pendingAudioPath: String? = null
    private var installAttempts = 0
    private var awaitingInstallResume = false

    internal fun attachTo(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).apply {
            setMethodCallHandler(::handle)
        }
    }

    internal fun handle(call: MethodCall, result: MethodChannel.Result) {
        scheduler.runOnMain {
            if (call.method != "openCharacterReader") {
                result.notImplemented()
                return@runOnMain
            }
            if (!inProgressGate.tryStart()) {
                result.error("reader_in_progress", null, null)
                return@runOnMain
            }

            val path = (call.arguments as? Map<*, *>)?.get("audioFilePath") as? String
            val audioFile = audioPathValidator.validate(path)
            if (audioFile == null) {
                inProgressGate.finish()
                result.error("audio_missing", null, null)
                return@runOnMain
            }
            if (!host.isPresentable()) {
                inProgressGate.finish()
                result.error("ar_failed", null, null)
                return@runOnMain
            }

            pendingResult = result
            replyGate = OneShotGate()
            pendingAudioPath = audioFile.path
            installAttempts = 0
            awaitingInstallResume = false
            checkArAvailability(remainingTransientPolls = MAX_TRANSIENT_POLLS)
        }
    }

    private fun checkArAvailability(remainingTransientPolls: Int) {
        when (arCore.checkAvailability()) {
            ArCoreAvailabilityDecision.Supported -> launchReader()
            ArCoreAvailabilityDecision.NeedsInstall -> requestArCoreInstall()
            ArCoreAvailabilityDecision.Unsupported -> finishError("ar_unsupported")
            ArCoreAvailabilityDecision.Failed -> finishError("ar_failed")
            ArCoreAvailabilityDecision.Retry -> {
                if (remainingTransientPolls <= 0) {
                    finishError("ar_failed")
                } else {
                    scheduler.postDelayed(TRANSIENT_POLL_INTERVAL_MS) {
                        checkArAvailability(remainingTransientPolls - 1)
                    }
                }
            }
        }
    }

    private fun requestArCoreInstall() {
        val step = ArCoreInstallPolicy.nextStep(installAttempts)
        if (step == ArCoreInstallStep.GiveUp) {
            finishError("ar_failed")
            return
        }
        installAttempts++
        when (arCore.requestInstall(step == ArCoreInstallStep.Prompt)) {
            ArCoreInstallOutcome.Installed -> {
                awaitingInstallResume = false
                checkArAvailability(remainingTransientPolls = MAX_TRANSIENT_POLLS)
            }
            // The installer is now in front of us and will not report back through
            // onActivityResult. onHostResume() picks the flow up again.
            ArCoreInstallOutcome.Requested -> awaitingInstallResume = true
            ArCoreInstallOutcome.Declined -> finishError("cancelled")
            ArCoreInstallOutcome.NotCompatible -> finishError("ar_unsupported")
            ArCoreInstallOutcome.Failed -> finishError("ar_failed")
        }
    }

    /**
     * Drives the second half of the ARCore install flow. requestInstall() reports the outcome of
     * an install by being called again after the host activity resumes, never through an activity
     * result, so without this the pending result is orphaned on every device that has to install
     * the ARCore APK.
     */
    fun onHostResume() {
        scheduler.runOnMain {
            if (pendingResult == null || !awaitingInstallResume) return@runOnMain
            awaitingInstallResume = false
            requestArCoreInstall()
        }
    }

    private fun launchReader() {
        val audioPath = pendingAudioPath ?: run {
            finishError("audio_missing")
            return
        }
        // A transient-availability poll or an install resume can land after the app has left
        // the foreground. startActivityForResult is silently dropped from the background on
        // Android 10+ without throwing, so re-check here rather than leave the call pending.
        if (!host.isPresentable()) {
            finishError("ar_failed")
            return
        }
        if (!host.launchReader(audioPath)) {
            finishError("ar_failed")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != readerRequestCode) return false
        if (pendingResult == null) return true

        val terminalCodeExtra =
            data?.getStringExtra(CharacterReaderResultMapper.EXTRA_TERMINAL_CODE)
        when (val code = CharacterReaderResultMapper.terminalCode(resultCode, terminalCodeExtra)) {
            CharacterReaderResultMapper.COMPLETED -> finishSuccess("completed")
            else -> finishError(code)
        }
        return true
    }

    private fun finishSuccess(value: Any?) {
        val result = pendingResult ?: return
        val gate = replyGate ?: return
        if (!gate.claim()) return
        clearPending()
        scheduler.runOnMain { result.success(value) }
    }

    private fun finishError(code: String) {
        val result = pendingResult ?: return
        val gate = replyGate ?: return
        if (!gate.claim()) return
        clearPending()
        scheduler.runOnMain { result.error(code, null, null) }
    }

    private fun clearPending() {
        pendingResult = null
        replyGate = null
        pendingAudioPath = null
        installAttempts = 0
        awaitingInstallResume = false
        inProgressGate.finish()
    }

    companion object {
        const val CHANNEL_NAME = "storybook_ar/character_reader"
        private const val TRANSIENT_POLL_INTERVAL_MS = 200L
        private const val MAX_TRANSIENT_POLLS = 10

        fun create(
            activity: Activity,
            messenger: BinaryMessenger,
            readerRequestCode: Int,
        ): CharacterReaderBridge =
            CharacterReaderBridge(
                arCore = ArCoreApkGateway(activity),
                host = ActivityReaderHost(activity, readerRequestCode),
                scheduler = MainLooperScheduler(),
                audioPathValidator = AudioPathValidator(activity.cacheDir),
                readerRequestCode = readerRequestCode,
            ).apply { attachTo(messenger) }
    }
}
