package com.motnhi.app.characterreader

import android.view.MotionEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.Typeface
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.TextUnit
import com.google.ar.core.Config
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import com.google.android.filament.gltfio.FilamentInstance
import com.google.ar.core.Anchor
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberMaterialLoader
import io.github.sceneview.rememberModelLoader

/**
 * Screen state the activity drives. The audio and lifecycle logic lives on the activity, exactly as
 * it did when this was a View hierarchy; only the rendering moved to Compose, because SceneView 4.x
 * exposes ARScene as a composable and ships no Android View.
 */
internal class ReaderUiState {
    var scannedPageMode by mutableStateOf(false)
    var guidance by mutableStateOf(GUIDANCE_PREPARING)
    var readLabel by mutableStateOf("Read")
    var controlsVisible by mutableStateOf(false)
    var speaking by mutableStateOf(false)

    /** Empty in the single-clip scan-any-page flow, which has no pages to move between. */
    var pageLabel by mutableStateOf("")
    var canGoPrevious by mutableStateOf(false)
    var canGoNext by mutableStateOf(false)
}

internal const val GUIDANCE_PREPARING = "Preparing character reader"
internal const val GUIDANCE_LOADING = "Loading character"
internal const val GUIDANCE_SEARCHING = "Move the phone slowly to find a table"
internal const val GUIDANCE_SURFACE_FOUND = "Table found - Tap to place the character"
internal const val GUIDANCE_READY = "Character ready"

internal fun scanLabel(en: String, vi: String): String =
    if (java.util.Locale.getDefault().language == "vi") vi else en

/** Uniform size the character is scaled to, in metres. Matches the iOS reader. */
private const val MODEL_SIZE_METERS = 0.35f

@Composable
internal fun CharacterReaderScreen(
    state: ReaderUiState,
    modelAssetFileName: String,
    onFailure: (String) -> Unit,
    onPlaced: () -> Unit,
    onReadClick: () -> Unit,
    onPreviousClick: () -> Unit,
    onNextClick: () -> Unit,
    onCloseClick: () -> Unit,
    onScanNextClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        // Deliberately not passed the page state: page turns must not recompose the AR scene,
        // because the placed anchor lives in its remembered state.
        CharacterReaderArScene(
            state = state,
            modelAssetFileName = modelAssetFileName,
            onFailure = onFailure,
            onPlaced = onPlaced,
        )
        Overlay(
            state = state,
            onReadClick = onReadClick,
            onPreviousClick = onPreviousClick,
            onNextClick = onNextClick,
            onCloseClick = onCloseClick,
            onScanNextClick = onScanNextClick,
        )
    }
}

@Composable
private fun CharacterReaderArScene(
    state: ReaderUiState,
    modelAssetFileName: String,
    onFailure: (String) -> Unit,
    onPlaced: () -> Unit,
) {
    val engine = rememberEngine()
    val modelLoader = rememberModelLoader(engine)
    val materialLoader = rememberMaterialLoader(engine)
    var placedAnchor by remember { mutableStateOf<Anchor?>(null) }
    val placed = placedAnchor != null
    var pendingTapX by remember { mutableStateOf<Float?>(null) }
    var pendingTapY by remember { mutableStateOf<Float?>(null) }
    var modelInstance by remember { mutableStateOf<FilamentInstance?>(null) }

    // Loaded off the main thread. createModelInstance() is a blocking file read plus glTF parse,
    // which would jank the reader's first frame in proportion to the model size. iOS loads
    // asynchronously behind the same "Loading character" step. A missing .glb is already caught
    // as model_missing before this screen is shown, so a failure here is a real parse failure.
    LaunchedEffect(modelAssetFileName) {
        state.guidance = GUIDANCE_LOADING
        val loaded = runCatching { modelLoader.loadModelInstance(modelAssetFileName) }.getOrNull()
        if (loaded == null) {
            onFailure("model_load_failed")
        } else {
            modelInstance = loaded
            state.guidance = GUIDANCE_SEARCHING
        }
    }

    // Deliberately no surface-hunting timeout. iOS keeps searching for as long as the reader is
    // open, and `ar_surface_not_found` is not in the method-channel contract on either platform:
    // CharacterReaderResultMapper would not recognise it, so it would reach Dart as `cancelled`,
    // reporting a failure as a deliberate user cancel. Giving up is the user's call, via Close.

    val loadedModel = modelInstance ?: return
    var viewport by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }

    ARSceneView(
        modifier = Modifier.fillMaxSize().onSizeChanged { viewport = it },
        engine = engine,
        modelLoader = modelLoader,
        materialLoader = materialLoader,
        planeRenderer = !placed,
        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL,
        sessionConfiguration = { _, config ->
            config.lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
        },
        onSessionFailed = { onFailure("ar_failed") },
        onSessionUpdated = { session, frame ->
            // Guard on the state itself rather than the `placed` snapshot captured when these
            // lambdas were composed: the library only swaps in fresh lambdas on recomposition, so
            // a second tap arriving in the same frame would otherwise place a second anchor and
            // leak the first.
            if (placedAnchor == null) {
                // Recomputed from all tracked planes each frame, not latched, so guidance reverts
                // when tracking is lost. Matches iOS.
                val guidance = if (
                    session.getAllTrackables(Plane::class.java).any { plane ->
                        plane.trackingState == TrackingState.TRACKING &&
                            plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING
                    }
                ) {
                    GUIDANCE_SURFACE_FOUND
                } else {
                    GUIDANCE_SEARCHING
                }
                if (state.guidance != guidance) {
                    state.guidance = guidance
                }

                val tapX = if (state.scannedPageMode && viewport.width > 0) viewport.width / 2f else pendingTapX
                val tapY = if (state.scannedPageMode && viewport.height > 0) viewport.height / 2f else pendingTapY
                if (tapX != null && tapY != null &&
                    (!state.scannedPageMode || frame.camera.trackingState == TrackingState.TRACKING)) {
                    // ARCore Frames are only valid inside the update callback, so the tap is
                    // recorded on the touch event and consumed here against a live frame.
                    pendingTapX = null
                    pendingTapY = null
                    val hit = frame.hitTest(tapX, tapY).firstOrNull { hitResult ->
                        val trackable = hitResult.trackable
                        trackable is Plane &&
                            trackable.trackingState == TrackingState.TRACKING &&
                            trackable.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                            trackable.isPoseInPolygon(hitResult.hitPose)
                    }
                    if (hit != null) {
                        placedAnchor = hit.createAnchor()
                        onPlaced()
                    }
                }
            }
        },
        onTouchEvent = { motionEvent, _ ->
            if (placedAnchor == null && motionEvent.actionMasked == MotionEvent.ACTION_UP) {
                pendingTapX = motionEvent.x
                pendingTapY = motionEvent.y
            }
            false
        },
    ) {
        val anchor = placedAnchor
        if (anchor != null) {
            AnchorNode(anchor = anchor) {
                ModelNode(
                    modelInstance = loadedModel,
                    autoAnimate = true,
                    scaleToUnits = MODEL_SIZE_METERS,
                    // Centred in X and Z, resting on the plane in Y.
                    centerOrigin = Float3(0.0f, -1.0f, 0.0f),
                )
            }
        }
    }
}

@Composable
private fun Overlay(
    state: ReaderUiState,
    onReadClick: () -> Unit,
    onPreviousClick: () -> Unit,
    onNextClick: () -> Unit,
    onCloseClick: () -> Unit,
    onScanNextClick: () -> Unit,
) {
    val context = LocalContext.current
    val sans = remember(context) {
        readerFont(context.assets, "NunitoSans-Regular", FontFamily.SansSerif)
    }
    val bold = remember(context) {
        readerFont(context.assets, "NunitoSans-ExtraBold", FontFamily.SansSerif)
    }
    val serif = remember(context) {
        readerFont(context.assets, "SourceSerif4-SemiBold", FontFamily.Serif)
    }
    val largeText = LocalDensity.current.fontScale >= 1.5f
    BoxWithConstraints(
        modifier = Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        val tablet = maxWidth >= 600.dp
        val dockMaxHeight = maxHeight * 0.65f
        val arrowWidth = if (tablet) 60.dp else 52.dp
        val controlHeight = if (tablet) 60.dp else 56.dp
        val showBadge = !largeText && maxWidth >= 340.dp
        Row(
            modifier = Modifier.align(Alignment.TopCenter).fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OverlayButton(
                label = "Close",
                icon = ReaderIcon.Close,
                font = bold,
                onClick = onCloseClick,
                modifier = Modifier.defaultMinSize(minHeight = 52.dp),
            )
            // Keep the exit reachable when accessibility text takes more room.
            if (showBadge) {
                Row(
                    modifier = Modifier.background(ReaderInk.copy(alpha = 0.85f), RoundedCornerShape(24.dp))
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    ReaderSymbol(ReaderIcon.Cube, ReaderPaper, Modifier.size(20.dp))
                    BasicText("STORY IN AR", style = TextStyle(
                        color = ReaderPaper, fontFamily = bold, fontSize = 14.sp,
                        fontWeight = FontWeight.Bold, letterSpacing = 0.5.sp,
                    ))
                }
            }
        }

        val surfaceFound = state.guidance == GUIDANCE_SURFACE_FOUND
        val title = when {
            state.controlsVisible -> "Story time"
            surfaceFound -> "Make room for a little magic."
            else -> "Find a spot for your story."
        }
        val guidance = when (state.guidance) {
            GUIDANCE_SURFACE_FOUND -> if (state.scannedPageMode) scanLabel("Hold still — placing your character.", "Giữ yên — đang đặt nhân vật.") else "Tap the table to place your character."
            GUIDANCE_SEARCHING -> if (state.scannedPageMode) scanLabel("Keep the page in view. Move slowly to find its surface.", "Giữ trang sách trong khung hình. Di chuyển chậm để tìm mặt phẳng.") else "Move your device slowly to find a table."
            else -> state.guidance
        }
        Column(
            modifier = Modifier.align(Alignment.BottomCenter)
                .padding(horizontal = 16.dp, vertical = if (tablet) 32.dp else 24.dp)
                .widthIn(max = 640.dp).fillMaxWidth().heightIn(max = dockMaxHeight)
                .background(ReaderPaper, RoundedCornerShape(if (tablet) 28.dp else 24.dp))
                .border(1.dp, ReaderLine, RoundedCornerShape(if (tablet) 28.dp else 24.dp))
                .pointerInput(Unit) { detectTapGestures(onTap = {}) }
                .verticalScroll(rememberScrollState())
                .padding(if (tablet) { if (state.controlsVisible) 24.dp else 28.dp } else 20.dp),
            verticalArrangement = Arrangement.spacedBy(
                if (tablet) { if (state.controlsVisible) 20.dp else 12.dp } else 16.dp,
            ),
        ) {
            if (!state.controlsVisible) {
                val caption = when (state.guidance) {
                    GUIDANCE_SURFACE_FOUND -> "TABLE FOUND"
                    GUIDANCE_SEARCHING -> "LOOKING FOR A TABLE"
                    else -> "GETTING READY"
                }
                BasicText(caption, style = TextStyle(
                    color = ReaderSage, fontFamily = bold, fontWeight = FontWeight.Bold,
                    fontSize = 14.sp, lineHeight = 20.sp, letterSpacing = 0.5.sp,
                ))
            }
            val headingStyle = TextStyle(
                color = ReaderInk, fontFamily = serif,
                fontSize = if (tablet) { if (state.controlsVisible) 28.sp else 32.sp } else 24.sp,
                lineHeight = if (tablet) { if (state.controlsVisible) 36.sp else 40.sp } else 32.sp,
            )
            val pageStyle = TextStyle(
                color = ReaderMuted, fontFamily = bold,
                fontSize = if (tablet) 16.sp else 14.sp, lineHeight = 24.sp,
            )
            if (largeText) {
                BasicText(title, style = headingStyle)
                if (state.controlsVisible && state.pageLabel.isNotEmpty()) {
                    BasicText(state.pageLabel, style = pageStyle)
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    BasicText(title, style = headingStyle, modifier = Modifier.weight(1f))
                    if (state.controlsVisible && state.pageLabel.isNotEmpty()) {
                        BasicText(state.pageLabel, style = pageStyle)
                    }
                }
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (state.speaking) SpeakingBadge()
                BasicText(guidance, style = TextStyle(
                    color = if (state.speaking) ReaderSage else ReaderMuted,
                    fontFamily = sans,
                    fontSize = if (tablet && !state.controlsVisible) 18.sp else 16.sp,
                    lineHeight = if (tablet && !state.controlsVisible) 28.sp else 24.sp,
                ), modifier = Modifier.weight(1f))
            }
            if (state.controlsVisible) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(if (tablet) 16.dp else 12.dp),
                ) {
                    if (state.pageLabel.isNotEmpty() && !state.scannedPageMode) {
                        OverlayButton(
                            label = "Previous page", icon = ReaderIcon.Previous,
                            font = bold, iconOnly = true, onClick = onPreviousClick,
                            enabled = state.canGoPrevious,
                            modifier = Modifier.size(arrowWidth, controlHeight),
                        )
                    }
                    OverlayButton(
                        label = state.readLabel,
                        icon = when (state.readLabel) {
                            "Pause" -> ReaderIcon.Pause
                            "Retry" -> ReaderIcon.Retry
                            else -> ReaderIcon.Play
                        },
                        font = bold, primary = true, onClick = onReadClick,
                        textSize = if (tablet) 18.sp else 16.sp,
                        modifier = Modifier.weight(1f).defaultMinSize(minHeight = controlHeight),
                    )
                    if (state.pageLabel.isNotEmpty() && !state.scannedPageMode) {
                        OverlayButton(
                            label = "Next page", icon = ReaderIcon.Next,
                            font = bold, iconOnly = true, onClick = onNextClick,
                            enabled = state.canGoNext,
                            modifier = Modifier.size(arrowWidth, controlHeight),
                        )
                    }
                }
            }
            if (state.scannedPageMode) {
                OverlayButton(
                    label = scanLabel("Scan next page", "Quét trang tiếp"),
                    icon = ReaderIcon.Next,
                    font = bold,
                    onClick = onScanNextClick,
                    modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = controlHeight),
                )
            }
        }
    }
}

private val ReaderPaper = Color(0xFFFFFAF4)
private val ReaderInk = Color(0xFF201A18)
private val ReaderMuted = Color(0xFF746B66)
private val ReaderLine = Color(0xFFDBD0C4)
private val ReaderCoral = Color(0xFFDC704B)
private val ReaderSage = Color(0xFF3B644C)

private fun readerFont(
    assets: android.content.res.AssetManager,
    name: String,
    fallback: FontFamily,
): FontFamily = try {
    FontFamily(Typeface(android.graphics.Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/$name.ttf")))
} catch (_: RuntimeException) {
    fallback
}

private enum class ReaderIcon { Close, Cube, Previous, Next, Play, Pause, Retry }

@Composable
private fun ReaderSymbol(icon: ReaderIcon, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val stroke = 2.dp.toPx()
        fun point(x: Float, y: Float) = Offset(size.width * x / 24, size.height * y / 24)
        fun line(x: Float, y: Float, endX: Float, endY: Float) {
            drawLine(color, point(x, y), point(endX, endY), stroke,
                cap = androidx.compose.ui.graphics.StrokeCap.Round)
        }
        when (icon) {
            ReaderIcon.Close -> { line(6f, 6f, 18f, 18f); line(18f, 6f, 6f, 18f) }
            ReaderIcon.Previous -> { line(14f, 6f, 8f, 12f); line(8f, 12f, 14f, 18f) }
            ReaderIcon.Next -> { line(10f, 6f, 16f, 12f); line(16f, 12f, 10f, 18f) }
            ReaderIcon.Pause -> { line(8f, 5f, 8f, 19f); line(16f, 5f, 16f, 19f) }
            ReaderIcon.Play -> {
                val path = Path().apply {
                    moveTo(size.width * 0.3f, size.height * 0.2f)
                    lineTo(size.width * 0.8f, size.height * 0.5f)
                    lineTo(size.width * 0.3f, size.height * 0.8f)
                    close()
                }
                drawPath(path, color)
            }
            ReaderIcon.Retry -> {
                drawArc(color, 0f, 300f, false, point(4f, 4f),
                    androidx.compose.ui.geometry.Size(size.width * 2 / 3, size.height * 2 / 3),
                    style = Stroke(stroke))
                line(20f, 3f, 20f, 9f); line(20f, 9f, 14f, 9f)
            }
            ReaderIcon.Cube -> {
                line(12f, 3f, 21f, 8f); line(21f, 8f, 21f, 17f)
                line(21f, 17f, 12f, 22f); line(12f, 22f, 3f, 17f)
                line(3f, 17f, 3f, 8f); line(3f, 8f, 12f, 3f)
                line(3f, 8f, 12f, 13f); line(12f, 13f, 21f, 8f)
                line(12f, 13f, 12f, 22f)
            }
        }
    }
}

@Composable
private fun OverlayButton(
    label: String,
    icon: ReaderIcon,
    font: FontFamily,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    primary: Boolean = false,
    iconOnly: Boolean = false,
    textSize: TextUnit = 16.sp,
) {
    val shape = RoundedCornerShape(32.dp)
    Row(
        modifier = modifier
            .background(if (primary) ReaderCoral else ReaderPaper, shape)
            .then(if (iconOnly) Modifier.border(1.dp, ReaderLine, shape) else Modifier)
            .clickable(enabled = enabled, onClick = onClick)
            .then(if (iconOnly) Modifier.semantics { contentDescription = label } else Modifier)
            .padding(horizontal = if (iconOnly) 0.dp else 18.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ReaderSymbol(icon, ReaderInk.copy(alpha = if (enabled) 1f else 0.3f), Modifier.size(if (iconOnly) 24.dp else 20.dp))
        if (!iconOnly) {
            BasicText(label, style = TextStyle(
                color = ReaderInk, fontFamily = font, fontSize = textSize,
                fontWeight = FontWeight.ExtraBold, lineHeight = 24.sp,
            ))
        }
    }
}

/** Uses the existing speaking state; no additional playback timer is needed. */
@Composable
private fun SpeakingBadge() {
    Row(
        modifier = Modifier.size(20.dp, 24.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        listOf(10.dp, 18.dp, 10.dp).forEach { barHeight ->
            Box(Modifier.size(4.dp, barHeight).background(ReaderSage, RoundedCornerShape(2.dp)))
        }
    }
}
