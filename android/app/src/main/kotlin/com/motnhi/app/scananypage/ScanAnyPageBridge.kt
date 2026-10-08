package com.motnhi.app.scananypage

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.motnhi.app.OneAtATimeGate
import com.motnhi.app.OneShotGate
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
        try {
            activity.startActivityForResult(Intent(activity, PageScannerActivity::class.java), requestCode)
        } catch (_: RuntimeException) {
            finishError("camera_unavailable")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != this.requestCode) return false
        if (pendingResult == null) return true

        val failure = data?.getStringExtra(PageScannerActivity.EXTRA_ERROR)
        if (failure != null || resultCode != Activity.RESULT_OK) {
            finishError(failure ?: "cancelled")
            return true
        }
        val path = data?.getStringExtra(PageScannerActivity.EXTRA_IMAGE_PATH)
        val file = path?.let { runCatching { File(it).canonicalFile }.getOrNull() }
        if (file == null || file.parentFile != activity.cacheDir.canonicalFile ||
            !file.name.startsWith("scan-page-") || !file.name.endsWith(".jpg")) {
            finishError("capture_failed")
            return true
        }
        recognize(Uri.fromFile(file), file)
        return true
    }

    private fun recognize(uri: Uri, ownedFile: File) {
        // Decode/compress off the UI thread. OCR and Flutter both use the same
        // orientation-corrected bitmap, including on devices with EXIF rotation.
        Thread {
            val page = try {
                ScanPageImage.fromUri(activity, uri)
            } catch (_: Exception) {
                runOnMain { finishError("capture_failed") }
                return@Thread
            } finally {
                ownedFile.delete()
            }
            runOnMain { recognizePage(page) }
        }.start()
    }

    private fun recognizePage(page: ScanPageImage) {
        val image = InputImage.fromBitmap(page.bitmap, 0)
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(image)
            .addOnSuccessListener { recognizedText ->
                val lines = recognizedText.textBlocks
                    .flatMap { block -> block.lines }
                    .map(RecognizedTextLine::fromMlKit)
                val ordered = ReadingOrderSorter.ordered(lines, page.bitmap.height)
                val geometry = ordered.mapNotNull {
                    ReadingOrderSorter.normalizedLine(it, page.bitmap.width, page.bitmap.height)
                }
                if (geometry.isEmpty() || geometry.size > 40 ||
                    ordered.sumOf { it.text.codePointCount(0, it.text.length) } > 4000) {
                    finishError("no_text")
                } else {
                    finishSuccess(mapOf(
                        "imageBytes" to page.jpeg,
                        "width" to page.bitmap.width,
                        "height" to page.bitmap.height,
                        "lines" to geometry,
                    ))
                }
                recognizer.close()
                page.bitmap.recycle()
            }
            .addOnFailureListener {
                recognizer.close()
                page.bitmap.recycle()
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
