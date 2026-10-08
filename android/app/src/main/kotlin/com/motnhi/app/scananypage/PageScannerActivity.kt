package com.motnhi.app.scananypage

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.hardware.display.DisplayManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.Surface
import android.view.TextureView
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.addCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import java.io.File
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

/** One guided page; auto capture on a stable border or manual capture on demand. */
class PageScannerActivity : ComponentActivity(), TextureView.SurfaceTextureListener {
    private val handler = Handler(Looper.getMainLooper())
    private val stability = PageBoundaryStability()
    private lateinit var root: FrameLayout
    private lateinit var preview: TextureView
    private lateinit var overlay: ScannerOverlayView
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var surface: Surface? = null
    private var previewSize = Size(1920, 1080)
    private var sensorRotation = 90
    private var opening = false
    private var analysing = false
    private var capturing = false
    private var terminal = false
    private var active = false
    private var requestingPermission = false
    private var generation = 0
    private var layoutGeneration = 0
    private var previewLayoutKey = ""
    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = Unit
        override fun onDisplayRemoved(displayId: Int) = Unit
        override fun onDisplayChanged(displayId: Int) {
            if (active && displayId == preview.display?.displayId) layoutPreview()
        }
    }

    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        requestingPermission = false
        if (granted) openCamera() else finishWith("camera_denied")
    }

    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
        root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        preview = TextureView(this).apply { surfaceTextureListener = this@PageScannerActivity }
        root.addView(preview, FrameLayout.LayoutParams(-1, -1))
        overlay = ScannerOverlayView(this, { finishWith("cancelled") }, { manualCapture() }).apply {
            onGuideChanged = {
                layoutGeneration++
                stability.reset()
            }
        }
        overlay.setCaptureEnabled(false)
        root.addView(overlay, FrameLayout.LayoutParams(-1, -1))
        ViewCompat.setOnApplyWindowInsetsListener(overlay) { view, insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom)
            insets
        }
        setContentView(root)
        ViewCompat.requestApplyInsets(overlay)
        onBackPressedDispatcher.addCallback(this) { finishWith("cancelled") }
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestingPermission = true
            permission.launch(Manifest.permission.CAMERA)
        }
    }

    override fun onResume() {
        super.onResume()
        active = true
        getSystemService(DisplayManager::class.java).registerDisplayListener(displayListener, handler)
        openCamera()
    }

    override fun onPause() {
        active = false
        getSystemService(DisplayManager::class.java).unregisterDisplayListener(displayListener)
        generation++
        closeCamera()
        // A permission prompt is the only expected interruption before capture.
        if (!requestingPermission && !terminal) finishWith("cancelled")
        super.onPause()
    }

    override fun onDestroy() {
        // Keep queued completion callbacks: they delete a JPEG whose compression
        // finished after cancellation.
        closeCamera()
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        root.post { if (active && !terminal) layoutPreview() }
    }

    private fun openCamera() {
        if (!active || terminal || opening || camera != null || !preview.isAvailable ||
            checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) return
        opening = true
        val epoch = generation
        try {
            val manager = getSystemService(CameraManager::class.java)
            val id = manager.cameraIdList.firstOrNull {
                manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: throw IllegalStateException("no_camera")
            val characteristics = manager.getCameraCharacteristics(id)
            sensorRotation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            val sizes = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(SurfaceTexture::class.java).orEmpty()
            previewSize = sizes.filter { maxOf(it.width, it.height) <= 2560 }
                .maxByOrNull { it.width.toLong() * it.height } ?: sizes.minByOrNull { it.width.toLong() * it.height }
                ?: throw IllegalStateException("no_preview")
            layoutPreview()
            manager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    opening = false
                    if (terminal || !active || epoch != generation) { device.close(); return }
                    camera = device
                    startPreview(device, characteristics, epoch)
                }
                override fun onDisconnected(device: CameraDevice) {
                    device.close()
                    if (!terminal && epoch == generation) finishWith("camera_unavailable")
                }
                override fun onError(device: CameraDevice, error: Int) {
                    device.close()
                    if (!terminal && epoch == generation) finishWith("camera_unavailable")
                }
            }, handler)
        } catch (_: SecurityException) {
            opening = false
            finishWith("camera_denied")
        } catch (_: Exception) {
            opening = false
            finishWith("camera_unavailable")
        }
    }

    @Suppress("DEPRECATION")
    private fun startPreview(device: CameraDevice, characteristics: CameraCharacteristics, epoch: Int) {
        val texture = preview.surfaceTexture ?: return finishWith("camera_unavailable")
        texture.setDefaultBufferSize(previewSize.width, previewSize.height)
        val target = Surface(texture)
        surface = target
        try {
            device.createCaptureSession(listOf(target), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(configured: CameraCaptureSession) {
                    if (terminal || !active || epoch != generation) { configured.close(); return }
                    session = configured
                    try {
                        val request = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                            addTarget(target)
                            val modes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: intArrayOf()
                            if (CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE in modes) {
                                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                            }
                        }
                        configured.setRepeatingRequest(request.build(), null, handler)
                        overlay.setCaptureEnabled(true)
                        scheduleAnalysis()
                    } catch (_: Exception) { finishWith("camera_unavailable") }
                }
                override fun onConfigureFailed(configured: CameraCaptureSession) {
                    configured.close()
                    if (!terminal && epoch == generation) finishWith("camera_unavailable")
                }
            }, handler)
        } catch (_: Exception) { finishWith("camera_unavailable") }
    }

    @Suppress("DEPRECATION")
    private fun layoutPreview() {
        if (terminal || capturing) return
        val width = preview.width
        val height = preview.height
        if (width <= 0 || height <= 0) return
        val displayDegrees = (preview.display?.rotation ?: windowManager.defaultDisplay.rotation) * 90
        val key = "$width:$height:${previewSize.width}:${previewSize.height}:$sensorRotation:$displayDegrees"
        if (key == previewLayoutKey) return
        val destination = ScannerPreviewGeometry.textureCorners(width, height,
            previewSize.width, previewSize.height, sensorRotation, displayDegrees)
        val source = floatArrayOf(0f, 0f, width.toFloat(), 0f, width.toFloat(), height.toFloat(), 0f, height.toFloat())
        val matrix = Matrix()
        if (!matrix.setPolyToPoly(source, 0, destination, 0, 4)) return finishWith("camera_unavailable")
        preview.setTransform(matrix)
        previewLayoutKey = key
        layoutGeneration++
        stability.reset()
        overlay.setGuidance(ScannerGuidance.FindPage)
    }

    private fun bitmapGuide(bitmap: Bitmap): RectF {
        val guide = overlay.guideRect
        val mapped = ScannerPreviewGeometry.mapGuide(ScannerRect(guide.left, guide.top, guide.right, guide.bottom),
            preview.width, preview.height, bitmap.width, bitmap.height)
        return RectF(mapped.left, mapped.top, mapped.right, mapped.bottom)
    }

    private fun scheduleAnalysis() {
        handler.postDelayed({ analyse() }, 240)
    }

    private fun analyse() {
        if (!active || terminal || capturing || analysing || camera == null) return
        if (overlay.guideRect.isEmpty) return scheduleAnalysis()
        val sampleHeight = (256f * preview.height / preview.width).roundToInt().coerceIn(160, 480)
        val bitmap = runCatching { preview.getBitmap(256, sampleHeight) }.getOrNull() ?: return scheduleAnalysis()
        analysing = true
        val epoch = generation
        val layoutEpoch = layoutGeneration
        val guide = bitmapGuide(bitmap)
        Thread {
            val detected = try {
                val pixels = IntArray(bitmap.width * bitmap.height)
                bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                val gray = IntArray(160 * 160)
                for (y in 0 until 160) for (x in 0 until 160) {
                    val sourceX = (guide.left + (x + 0.5f) * guide.width() / 160).toInt().coerceIn(0, bitmap.width - 1)
                    val sourceY = (guide.top + (y + 0.5f) * guide.height() / 160).toInt().coerceIn(0, bitmap.height - 1)
                    val color = pixels[sourceY * bitmap.width + sourceX]
                    gray[y * 160 + x] = (Color.red(color) * 77 + Color.green(color) * 150 + Color.blue(color) * 29) / 256
                }
                PageBoundaryDetector.detect(gray, 160, 160)
            } catch (_: Exception) { null } finally { bitmap.recycle() }
            handler.post {
                analysing = false
                if (!active || terminal || capturing || epoch != generation || layoutEpoch != layoutGeneration) return@post
                overlay.setGuidance(if (detected == null) ScannerGuidance.FindPage else ScannerGuidance.HoldStill)
                if (stability.observe(detected) && detected != null) {
                    capture(detected)
                } else {
                    scheduleAnalysis()
                }
            }
        }.start()
    }

    private fun manualCapture() { capture(null) }

    private fun capture(quad: PageQuad?) {
        if (capturing || terminal || !active || camera == null || overlay.guideRect.isEmpty) return
        capturing = true
        overlay.setCaptureEnabled(false)
        val epoch = generation
        val bitmap = runCatching { preview.bitmap }.getOrNull()
        if (bitmap == null) { finishWith("capture_failed"); return }
        val guide = bitmapGuide(bitmap)
        overlay.setGuidance(ScannerGuidance.Preparing)
        val captured = try {
            if (quad == null) {
                val crop = ScannerPreviewGeometry.cropBounds(
                    ScannerRect(guide.left, guide.top, guide.right, guide.bottom), bitmap.width, bitmap.height)
                Bitmap.createBitmap(bitmap, crop.x, crop.y, crop.width, crop.height)
            } else {
                rectifyPage(bitmap, guide, quad)
            }
        } catch (_: Exception) {
            bitmap.recycle()
            finishWith("capture_failed")
            return
        }
        if (captured !== bitmap) bitmap.recycle()
        closeCamera()
        Thread {
            var file: File? = null
            try {
                file = File.createTempFile("scan-page-", ".jpg", cacheDir)
                file.outputStream().use { stream ->
                    check(captured.compress(Bitmap.CompressFormat.JPEG, 90, stream))
                }
                val output = file
                handler.post {
                    if (terminal || !active || epoch != generation) output.delete()
                    else finishWith(null, output.path)
                }
            } catch (_: Exception) {
                file?.delete()
                handler.post { if (!terminal) finishWith("capture_failed") }
            } finally { captured.recycle() }
        }.start()
    }

    private fun rectifyPage(bitmap: Bitmap, guide: RectF, quad: PageQuad): Bitmap {
        fun x(point: PagePoint) = guide.left + point.x * guide.width()
        fun y(point: PagePoint) = guide.top + point.y * guide.height()
        val tl = quad.topLeft; val tr = quad.topRight
        val br = quad.bottomRight; val bl = quad.bottomLeft
        val width = max(hypot(x(tr) - x(tl), y(tr) - y(tl)), hypot(x(br) - x(bl), y(br) - y(bl)))
            .roundToInt().coerceIn(1, 3000)
        val height = max(hypot(x(bl) - x(tl), y(bl) - y(tl)), hypot(x(br) - x(tr), y(br) - y(tr)))
            .roundToInt().coerceIn(1, 3000)
        val source = floatArrayOf(x(tl), y(tl), x(tr), y(tr), x(br), y(br), x(bl), y(bl))
        val destination = floatArrayOf(0f, 0f, width.toFloat(), 0f,
            width.toFloat(), height.toFloat(), 0f, height.toFloat())
        val matrix = Matrix()
        check(matrix.setPolyToPoly(source, 0, destination, 0, 4))
        val result = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        Canvas(result).drawBitmap(bitmap, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
        return result
    }

    private fun closeCamera() {
        opening = false
        overlay.setCaptureEnabled(false)
        stability.reset()
        session?.close(); session = null
        camera?.close(); camera = null
        surface?.release(); surface = null
    }

    private fun finishWith(error: String?, path: String? = null) {
        if (terminal) return
        terminal = true
        generation++
        closeCamera()
        val data = Intent().putExtra(EXTRA_ERROR, error).putExtra(EXTRA_IMAGE_PATH, path)
        setResult(if (error == null) RESULT_OK else RESULT_CANCELED, data)
        finish()
    }

    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) { openCamera() }
    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) { layoutPreview() }
    override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
    override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
        generation++
        closeCamera()
        return true
    }

    companion object {
        const val EXTRA_ERROR = "storybook_ar.scan.ERROR"
        const val EXTRA_IMAGE_PATH = "storybook_ar.scan.IMAGE_PATH"
    }
}
