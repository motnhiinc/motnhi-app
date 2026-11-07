package com.motnhi.app.characterreader

import android.os.SystemClock
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.google.ar.core.*
import com.google.android.filament.gltfio.FilamentInstance
import com.motnhi.app.R
import com.motnhi.app.BuildConfig
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberMaterialLoader
import io.github.sceneview.rememberModelLoader
import io.github.sceneview.rememberScene
import io.github.sceneview.ar.rememberARCameraStream
import io.github.sceneview.ar.scene.PlaneRenderer
import android.util.Size

internal class ReaderUiState {
    var automaticScan by mutableStateOf(false)
    var preparingNarration by mutableStateOf(false)
    var readingComplete by mutableStateOf(false)
    var manualPlacementAvailable by mutableStateOf(false)
    var guidance by mutableStateOf(R.string.reader_preparing)
    var playbackStatus by mutableStateOf(R.string.reader_ready)
    var readLabel by mutableStateOf(R.string.reader_read)
    var controlsVisible by mutableStateOf(false)
    var speaking by mutableStateOf(false)
    var moving by mutableStateOf(false)
    var canPlace by mutableStateOf(false)
    var trackingReady by mutableStateOf(false)
    var needsReposition by mutableStateOf(false)
    var placeRequested by mutableStateOf(false)
    var pageLabel by mutableStateOf("")
    var canGoPrevious by mutableStateOf(false)
    var canGoNext by mutableStateOf(false)
    var transform by mutableStateOf(ReaderTransform())
    var listening by mutableStateOf(false)
    var voiceStatus by mutableStateOf(R.string.reader_voice_hint)
    var panel by mutableStateOf(ReaderPanel.NONE)

    val playback: ReaderPlaybackState get() = when {
        preparingNarration -> ReaderPlaybackState.PREPARING
        readingComplete -> ReaderPlaybackState.COMPLETED
        speaking -> ReaderPlaybackState.READING
        readLabel == R.string.reader_resume -> ReaderPlaybackState.PAUSED
        else -> ReaderPlaybackState.READY
    }

    fun openPanel(next: ReaderPanel, interrupt: () -> Unit) {
        interrupt()
        panel = next
    }

    fun dismissPanel() { panel = ReaderPanel.NONE }

    fun beginMove(interrupt: () -> Unit) {
        interrupt()
        dismissPanel()
        canPlace = false
        placeRequested = false
        moving = true
    }

    fun cancelMove() {
        moving = false
        placeRequested = false
    }
}

internal enum class ReaderPanel { NONE, MORE, ADJUSTMENTS, VOICE }
internal enum class ReaderPlaybackState { PREPARING, READY, READING, PAUSED, COMPLETED }

internal enum class ReaderCompletionAction { SCAN, NEXT, EXIT }
internal fun readerCompletionAction(canScan: Boolean, canGoNext: Boolean) = when {
    canScan -> ReaderCompletionAction.SCAN
    canGoNext -> ReaderCompletionAction.NEXT
    else -> ReaderCompletionAction.EXIT
}

@Composable
internal fun CharacterReaderScreen(
    state: ReaderUiState,
    modelAssetFileName: String,
    experimentalDepth: Boolean = false,
    onFailure: (String) -> Unit,
    onPlaced: () -> Unit,
    onReadClick: () -> Unit,
    onVoiceClick: () -> Unit,
    onPreviousClick: () -> Unit,
    onNextClick: () -> Unit,
    onPausePlayback: () -> Unit,
    onCloseClick: () -> Unit,
    onFrameReady: () -> Unit = {},
    onListenWithoutAr: (() -> Unit)? = null,
    onScanNextPage: (() -> Unit)? = null,
) {
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        CharacterReaderArScene(state, modelAssetFileName, experimentalDepth, onFailure, onPlaced, onPausePlayback, onFrameReady)
        if (!state.controlsVisible || state.moving) {
            // Same full-viewport center as the AR hit test, independent of asymmetric insets.
            Box(Modifier.align(Alignment.Center).size(28.dp)
                .border(3.dp, if (state.canPlace) Color.Green else Color.White, CircleShape))
        }
        ReaderOverlay(state, onReadClick, onVoiceClick, onPreviousClick, onNextClick, onPausePlayback, onCloseClick, onListenWithoutAr, onScanNextPage)
    }
}

@Composable
private fun CharacterReaderArScene(
    state: ReaderUiState,
    modelAssetFileName: String,
    experimentalDepth: Boolean,
    onFailure: (String) -> Unit,
    onPlaced: () -> Unit,
    onPausePlayback: () -> Unit,
    onFrameReady: () -> Unit,
) {
    val engine = rememberEngine()
    val modelLoader = rememberModelLoader(engine)
    val materialLoader = rememberMaterialLoader(engine)
    val scene = rememberScene(engine)
    val cameraStream = rememberARCameraStream(materialLoader)
    // Own exactly one supported V1 receiver. Built-in renderer below is disabled to avoid
    // duplicate grids/shadows. Visibility and shadow receiving are independent in 4.18.
    val planes = remember(engine, materialLoader, scene) { PlaneRenderer(engine, materialLoader, scene) }
    val sceneStarted = remember { SystemClock.elapsedRealtime() }
    val diagnostics = remember { ReaderDiagnostics(sceneStarted) }
    fun mark(name: String) {
        if (diagnostics.mark(name, SystemClock.elapsedRealtime())) {
            android.util.Log.i("ReaderAR", "$name=${diagnostics.elapsed(name)}ms")
        }
    }
    var depthSupported by remember { mutableStateOf<Boolean?>(null) }
    // Occlusion experiments also need sensing. Production can place using measured planes
    // and motion/stability evidence without generating depth images.
    val depthRequested = BuildConfig.READER_DEPTH_ENABLED || experimentalDepth
    val requestedDepthMode = if (ReaderDepthPolicy.requestAutomatic(depthRequested, depthSupported))
        Config.DepthMode.AUTOMATIC else Config.DepthMode.DISABLED
    val observedDepthMode = remember { arrayOfNulls<Config.DepthMode>(1) }
    DisposableEffect(planes) { onDispose {
        planes.destroy()
        android.util.Log.i("ReaderAR", "timings modelReady=${diagnostics.elapsed("modelReady")} firstFrame=${diagnostics.elapsed("firstFrame")} validPlacement=${diagnostics.elapsed("validPlacement")} placedFrame=${diagnostics.elapsed("placedFrame")} validDepth=${diagnostics.elapsed("validDepth")}")
    } }
    val placement = remember { PlacementTransaction<Anchor>() }
    val tracking = remember { TrackingLossDebouncer() }
    val surfaceStability = remember { ReaderSurfaceStability<Plane>() }
    val surfaceVerification = remember { ReaderSurfaceVerification<Plane>() }
    val depthStability = remember { ReaderSurfaceStability<Plane>(settleMillis = 350L) }
    val depthSampler = remember { ReaderDepthSampler() }
    val contactLoss = remember { TrackingLossDebouncer(700L) }
    var supportingPlane by remember { mutableStateOf<Plane?>(null) }
    var anchor by remember { mutableStateOf<Anchor?>(null) }
    var initialAnchor by remember { mutableStateOf<Anchor?>(null) }
    var anchorNode by remember { mutableStateOf<io.github.sceneview.ar.node.AnchorNode?>(null) }
    var yaw by remember { mutableStateOf(0f) }
    var size by remember { mutableStateOf(IntSize.Zero) }
    var model by remember { mutableStateOf<FilamentInstance?>(null) }
    var geometry by remember { mutableStateOf<ReaderModelGeometry?>(null) }
    var preview by remember { mutableStateOf<Pose?>(null) }
    val footprintMaterial = remember(materialLoader) {
        materialLoader.createColorInstance(Color(0xFF66BB6A))
    }
    val checkingMaterial = remember(materialLoader) {
        materialLoader.createColorInstance(Color(0xFFFFCA28))
    }
    // AnchorNode owns detach on replacement/disposal. Keep the node itself stable across moves:
    // replacing its composable would recursively destroy the still-reused model's entities.
    LaunchedEffect(modelAssetFileName) {
        state.guidance = R.string.reader_loading
        model = runCatching { modelLoader.loadModelInstance(modelAssetFileName) }.getOrNull()
        geometry = model?.asset?.boundingBox?.let { bounds ->
            runCatching { ReaderModelGeometry.fromBounds(bounds.center, bounds.halfExtent) }.getOrNull()
        }
        if (model == null || geometry == null) onFailure("model_load_failed")
        else {
            android.util.Log.i("ReaderAR", "model=$modelAssetFileName geometry=$geometry")
            mark("modelReady")
            state.guidance = R.string.reader_searching
        }
    }
    val loadedModel = model
    val modelGeometry = geometry
    val footprintRadius = (modelGeometry?.footprintRadius ?: 0.175f) * state.transform.scale
    val animationNames = remember(loadedModel) {
        (0 until (loadedModel?.animator?.animationCount ?: 0)).map {
            requireNotNull(loadedModel)
            loadedModel.animator.getAnimationName(it)
        }.toSet()
    }
    ARSceneView(
        modifier = Modifier.fillMaxSize().onSizeChanged { size = it }
            .pointerInput(state.controlsVisible, state.moving, state.trackingReady) {
                detectTransformGestures { _, _, zoom, rotation ->
                    // No tap-to-place, translation, pitch or roll. Sibling overlay buttons win
                    // hit testing; only two-finger zoom/twist changes this foot-pivot transform.
                    if (state.controlsVisible && !state.moving && state.trackingReady) {
                        state.transform = state.transform.adjust(zoom, rotation)
                    }
                }
            },
        engine = engine,
        scene = scene,
        cameraStream = cameraStream,
        modelLoader = modelLoader,
        materialLoader = materialLoader,
        planeRenderer = false,
        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL,
        // Accuracy over speed: never invent a depth while ARCore is finding the floor.
        instantPlacementMode = Config.InstantPlacementMode.DISABLED,
        depthMode = requestedDepthMode,
        sessionConfiguration = { session, config ->
            // Ambient is the lightweight baseline. HDR remains independently selectable
            // for release-device comparisons, including its main-light and IBL updates.
            config.lightEstimationMode = if (BuildConfig.READER_HDR_ENABLED)
                Config.LightEstimationMode.ENVIRONMENTAL_HDR else Config.LightEstimationMode.AMBIENT_INTENSITY
            config.focusMode = Config.FocusMode.AUTO
            val supported = session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
            depthSupported = supported
            // Start disabled until capability is known. Recomposition then updates the typed
            // parameter, whose 4.18 LaunchedEffect owns reactive session reconfiguration.
            // Do not independently set AUTOMATIC here: an older typed value would undo it.
            config.depthMode = if (supported) requestedDepthMode else Config.DepthMode.DISABLED
            android.util.Log.i("ReaderAR", "depth supported=$depthSupported configured=${config.depthMode} occlusion=$experimentalDepth")
        },
        onSessionFailed = { onFailure("ar_failed") },
        onSessionUpdated = { session, frame ->
            state.manualPlacementAvailable = SystemClock.elapsedRealtime() - sceneStarted >= 8000
            val effectiveDepthMode = session.config.depthMode
            if (observedDepthMode[0] != effectiveDepthMode) {
                observedDepthMode[0] = effectiveDepthMode
                android.util.Log.i("ReaderAR", "observedDepth=$effectiveDepthMode requested=$requestedDepthMode supported=$depthSupported")
            }
            if (diagnostics.elapsed("firstFrame") == null) {
                android.util.Log.i("ReaderAR", "hdr=${session.config.lightEstimationMode} shadows=V1")
                mark("firstFrame")
            }
            val cameraTracked = frame.camera.trackingState == TrackingState.TRACKING
            if (anchor != null) mark("placedFrame")
            if (size.width > 0 && size.height > 0) {
                planes.viewSize = Size(size.width, size.height)
                planes.isVisible = anchor == null || state.moving
                planes.isShadowReceiver = true
                planes.update(session, frame)
            }
            // SceneView uploads depth before this callback. Validate this live image before
            // drawing; on first enable upload once more so no uninitialised texture is used.
            val configured = effectiveDepthMode == Config.DepthMode.AUTOMATIC
            val validDepth = if (experimentalDepth && depthSupported == true && configured && cameraTracked) {
                runCatching { frame.acquireDepthImage16Bits().use { image ->
                    val plane = image.planes[0]
                    val buffer = plane.buffer
                    // Cheap centre-region samples reject empty depth; no scan/allocation/log per frame.
                    val fresh = image.timestamp > 0 && frame.timestamp >= image.timestamp &&
                        frame.timestamp - image.timestamp <= 250_000_000L
                    fresh && (1..3).any { y -> (1..3).any { x ->
                        val index = (image.height * y / 4) * plane.rowStride +
                            (image.width * x / 4) * plane.pixelStride
                        index + 1 < buffer.limit() &&
                            ((buffer.get(index).toInt() and 255) or
                                ((buffer.get(index + 1).toInt() and 255) shl 8)) > 0
                    } }
                } }.getOrDefault(false)
            } else false
            val occlude = ReaderDepthPolicy.enable(experimentalDepth, depthSupported == true, configured,
                cameraTracked, validDepth)
            val enabling = occlude && !cameraStream.isDepthOcclusionEnabled
            cameraStream.isDepthOcclusionEnabled = occlude
            if (enabling) cameraStream.update(session, frame)
            if (occlude) mark("validDepth")
            // Follow plane merges. An anchor can keep TRACKING even after its supporting
            // surface has been refined away from the feet, so anchor tracking alone is insufficient.
            var support = supportingPlane
            while (support?.subsumedBy != null) support = support.subsumedBy
            supportingPlane = support
            val placed = anchor
            val contactValid = placed == null || (support != null &&
                ReaderPlacementGeometry.supportedContact(
                    support.trackingState == TrackingState.TRACKING,
                    support.isPoseInPolygon(placed.pose),
                    support.centerPose.inverse().compose(placed.pose).ty()))
            val tracked = cameraTracked && (placed == null || placed.trackingState == TrackingState.TRACKING)
            state.trackingReady = tracked && contactValid
            val trackingLost = tracking.update(tracked, SystemClock.elapsedRealtime())
            val contactLost = contactLoss.update(placed == null || !cameraTracked || contactValid,
                SystemClock.elapsedRealtime())
            val anchorStopped = anchor?.trackingState == TrackingState.STOPPED
            val previouslyLost = state.needsReposition
            state.needsReposition = anchor != null && (trackingLost || anchorStopped || contactLost ||
                (previouslyLost && !state.trackingReady))
            // A brief pause retains the pose. Once it is unreliable, explain the loss rather
            // than displaying a guessed world position or silently creating a replacement anchor.
            anchorNode?.isVisible = !state.needsReposition
            if (state.needsReposition && !previouslyLost) onPausePlayback()
            if (!cameraTracked || trackingLost || anchorStopped) {
                state.guidance = when (frame.camera.trackingFailureReason) {
                    TrackingFailureReason.INSUFFICIENT_LIGHT -> R.string.reader_light
                    TrackingFailureReason.EXCESSIVE_MOTION -> R.string.reader_slow
                    else -> R.string.reader_recover
                }
            } else if (contactLost && !state.moving) {
                state.guidance = R.string.reader_contact_lost
            } else if (tracked && anchor != null && !state.moving) {
                state.guidance = R.string.reader_ready
            }
            if (state.moving) placement.beginMove() else placement.cancel()
            if (anchor == null || state.moving) {
                val nearestSurface = if (cameraTracked && size.width > 0 && size.height > 0) {
                    frame.hitTest(size.width / 2f, size.height / 2f).firstOrNull { result ->
                        val plane = result.trackable as? Plane
                        plane != null && ReaderPresentationPolicy.canPlace(
                            cameraTracked,
                            plane.trackingState == TrackingState.TRACKING,
                            plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING,
                            plane.isPoseInPolygon(result.hitPose),
                        ) && plane.subsumedBy == null
                    }
                } else null
                // Never look through a small/unsuitable foreground surface to a farther plane.
                val inRange = nearestSurface != null && nearestSurface.distance in 0.25f..3.0f
                val lookingDown = nearestSurface != null &&
                    (frame.camera.pose.ty() - nearestSurface.hitPose.ty()) / nearestSurface.distance >= 0.25f
                val hasRoom = nearestSurface != null && footprintFits(nearestSurface.trackable as Plane,
                    nearestSurface.hitPose, footprintRadius)
                val hit = nearestSurface?.takeIf { inRange && lookingDown && hasRoom }
                val measuredDepth = if (hit != null && configured && cameraTracked) {
                    depthSampler.sample(frame, size.width / 2f, size.height / 2f)
                } else null
                val agreement = ReaderPlacementGeometry.depthAgreement(
                    hit?.let { -frame.camera.pose.inverse().compose(it.hitPose).tz() } ?: 0f,
                    measuredDepth)
                if (agreement == ReaderDepthAgreement.CONFLICT) {
                    surfaceStability.reset()
                    surfaceVerification.reset()
                }
                val pose = hit?.hitPose
                val surfaceVerified = surfaceVerification.update(hit?.trackable as? Plane,
                    pose?.ty() ?: 0f, frame.camera.pose.tx(), frame.camera.pose.tz(),
                    frame.timestamp / 1_000_000)
                val targetSettled = surfaceStability.update(hit?.trackable as? Plane,
                    pose?.tx() ?: 0f, pose?.ty() ?: 0f, pose?.tz() ?: 0f, frame.timestamp / 1_000_000)
                // A single matching depth frame must not trigger automatic placement.
                val depthSettled = depthStability.update(
                    (hit?.trackable as? Plane).takeIf { agreement == ReaderDepthAgreement.MATCH },
                    pose?.tx() ?: 0f, pose?.ty() ?: 0f, pose?.tz() ?: 0f, frame.timestamp / 1_000_000)
                state.canPlace = surfaceVerified && targetSettled && modelGeometry != null &&
                    agreement != ReaderDepthAgreement.CONFLICT
                if (state.canPlace) mark("validPlacement")
                // The center hit, footprint and eventual anchor are identical (no lagging smoothed
                // pose that would make the visible preview differ from the committed placement).
                preview = hit?.hitPose
                if (cameraTracked) {
                    state.guidance = when {
                        nearestSurface == null -> R.string.reader_searching
                        !inRange -> R.string.reader_distance
                        !lookingDown -> R.string.reader_aim_down
                        !hasRoom -> R.string.reader_more_room
                        agreement == ReaderDepthAgreement.CONFLICT -> R.string.reader_depth_conflict
                        !surfaceVerified -> R.string.reader_verify_surface
                        !state.canPlace -> R.string.reader_surface_settling
                        state.automaticScan && !state.moving && depthSupported != false &&
                            !depthSettled -> R.string.reader_depth_waiting
                        else -> R.string.reader_surface
                    }
                }
                val autoPlace = ReaderPlacementGeometry.automaticPlacement(state.automaticScan,
                    state.moving, state.canPlace, depthSupported,
                    if (depthSettled) agreement else ReaderDepthAgreement.UNAVAILABLE,
                    requireDepth = depthRequested)
                if (state.placeRequested || autoPlace) {
                    state.placeRequested = false
                    // Consume only this live frame's validated hit, never a retained HitResult.
                    if (hit != null && state.canPlace && loadedModel != null) {
                        val next = runCatching { hit.createAnchor() }.getOrNull()
                        if (next != null) {
                            val localCamera = next.pose.inverse().transformPoint(frame.camera.pose.translation)
                            val previousAnchor = anchor
                            yaw = if (previousAnchor == null) {
                                ReaderPresentationPolicy.viewerYawDegrees(localCamera[0], localCamera[2],
                                    ReaderPresentationPolicy.forwardOffsetDegrees(modelAssetFileName))
                            } else {
                                // Preserve world heading when two horizontal planes use different
                                // local coordinate frames; retain the user's relative yaw and scale.
                                val radians = Math.toRadians(yaw.toDouble())
                                val forward = floatArrayOf(kotlin.math.sin(radians).toFloat(), 0f,
                                    kotlin.math.cos(radians).toFloat())
                                val nextForward = next.pose.inverse().rotateVector(
                                    previousAnchor.pose.rotateVector(forward))
                                ReaderPresentationPolicy.viewerYawDegrees(nextForward[0], nextForward[2])
                            }
                            placement.confirm(next)
                            val existingNode = anchorNode
                            if (existingNode != null) existingNode.anchor = next
                            else initialAnchor = next
                             anchor = next
                             supportingPlane = hit.trackable as Plane
                             contactLoss.update(true, SystemClock.elapsedRealtime())
                             android.util.Log.i("ReaderAR", "placed distance=${hit.distance} depth=$agreement automatic=$autoPlace footprint=$footprintRadius")
                            state.moving = false
                            state.needsReposition = false
                             surfaceStability.reset()
                             surfaceVerification.reset()
                             depthStability.reset()
                            preview = null
                            onPlaced()
                        }
                    }
                }
            } else {
                surfaceStability.reset()
                surfaceVerification.reset()
                depthStability.reset()
                preview = null
                state.canPlace = false
            }
            onFrameReady()
        },
    ) {
        val committed = initialAnchor
        if (committed != null && loadedModel != null && modelGeometry != null) {
            AnchorNode(anchor = committed,
                visibleTrackingStates = setOf(TrackingState.TRACKING, TrackingState.PAUSED),
                apply = {
                    isEditable = false
                    // SceneView defaults to TRACKING only, causing immediate disappearance on
                    // PAUSED. It already retains the last pose until tracking resumes.
                    visibleCameraTrackingStates = setOf(TrackingState.TRACKING, TrackingState.PAUSED)
                    anchorNode = this
                }) {
                // Transform the model AND its foot offset together; scaling preserves contact.
                Node(scale = Float3(state.transform.scale),
                    rotation = Float3(0f, yaw + state.transform.yaw, 0f),
                    isVisible = !state.needsReposition) {
                    ModelNode(
                        modelInstance = loadedModel,
                        autoAnimate = false,
                        animationName = ReaderPresentationPolicy.animationName(state.speaking, animationNames),
                        // SceneView 4.18 centerOrigin uses origin * size, ignoring the asset
                        // bounds' center/minimum. Compute the actual bottom-center explicitly.
                        scale = Float3(modelGeometry.scale),
                        position = Float3(modelGeometry.x, modelGeometry.y, modelGeometry.z),
                    )
                }
            }
        }
        ReaderPresentationPolicy.visiblePreview(anchor != null, state.moving, preview)?.let { pose ->
            PoseNode(pose = pose) {
                CylinderNode(radius = footprintRadius, height = 0.002f,
                    position = Float3(0f, 0.002f, 0f),
                    materialInstance = if (state.canPlace) footprintMaterial else checkingMaterial)
            }
        }
    }
}

/** All four corners of the conservative character footprint must be on the measured plane. */
private fun footprintFits(plane: Plane, pose: Pose, radius: Float): Boolean =
    listOf(-radius, radius).all { x -> listOf(-radius, radius).all { z ->
        plane.isPoseInPolygon(pose.compose(Pose.makeTranslation(x, 0f, z)))
    } }
