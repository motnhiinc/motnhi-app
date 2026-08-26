package com.motnhi.app.characterreader

import android.app.Activity
import android.content.Intent
import com.motnhi.app.OneAtATimeGate
import com.motnhi.app.OneShotGate
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

    /** True while the pending call came from `openStoryReader` rather than `openCharacterReader`. */
    private var pendingIsStoryReader = false
    private var pendingPages: List<StoryReaderPage>? = null
    private var pendingInitialPageIndex = 0

    /**
     * The bundled `<base>.glb` the story reader should load. Only story mode carries a choice;
     * the single-clip scan-any-page flow keeps the fox, so this stays at the default there.
     */
    private var pendingModelAssetFileName: String = CharacterReaderActivity.MODEL_FILENAME

    internal fun attachTo(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).apply {
            setMethodCallHandler(::handle)
        }
    }

    internal fun handle(call: MethodCall, result: MethodChannel.Result) {
        scheduler.runOnMain {
            when (call.method) {
                // Deliberately outside the gate: a capability probe presents nothing, and the
                // player asks it once on open so an unsupported device never shows the AR button
                // and then fails after a long preparation. Retry is transient, so only an
                // outright Unsupported answers false.
                "isStoryReaderSupported" ->
                    result.success(
                        arCore.checkAvailability() != ArCoreAvailabilityDecision.Unsupported,
                    )

                "openCharacterReader" -> start(call, result, storyMode = false)
                "openStoryReader" -> start(call, result, storyMode = true)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Shared entry for both readers. They share [inProgressGate] on purpose: they are the same
     * channel and the same activity, so two readers must never be presentable at once.
     */
    private fun start(call: MethodCall, result: MethodChannel.Result, storyMode: Boolean) {
        if (!inProgressGate.tryStart()) {
            result.error("reader_in_progress", null, null)
            return
        }

        val arguments = call.arguments as? Map<*, *>
        if (storyMode) {
            val pages = StoryReaderPages.parse(arguments?.get("pages"))
                ?.let(::validatePages)
            if (pages == null) {
                inProgressGate.finish()
                result.error("audio_missing", null, null)
                return
            }
            if (!host.isPresentable()) {
                inProgressGate.finish()
                result.error("ar_failed", null, null)
                return
            }
            pendingPages = pages
            pendingInitialPageIndex = StoryReaderPages.clampIndex(
                (arguments?.get("initialPageIndex") as? Number)?.toInt() ?: 0,
                pages.size,
            )
            pendingModelAssetFileName = modelAssetFileName(arguments)
            pendingAudioPath = null
        } else {
            val audioFile = audioPathValidator
                .validate(arguments?.get("audioFilePath") as? String)
            if (audioFile == null) {
                inProgressGate.finish()
                result.error("audio_missing", null, null)
                return
            }
            if (!host.isPresentable()) {
                inProgressGate.finish()
                result.error("ar_failed", null, null)
                return
            }
            pendingAudioPath = audioFile.path
            pendingPages = null
        }

        pendingIsStoryReader = storyMode
        pendingResult = result
        replyGate = OneShotGate()
        installAttempts = 0
        awaitingInstallResume = false
        checkArAvailability(remainingTransientPolls = MAX_TRANSIENT_POLLS)
    }

    /**
     * Maps Dart's chosen base name onto a bundled asset file name. The allowlist here is the
     * first gate: a malformed or hostile name never reaches the activity, it simply falls back
     * to the fox so an open still shows some character instead of failing with model_missing.
     * Deliberately free of Android types so JVM tests can pin the fallbacks.
     */
    private fun modelAssetFileName(arguments: Map<*, *>?): String {
        val baseName = arguments?.get("modelAssetBaseName") as? String
        val safeBaseName = baseName
            ?.takeIf { Regex("^[a-z0-9_]+$").matches(it) }
            ?: "scan_any_page_character"
        return "$safeBaseName.glb"
    }

    /**
     * Every clip in the playlist must validate; one bad path fails the whole request. A partial
     * playlist would leave the character silent partway through a page with no way to say why.
     */
    private fun validatePages(pages: List<StoryReaderPage>): List<StoryReaderPage>? =
        pages.map { page ->
            val validated = page.audioFilePaths.map { path ->
                audioPathValidator.validate(path)?.path ?: return null
            }
            page.copy(audioFilePaths = validated)
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
        // A transient-availability poll or an install resume can land after the app has left
        // the foreground. startActivityForResult is silently dropped from the background on
        // Android 10+ without throwing, so re-check here rather than leave the call pending.
        if (!host.isPresentable()) {
            finishError("ar_failed")
            return
        }

        val launched = if (pendingIsStoryReader) {
            val pages = pendingPages ?: run {
                finishError("audio_missing")
                return
            }
            host.launchStoryReader(pages, pendingInitialPageIndex, pendingModelAssetFileName)
        } else {
            val audioPath = pendingAudioPath ?: run {
                finishError("audio_missing")
                return
            }
            host.launchReader(audioPath)
        }

        if (!launched) finishError("ar_failed")
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != readerRequestCode) return false
        if (pendingResult == null) return true

        val terminalCodeExtra =
            data?.getStringExtra(CharacterReaderResultMapper.EXTRA_TERMINAL_CODE)
        val code = CharacterReaderResultMapper.terminalCode(resultCode, terminalCodeExtra)

        if (pendingIsStoryReader) {
            return finishStoryTerminal(
                code = code,
                lastPageId = data?.getStringExtra(CharacterReaderResultMapper.EXTRA_LAST_PAGE_ID),
                pagesRead = data
                    ?.getStringArrayListExtra(CharacterReaderResultMapper.EXTRA_PAGES_READ)
                    ?: emptyList(),
            )
        }

        when (code) {
            CharacterReaderResultMapper.COMPLETED -> finishSuccess("completed")
            else -> finishError(code)
        }
        return true
    }

    /**
     * Takes primitives rather than the [Intent] so JVM tests can drive it, mirroring
     * [CharacterReaderResultMapper.terminalCode]. Intent unwrapping belongs to the caller.
     *
     * Both `completed` and `cancelled` go down the *success* channel, unlike
     * `openCharacterReader` which sends everything but `completed` to `result.error`. Cancel is
     * the normal way to leave AR, and it still carries the page the child reached — routing it
     * as an error would throw that away and strand the book on the page AR started from.
     * `result.error` stays reserved for failures where nothing was ever presented.
     */
    internal fun finishStoryTerminal(
        code: String,
        lastPageId: String?,
        pagesRead: List<String>,
    ): Boolean {
        if (code == CharacterReaderResultMapper.COMPLETED ||
            code == CharacterReaderResultMapper.CANCELLED
        ) {
            finishStory(code, lastPageId, pagesRead)
        } else {
            finishError(code)
        }
        return true
    }

    private fun finishStory(
        terminalCode: String,
        lastPageId: String?,
        pagesRead: List<String>,
    ) {
        val result = pendingResult ?: return
        val gate = replyGate ?: return
        if (!gate.claim()) return
        clearPending()
        scheduler.runOnMain {
            result.success(
                mapOf(
                    "terminalCode" to terminalCode,
                    "lastPageId" to lastPageId,
                    "pagesRead" to pagesRead,
                ),
            )
        }
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
        pendingIsStoryReader = false
        pendingPages = null
        pendingInitialPageIndex = 0
        pendingModelAssetFileName = CharacterReaderActivity.MODEL_FILENAME
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
