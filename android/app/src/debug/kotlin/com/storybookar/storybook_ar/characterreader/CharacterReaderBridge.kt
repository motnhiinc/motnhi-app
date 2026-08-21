package com.storybookar.storybook_ar.characterreader

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.storybookar.storybook_ar.OneAtATimeGate
import com.storybookar.storybook_ar.OneShotGate
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CharacterReaderBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val readerRequestCode: Int,
    private val installRequestCode: Int,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "storybook_ar/character_reader")
    private val audioPathValidator = AudioPathValidator(activity.cacheDir)
    private val inProgressGate = OneAtATimeGate()
    private var pendingResult: MethodChannel.Result? = null
    private var replyGate: OneShotGate? = null
    private var pendingAudioPath: String? = null
    private var arInstallRequested = false

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        runOnMain {
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
            if (!activity.isPresentable()) {
                inProgressGate.finish()
                result.error("ar_failed", null, null)
                return@runOnMain
            }

            pendingResult = result
            replyGate = OneShotGate()
            pendingAudioPath = audioFile.path
            arInstallRequested = false
            checkArAvailability(remainingTransientPolls = MAX_TRANSIENT_POLLS)
        }
    }

    private fun checkArAvailability(remainingTransientPolls: Int) {
        val availability = ArCoreApk.getInstance().checkAvailability(activity)
        when (ArCoreAvailabilityMapper.map(availability)) {
            ArCoreAvailabilityDecision.Supported -> launchReader()
            ArCoreAvailabilityDecision.NeedsInstall -> requestArCoreInstall()
            ArCoreAvailabilityDecision.Unsupported -> finishError("ar_unsupported")
            ArCoreAvailabilityDecision.Failed -> finishError("ar_failed")
            ArCoreAvailabilityDecision.Retry -> {
                if (remainingTransientPolls <= 0) {
                    finishError("ar_failed")
                } else {
                    mainHandler.postDelayed(
                        { checkArAvailability(remainingTransientPolls - 1) },
                        TRANSIENT_POLL_INTERVAL_MS,
                    )
                }
            }
        }
    }

    private fun requestArCoreInstall() {
        try {
            when (ArCoreApk.getInstance().requestInstall(activity, !arInstallRequested)) {
                ArCoreApk.InstallStatus.INSTALLED -> checkArAvailability(MAX_TRANSIENT_POLLS)
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    arInstallRequested = true
                }
            }
        } catch (_: UnavailableDeviceNotCompatibleException) {
            finishError("ar_unsupported")
        } catch (_: Exception) {
            finishError("ar_failed")
        }
    }

    private fun launchReader() {
        val audioPath = pendingAudioPath ?: run {
            finishError("audio_missing")
            return
        }
        try {
            val intent = Intent(activity, CharacterReaderActivity::class.java)
                .putExtra(CharacterReaderActivity.EXTRA_AUDIO_FILE_PATH, audioPath)
            activity.startActivityForResult(intent, readerRequestCode)
        } catch (_: RuntimeException) {
            finishError("ar_failed")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == installRequestCode) {
            if (pendingResult == null) return true
            if (resultCode == Activity.RESULT_CANCELED) {
                finishError("cancelled")
            } else {
                checkArAvailability(MAX_TRANSIENT_POLLS)
            }
            return true
        }
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
        runOnMain { result.success(value) }
    }

    private fun finishError(code: String) {
        val result = pendingResult ?: return
        val gate = replyGate ?: return
        if (!gate.claim()) return
        clearPending()
        runOnMain { result.error(code, null, null) }
    }

    private fun clearPending() {
        pendingResult = null
        replyGate = null
        pendingAudioPath = null
        arInstallRequested = false
        inProgressGate.finish()
    }

    private fun runOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post(action)
        }
    }

    companion object {
        private const val TRANSIENT_POLL_INTERVAL_MS = 200L
        private const val MAX_TRANSIENT_POLLS = 10
    }
}

private fun Activity.isPresentable(): Boolean {
    if (isFinishing || isDestroyed) return false
    val lifecycleOwner = this as? LifecycleOwner ?: return true
    return lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
}
