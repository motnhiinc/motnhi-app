package com.motnhi.app.scananypage

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.motnhi.app.OneAtATimeGate
import com.motnhi.app.OneShotGate
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ScanAnyPageBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val requestCode: Int,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "storybook_ar/scan_any_page")
    private val inProgressGate = OneAtATimeGate()
    private var pendingResult: MethodChannel.Result? = null
    private var replyGate: OneShotGate? = null

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        runOnMain {
            if (call.method != "scanAndRecognize") {
                result.notImplemented()
                return@runOnMain
            }
            if (!inProgressGate.tryStart()) {
                result.error("scan_in_progress", null, null)
                return@runOnMain
            }
            if (!activity.isPresentable()) {
                inProgressGate.finish()
                result.error("camera_unavailable", null, null)
                return@runOnMain
            }

            pendingResult = result
            replyGate = OneShotGate()
            launchScanner()
        }
    }

    private fun launchScanner() {
        val options = GmsDocumentScannerOptions.Builder()
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .setGalleryImportAllowed(false)
            .setPageLimit(1)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .build()

        GmsDocumentScanning.getClient(options)
            .getStartScanIntent(activity)
            .addOnSuccessListener { intentSender ->
                runOnMain {
                    try {
                        activity.startIntentSenderForResult(
                            intentSender,
                            requestCode,
                            null,
                            0,
                            0,
                            0,
                            null,
                        )
                    } catch (_: IntentSender.SendIntentException) {
                        finishError("camera_unavailable")
                    } catch (_: RuntimeException) {
                        finishError("camera_unavailable")
                    }
                }
            }
            .addOnFailureListener {
                finishError("camera_unavailable")
            }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != this.requestCode) return false
        if (pendingResult == null) return true

        val scanResult = data?.let { GmsDocumentScanningResult.fromActivityResultIntent(it) }
        val pages = scanResult?.pages.orEmpty()
        val failureCode = ScannerFailureMapper.activityResultFailureCode(
            resultCode = resultCode,
            hasParsedResult = scanResult != null,
            pageCount = pages.size,
        )
        if (failureCode != null) {
            finishError(failureCode)
            return true
        }

        val uri = pages.first().imageUri
        recognize(uri)
        return true
    }

    private fun recognize(uri: Uri) {
        val image = try {
            InputImage.fromFilePath(activity, uri)
        } catch (_: Exception) {
            finishError("capture_failed")
            return
        }
        // Take the height from the InputImage, not from a second raw decode of the file. The
        // bounding boxes are in this image's coordinate space, so the two agree by construction
        // even when the JPEG carries an EXIF rotation that a raw bounds decode would ignore.
        val imageHeight = image.height
        if (imageHeight <= 0) {
            finishError("capture_failed")
            return
        }
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(image)
            .addOnSuccessListener { recognizedText ->
                val lines = recognizedText.textBlocks
                    .flatMap { block -> block.lines }
                    .map(RecognizedTextLine::fromMlKit)
                val text = ReadingOrderSorter.join(lines, imageHeight)
                if (text.isBlank()) {
                    finishError("no_text")
                } else {
                    finishSuccess(mapOf("text" to text))
                }
                recognizer.close()
            }
            .addOnFailureListener {
                recognizer.close()
                finishError("ocr_failed")
            }
    }

    private fun finishSuccess(value: Any?) {
        val result = pendingResult ?: return
        val gate = replyGate ?: return
        if (!gate.claim()) return
        pendingResult = null
        replyGate = null
        inProgressGate.finish()
        runOnMain { result.success(value) }
    }

    private fun finishError(code: String) {
        val result = pendingResult ?: return
        val gate = replyGate ?: return
        if (!gate.claim()) return
        pendingResult = null
        replyGate = null
        inProgressGate.finish()
        runOnMain { result.error(code, null, null) }
    }

    private fun runOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post(action)
        }
    }
}

private fun Activity.isPresentable(): Boolean {
    if (isFinishing || isDestroyed) return false
    val lifecycleOwner = this as? LifecycleOwner ?: return true
    return lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
}
