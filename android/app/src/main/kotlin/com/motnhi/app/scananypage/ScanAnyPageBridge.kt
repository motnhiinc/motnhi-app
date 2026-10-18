package com.motnhi.app.scananypage

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.Build
import android.util.Log
import java.util.UUID
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
    private var attemptId = ""
    private var captureOnly = false
    private var scannerStarted = 0L
    private var captureReturned = 0L
    private var scansStarted = 0
    private var diagnosticFields: Map<String, Any> = emptyMap()

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
            captureOnly = call.argument<Boolean>("capture_only") == true
            replyGate = OneShotGate()
            attemptId = call.argument<String>("attempt_id") ?: UUID.randomUUID().toString()
            val appInfo = activity.packageManager.getPackageInfo(activity.packageName, 0)
            val connectivity = activity.getSystemService(ConnectivityManager::class.java)
            val network = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
            val category = when {
                network == null -> "offline"
                network.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                network.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                else -> "other"
            }
            diagnosticFields = mapOf("app_version" to (appInfo.versionName ?: "unknown"),
                "android_sdk" to Build.VERSION.SDK_INT, "device_model" to "${Build.MANUFACTURER}/${Build.MODEL}",
                "cold_run" to (scansStarted++ == 0), "network_category" to category)
            Log.d("ScanStages", "attempt=$attemptId stage=session app_version=${appInfo.versionName} android_sdk=${Build.VERSION.SDK_INT} device=${Build.MANUFACTURER}/${Build.MODEL}")
            launchScanner()
        }
    }

    private fun launchScanner() {
        val generation = replyGate
        val started = SystemClock.elapsedRealtime()
        val initializationTimeout = Runnable {
            if (replyGate === generation) finishError("scanner_initialization_timeout")
        }
        mainHandler.postDelayed(initializationTimeout, 30_000)
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
                    if (replyGate !== generation) return@runOnMain
                    mainHandler.removeCallbacks(initializationTimeout)
                    Log.d("ScanStages", "attempt=$attemptId stage=scanner_intent elapsed_ms=${SystemClock.elapsedRealtime() - started}")
                    scannerStarted = SystemClock.elapsedRealtime()
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
                if (replyGate === generation) {
                    mainHandler.removeCallbacks(initializationTimeout)
                    finishError("camera_unavailable")
                }
            }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != this.requestCode) return false
        if (pendingResult == null) return true
        captureReturned = SystemClock.elapsedRealtime()
        Log.d("ScanStages", "attempt=$attemptId stage=managed_scanner_round_trip elapsed_ms=${SystemClock.elapsedRealtime() - scannerStarted}")

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
        // Decode/compress off the UI thread. OCR and Flutter both use the same
        // orientation-corrected bitmap, including on devices with EXIF rotation.
        Thread {
            val page = try {
                ScanPageImage.fromUri(activity, uri, attemptId)
            } catch (error: Throwable) {
                val code = if (error is IllegalArgumentException && error.message in setOf("image_decode_failed", "image_encode_failed")) error.message!! else "image_decode_failed"
                runOnMain { finishError(code) }
                return@Thread
            }
            runOnMain { recognizePage(page) }
        }.start()
    }

    private fun recognizePage(page: ScanPageImage) {
        if (captureOnly) {
            finishSuccess(mapOf(
                "imageBytes" to page.jpeg,
                "width" to page.bitmap.width,
                "height" to page.bitmap.height,
                "lines" to emptyList<Any>(),
                "nativeProcessingMs" to (SystemClock.elapsedRealtime() - captureReturned),
                "diagnostics" to diagnosticFields,
            ))
            page.bitmap.recycle()
            return
        }
        val started = SystemClock.elapsedRealtime()
        val recognizer = try {
            TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        } catch (_: Exception) {
            page.bitmap.recycle()
            finishError("ocr_failed")
            return
        }
        val task = try {
            recognizer.process(InputImage.fromBitmap(page.bitmap, 0))
        } catch (_: Exception) {
            recognizer.close()
            page.bitmap.recycle()
            finishError("ocr_failed")
            return
        }
        task
            .addOnSuccessListener { recognizedText ->
                Thread {
                    try {
                        val lines = recognizedText.textBlocks
                            .flatMap { block -> block.lines }
                            .map(RecognizedTextLine::fromMlKit)
                        val ordered = ReadingOrderSorter.ordered(lines, page.bitmap.height)
                        val geometry = ordered.mapNotNull {
                            ReadingOrderSorter.normalizedLine(it, page.bitmap.width, page.bitmap.height)
                        }
                        Log.d("ScanStages", "attempt=$attemptId stage=ocr elapsed_ms=${SystemClock.elapsedRealtime() - started} lines=${geometry.size}")
                        val limitFailure = PageLimits.failureCode(lines.map { it.text })
                        if (limitFailure != null || geometry.isEmpty()) {
                            finishError(limitFailure ?: "no_text")
                        } else {
                            val quality = PageQuality.assess(page.bitmap, ordered)
                            Log.d("ScanStages", "attempt=$attemptId stage=quality version=1 mode=observational samples=${quality["textRegionSamples"]} sharpness=${quality["sharpness"]} bright_fraction=${quality["brightFraction"]} text_height_fraction=${quality["textHeightFraction"]}")
                            finishSuccess(mapOf(
                                "imageBytes" to page.jpeg,
                                "width" to page.bitmap.width,
                                "height" to page.bitmap.height,
                                "lines" to geometry,
                                "quality" to quality,
                                "nativeProcessingMs" to (SystemClock.elapsedRealtime() - captureReturned),
                                "diagnostics" to diagnosticFields,
                            ))
                        }
                    } catch (_: Throwable) {
                        finishError("ocr_failed")
                    } finally {
                        recognizer.close()
                        page.bitmap.recycle()
                    }
                }.start()
            }
            .addOnFailureListener {
                recognizer.close()
                page.bitmap.recycle()
                finishError("ocr_failed")
            }
    }

    private fun finishSuccess(value: Any?) {
        runOnMain {
            val result = pendingResult ?: return@runOnMain
            val gate = replyGate ?: return@runOnMain
            if (!gate.claim()) return@runOnMain
            pendingResult = null
            replyGate = null
            inProgressGate.finish()
            result.success(value)
        }
    }

    private fun finishError(code: String) {
        runOnMain {
            val result = pendingResult ?: return@runOnMain
            val gate = replyGate ?: return@runOnMain
            if (!gate.claim()) return@runOnMain
            Log.d("ScanStages", "attempt=$attemptId stage=native_failure reason=$code")
            pendingResult = null
            replyGate = null
            inProgressGate.finish()
            result.error(code, null, null)
        }
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
