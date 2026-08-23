package com.storybookar.storybook_ar.characterreader

import android.view.MotionEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

    ARSceneView(
        modifier = Modifier.fillMaxSize(),
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

                val tapX = pendingTapX
                val tapY = pendingTapY
                if (tapX != null && tapY != null) {
                    // ARCore Frames are only valid inside the update callback, so the tap is
                    // recorded on the touch event and consumed here against a live frame.
                    pendingTapX = null
                    pendingTapY = null
                    val hit = frame.hitTest(tapX, tapY).firstOrNull { hitResult ->
                        val trackable = hitResult.trackable
                        trackable is Plane &&
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
) {
    Box(modifier = Modifier.fillMaxSize()) {
        OverlayButton(
            label = "Close",
            onClick = onCloseClick,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(16.dp)
                .defaultMinSize(minWidth = 88.dp, minHeight = 48.dp),
        )

        BasicText(
            text = state.guidance,
            style = TextStyle(color = Color.White, fontSize = 18.sp, textAlign = TextAlign.Center),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 24.dp, start = 120.dp, end = 16.dp)
                .background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(12.dp))
                .padding(horizontal = 16.dp, vertical = 12.dp),
        )

        if (state.controlsVisible) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (state.pageLabel.isNotEmpty()) {
                    BasicText(
                        text = state.pageLabel,
                        style = TextStyle(color = Color.White, fontSize = 15.sp),
                        modifier = Modifier
                            .padding(bottom = 10.dp)
                            .background(
                                Color.Black.copy(alpha = 0.65f),
                                RoundedCornerShape(10.dp),
                            )
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                    )
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    if (state.speaking) {
                        SpeakingBadge()
                    }
                    if (state.pageLabel.isNotEmpty()) {
                        OverlayButton(
                            label = "Back",
                            onClick = onPreviousClick,
                            enabled = state.canGoPrevious,
                            modifier = Modifier
                                .padding(end = 10.dp)
                                .defaultMinSize(minWidth = 96.dp, minHeight = 56.dp),
                        )
                    }
                    OverlayButton(
                        label = state.readLabel,
                        onClick = onReadClick,
                        modifier = Modifier.defaultMinSize(minWidth = 148.dp, minHeight = 56.dp),
                    )
                    if (state.pageLabel.isNotEmpty()) {
                        OverlayButton(
                            label = "Next",
                            onClick = onNextClick,
                            enabled = state.canGoNext,
                            modifier = Modifier
                                .padding(start = 10.dp)
                                .defaultMinSize(minWidth = 96.dp, minHeight = 56.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun OverlayButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Box(
        modifier = modifier
            .background(
                if (enabled) Color(0xFF3F51B5) else Color(0xFF3F51B5).copy(alpha = 0.35f),
                RoundedCornerShape(14.dp),
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text = label,
            style = TextStyle(
                color = if (enabled) Color.White else Color.White.copy(alpha = 0.55f),
                fontSize = 16.sp,
            ),
        )
    }
}

/**
 * Static stand-in for the animated wave bars on iOS. The indicator is present and driven by the
 * same playback state; it just does not animate.
 */
@Composable
private fun SpeakingBadge() {
    Row(
        modifier = Modifier
            .padding(end = 14.dp)
            .background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(12.dp))
            .padding(8.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        listOf(14.dp, 22.dp, 14.dp).forEach { barHeight ->
            Box(
                modifier = Modifier
                    .size(width = 6.dp, height = barHeight)
                    .background(Color.Green, RoundedCornerShape(2.dp)),
            )
        }
    }
}
