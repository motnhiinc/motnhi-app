package com.motnhi.app.scananypage

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Rect
import android.os.Bundle
import android.os.SystemClock
import android.view.Gravity
import android.view.ViewGroup
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.activity.addCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.motnhi.app.R
import java.io.File
import java.util.concurrent.Executors

/** One-page camera: no editor, review screen or Done button. OCR of the live
 * preview is used only for capture eligibility; the backend still approves it. */
class PageScannerActivity : ComponentActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private val stability = ScanCaptureStability()
    private lateinit var preview: PreviewView
    private lateinit var status: TextView
    private lateinit var progress: ProgressBar
    private lateinit var shutter: Button
    private var cameraProvider: ProcessCameraProvider? = null
    private var capture: ImageCapture? = null
    private var analysis: ImageAnalysis? = null
    @Volatile private var capturing = false
    @Volatile private var terminal = false
    private var lastAnalysis = 0L
    private var output: File? = null
    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        if (it) startCamera() else fail("camera_denied")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Recover only files owned by this scanner after an interrupted process.
        cacheDir.listFiles()?.filter { it.isFile && it.name.startsWith("page-capture-") && it.extension == "jpg" }
            ?.forEach { it.delete() }
        val root = FrameLayout(this)
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        preview = PreviewView(this)
        root.addView(preview, FrameLayout.LayoutParams(-1, -1))
        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(16), dp(20), dp(16))
            setBackgroundColor(0xCC000000.toInt())
        }
        status = TextView(this).apply {
            setText(R.string.scan_point_page); setTextColor(Color.WHITE)
            textSize = 20f; gravity = Gravity.CENTER
            accessibilityLiveRegion = android.view.View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100 }
        shutter = Button(this).apply {
            setText(R.string.scan_capture_manually)
            setOnClickListener { capturePage() }
        }
        controls.addView(status)
        controls.addView(progress, LinearLayout.LayoutParams(-1, 16))
        controls.addView(shutter)
        root.addView(controls, FrameLayout.LayoutParams(-1, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))
        val back = Button(this).apply {
            setText(R.string.reader_back)
            setOnClickListener { fail("cancelled") }
        }
        root.addView(back, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.START).apply {
            topMargin = dp(12); leftMargin = dp(16)
        })
        setContentView(root)
        onBackPressedDispatcher.addCallback(this) { fail("cancelled") }
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) startCamera()
        else permission.launch(Manifest.permission.CAMERA)
    }

    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            if (terminal || isDestroyed) return@addListener
            try {
                val provider = future.get()
                cameraProvider = provider
                val live = Preview.Builder().build().also { it.setSurfaceProvider(preview.surfaceProvider) }
                capture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
                analysis = ImageAnalysis.Builder()
                    .setTargetResolution(android.util.Size(720, 960))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build().also {
                        it.setAnalyzer(executor, ::analyze)
                    }
                provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, live, capture, analysis)
            } catch (_: Exception) { fail("camera_unavailable") }
        }, ContextCompat.getMainExecutor(this))
    }

    @androidx.annotation.OptIn(ExperimentalGetImage::class)
    private fun analyze(frame: ImageProxy) {
        if (terminal || capturing) { frame.close(); return }
        val now = SystemClock.elapsedRealtime()
        val image = frame.image
        if (image == null || now - lastAnalysis < 200) { frame.close(); return }
        lastAnalysis = now
        val rotation = frame.imageInfo.rotationDegrees
        val width = if (rotation % 180 == 0) frame.width else frame.height
        val height = if (rotation % 180 == 0) frame.height else frame.width
        // Sample luminance/edges before ML Kit finishes; never access a closed proxy.
        val plane = frame.planes[0]
        val buffer = plane.buffer
        var luminance = 0L; var edges = 0L; var samples = 0
        for (y in frame.height / 5 until frame.height * 4 / 5 step 8) {
            for (x in frame.width / 5 until frame.width * 4 / 5 step 8) {
                val index = y * plane.rowStride + x * plane.pixelStride
                if (index + plane.pixelStride >= buffer.limit()) continue
                val value = buffer.get(index).toInt() and 255
                luminance += value
                edges += kotlin.math.abs(value - (buffer.get(index + plane.pixelStride).toInt() and 255))
                samples++
            }
        }
        val quality = samples > 0 && luminance / samples in 45..235 && edges.toFloat() / samples > 2f
        val task = try {
            recognizer.process(InputImage.fromMediaImage(image, rotation))
        } catch (_: Exception) { frame.close(); return }
        task
            .addOnSuccessListener { text ->
                if (terminal || capturing || !lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) return@addOnSuccessListener
                val lines = text.textBlocks.flatMap { it.lines }
                val boxes = lines.mapNotNull { it.boundingBox }
                val bounds = boxes.firstOrNull()?.let { first ->
                    Rect(first).apply { boxes.drop(1).forEach { union(it) } }
                }
                val normalized = bounds?.let {
                    floatArrayOf(it.left.toFloat() / width, it.top.toFloat() / height,
                        it.right.toFloat() / width, it.bottom.toFloat() / height)
                }
                val readable = quality && lines.isNotEmpty() && text.text.length >= 12 &&
                    bounds != null && bounds.width() > width * 0.25 && bounds.height() > height * 0.02 &&
                    bounds.left > width * 0.02 && bounds.right < width * 0.98 &&
                    bounds.top > height * 0.02 && bounds.bottom < height * 0.98 &&
                    boxes.map { it.height() }.average() >= height * 0.014
                val fraction = stability.observe(text.text, normalized, readable, SystemClock.elapsedRealtime())
                progress.progress = (fraction * 100).toInt()
                status.setText(if (readable) R.string.scan_hold_steady else R.string.scan_point_page)
                if (fraction >= 1) capturePage()
            }
            .addOnFailureListener { stability.reset() }
            .addOnCompleteListener { frame.close() }
    }

    private fun capturePage() {
        val camera = capture ?: return
        if (terminal || capturing || !lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) return
        capturing = true
        analysis?.clearAnalyzer()
        shutter.isEnabled = false
        status.setText(R.string.scan_captured)
        shutter.performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM)
        val file = try {
            File.createTempFile("page-capture-", ".jpg", cacheDir)
        } catch (_: Exception) { fail("capture_failed"); return }
        output = file
        camera.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(),
            ContextCompat.getMainExecutor(this), object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                    if (terminal) { file.delete(); return }
                    terminal = true
                    cameraProvider?.unbindAll()
                    setResult(RESULT_OK, Intent().putExtra(EXTRA_IMAGE_PATH, file.absolutePath))
                    finish()
                }
                override fun onError(error: ImageCaptureException) { fail("capture_failed") }
            })
    }

    private fun fail(code: String) {
        if (terminal) return
        terminal = true
        cameraProvider?.unbindAll()
        output?.delete()
        setResult(RESULT_CANCELED, Intent().putExtra("scan_failure", code))
        finish()
    }

    override fun onPause() {
        stability.reset()
        progress.progress = 0
        super.onPause()
    }

    override fun onDestroy() {
        if (!terminal) output?.delete()
        terminal = true
        analysis?.clearAnalyzer()
        cameraProvider?.unbindAll()
        executor.shutdown()
        recognizer.close()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_IMAGE_PATH = "storybook_ar.scan.CAPTURED_IMAGE_PATH"
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
