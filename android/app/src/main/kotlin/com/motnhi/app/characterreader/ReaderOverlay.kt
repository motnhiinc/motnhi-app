package com.motnhi.app.characterreader

import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.motnhi.app.R
import java.util.Locale

/** Approved Paper values, translated from CSS px to density-independent Compose units. */
private val Paper = Color(0xFFF7F5EF)
private val Ink = Color(0xFF202D29)
private val Moss = Color(0xFF557365)
private val Muted = Color(0xFF66716B)
private val Sage = Color(0xFFDCE6DD)
private val Divider = Color(0xFFDCE0D8)
private val ReaderFont = FontFamily(
    Font(R.font.reader_inter_regular, FontWeight.Normal),
    Font(R.font.reader_inter_medium, FontWeight.Medium),
    Font(R.font.reader_inter_semibold, FontWeight.SemiBold),
)

@Composable
internal fun ReaderOverlay(
    state: ReaderUiState,
    onReadClick: () -> Unit,
    onVoiceClick: () -> Unit,
    onPreviousClick: () -> Unit,
    onNextClick: () -> Unit,
    onInterrupt: () -> Unit,
    onCloseClick: () -> Unit,
    onListenWithoutAr: (() -> Unit)?,
    onScanNextPage: (() -> Unit)?,
) {
    fun dismissVoice() { onInterrupt(); state.dismissPanel() }
    BackHandler(state.moving || state.panel == ReaderPanel.VOICE) {
        if (state.panel == ReaderPanel.VOICE) dismissVoice() else state.cancelMove()
    }
    BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
        // Keep the header and dock in separate vertical lanes, even in landscape / large text.
        Column(Modifier.fillMaxSize()) {
            SessionHeader(onCloseClick, { state.openPanel(ReaderPanel.MORE, onInterrupt) })
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    .widthIn(max = 520.dp).fillMaxWidth().verticalScroll(rememberScrollState())
                    .clip(RoundedCornerShape(28.dp)).background(Paper)
                    .border(1.dp, Color.White, RoundedCornerShape(28.dp))
                    .padding(start = 22.dp, top = 22.dp, end = 22.dp,
                        bottom = if (state.readingComplete && state.panel != ReaderPanel.VOICE) 12.dp else 22.dp),
                    verticalArrangement = Arrangement.spacedBy(
                        if (state.panel == ReaderPanel.VOICE || state.readingComplete) 14.dp else 18.dp)) {
                    when {
                        state.panel == ReaderPanel.VOICE -> ListeningDock(state, onVoiceClick, ::dismissVoice)
                        !state.controlsVisible || state.moving -> PlacementDock(state)
                        state.needsReposition -> {
                            Eyebrow(R.string.reader_tracking_lost)
                            ReaderText(stringResource(state.guidance), size = 16)
                            ReaderAction(R.string.reader_find_surface, { state.beginMove(onInterrupt) }, icon = ReaderIcon.MOVE)
                        }
                        state.playback == ReaderPlaybackState.PREPARING -> {
                            Eyebrow(R.string.reader_story_time)
                            DockTitle(R.string.reader_preparing_story)
                            ReaderText(stringResource(R.string.reader_preparing_hint), color = Muted)
                            ReadingActions(state, onReadClick, onVoiceClick, enabled = false)
                        }
                        state.playback == ReaderPlaybackState.COMPLETED -> CompletionDock(
                            state, onReadClick, onNextClick, onCloseClick, onScanNextPage)
                        else -> ReadingDock(state, onReadClick, onVoiceClick)
                    }
                    if ((!state.controlsVisible || state.moving) && state.preparingNarration) {
                        ReaderText(stringResource(R.string.reader_preparing_story), color = Muted)
                    }
                }
            }
        }
    }
    if (state.panel == ReaderPanel.MORE || state.panel == ReaderPanel.ADJUSTMENTS) {
        ControlsSheet(state, onPreviousClick, onNextClick, onInterrupt, onListenWithoutAr)
    }
}

@Composable
private fun SessionHeader(onClose: () -> Unit, onMore: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        HeaderAction(R.string.reader_close, ReaderIcon.CLOSE, onClose)
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Row(Modifier.clip(RoundedCornerShape(24.dp)).background(Ink.copy(alpha = 0.8f))
                .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(6.dp).background(Color(0xFFC6DFC2), CircleShape))
                ReaderText(stringResource(R.string.reader_story_time), size = 14, color = Color.White, weight = FontWeight.Medium)
            }
        }
        HeaderAction(R.string.reader_more, ReaderIcon.MORE, onMore)
    }
}

@Composable
private fun HeaderAction(@StringRes label: Int, icon: ReaderIcon, onClick: () -> Unit) {
    val description = stringResource(label)
    Box(Modifier.size(48.dp).clip(CircleShape).background(Ink.copy(alpha = 0.8f))
        .clickable(role = Role.Button, onClick = onClick).semantics { contentDescription = description },
        contentAlignment = Alignment.Center) { ReaderGlyph(icon, Color.White) }
}

@Composable
private fun ReadingDock(state: ReaderUiState, onRead: () -> Unit, onVoice: () -> Unit) {
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Eyebrow(when (state.playback) {
            ReaderPlaybackState.READING -> R.string.reader_speaking
            ReaderPlaybackState.PAUSED -> R.string.reader_paused_short
            else -> R.string.reader_ready_short
        })
        if (state.pageLabel.isNotEmpty()) ReaderText(state.pageLabel, size = 14, color = Muted)
    }
    DockTitle(R.string.reader_story_time, compact = true)
    if (state.readLabel == R.string.reader_retry) ReaderText(stringResource(state.playbackStatus), color = Muted)
    ReadingActions(state, onRead, onVoice)
}

@Composable
private fun ReadingActions(state: ReaderUiState, onRead: () -> Unit, onVoice: () -> Unit, enabled: Boolean = true) {
    // The same weighted slots are retained for Read / Pause / Resume. Large text stacks instead of clipping.
    val stack = LocalDensity.current.fontScale > 1.3f
    @Composable fun Actions(modifier: Modifier) {
        ReaderAction(state.readLabel, onRead, enabled && !state.listening &&
            ReaderPlaybackPolicy.controlEnabled(state.speaking, state.trackingReady), modifier,
            icon = if (state.speaking) ReaderIcon.PAUSE else ReaderIcon.PLAY)
        ReaderAction(R.string.reader_talk_short, onVoice, enabled, modifier, secondary = true, icon = ReaderIcon.MIC)
    }
    if (stack) Column(verticalArrangement = Arrangement.spacedBy(12.dp)) { Actions(Modifier.fillMaxWidth()) }
    else Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        ReaderAction(state.readLabel, onRead, enabled && !state.listening &&
            ReaderPlaybackPolicy.controlEnabled(state.speaking, state.trackingReady), Modifier.weight(1f),
            icon = if (state.speaking) ReaderIcon.PAUSE else ReaderIcon.PLAY)
        ReaderAction(R.string.reader_talk_short, onVoice, enabled, Modifier.width(96.dp),
            secondary = true, icon = ReaderIcon.MIC)
    }
}

@Composable
private fun ColumnScope.PlacementDock(state: ReaderUiState) {
    Eyebrow(if (state.moving) R.string.reader_move else R.string.reader_story_time)
    ReaderText(stringResource(state.guidance), size = 16)
    if (!state.automaticScan || state.moving || state.manualPlacementAvailable || state.canPlace) {
        ReaderAction(R.string.reader_place, { state.placeRequested = true }, state.canPlace, icon = ReaderIcon.MOVE)
    }
    if (state.moving) ReaderAction(R.string.reader_cancel_move, state::cancelMove, secondary = true, icon = ReaderIcon.CLOSE)
}

@Composable
private fun ColumnScope.ListeningDock(state: ReaderUiState, onRetry: () -> Unit, onCancel: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Eyebrow(if (state.listening) R.string.reader_listening else R.string.reader_voice_title)
        ReaderGlyph(ReaderIcon.WAVE, Moss)
    }
    DockTitle(R.string.reader_voice_question)
    ReaderText(stringResource(if (state.listening) R.string.reader_listening_hint else state.voiceStatus), color = Muted,
        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
    if (!state.listening) ReaderAction(R.string.reader_voice_try_again, onRetry, secondary = true, icon = ReaderIcon.MIC)
    ReaderAction(if (state.listening) R.string.reader_cancel_listening else R.string.reader_done,
        onCancel, secondary = true, icon = ReaderIcon.CLOSE)
}

@Composable
private fun ColumnScope.CompletionDock(
    state: ReaderUiState, onReplay: () -> Unit, onNext: () -> Unit, onExit: () -> Unit, onScan: (() -> Unit)?,
) {
    val action = readerCompletionAction(onScan != null, state.canGoNext)
    Eyebrow(if (action == ReaderCompletionAction.EXIT) R.string.reader_complete else R.string.reader_page_finished_short)
    DockTitle(if (action == ReaderCompletionAction.EXIT) R.string.reader_story_finished else R.string.reader_one_more_page)
    if (state.pageLabel.isNotEmpty()) ReaderText(state.pageLabel, size = 14, color = Muted)
    when (action) {
        ReaderCompletionAction.SCAN -> ReaderAction(R.string.reader_scan_next_page, { onScan?.invoke() }, icon = ReaderIcon.SCAN)
        ReaderCompletionAction.NEXT -> ReaderAction(R.string.reader_next_page, onNext, icon = ReaderIcon.NEXT)
        ReaderCompletionAction.EXIT -> ReaderAction(R.string.reader_read_again, onReplay,
            enabled = state.trackingReady, icon = ReaderIcon.REPLAY)
    }
    ReaderAction(if (action == ReaderCompletionAction.EXIT) R.string.reader_exit else R.string.reader_replay_page,
        if (action == ReaderCompletionAction.EXIT) onExit else onReplay,
        enabled = action == ReaderCompletionAction.EXIT || state.trackingReady, textOnly = true, icon =
            if (action == ReaderCompletionAction.EXIT) ReaderIcon.CLOSE else ReaderIcon.REPLAY)
}

@Composable
private fun ControlsSheet(
    state: ReaderUiState, onPrevious: () -> Unit, onNext: () -> Unit,
    onInterrupt: () -> Unit, onListenWithoutAr: (() -> Unit)?,
) {
    fun back() {
        if (state.panel == ReaderPanel.ADJUSTMENTS) state.panel = ReaderPanel.MORE else state.dismissPanel()
    }
    Dialog(onDismissRequest = ::back, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect { window?.setDimAmount(0f) }
        BoxWithConstraints(Modifier.fillMaxSize().background(Color(0x6614211D)).safeDrawingPadding()) {
            // Dialog provides modal accessibility focus and Back/outside dismissal, unlike an inline overlay.
            Box(Modifier.fillMaxSize().clickable(indication = null,
                interactionSource = null, onClick = ::back).clearAndSetSemantics {})
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().heightIn(max = maxHeight * 0.92f)
                .clip(RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp)).background(Paper)
                .verticalScroll(rememberScrollState()).padding(horizontal = 24.dp)
                .padding(top = 12.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.align(Alignment.CenterHorizontally).size(36.dp, 4.dp)
                    .background(Color(0xFFC7CDC7), RoundedCornerShape(2.dp)))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ReaderText(stringResource(if (state.panel == ReaderPanel.MORE) R.string.reader_controls_title else R.string.reader_adjust_title),
                        size = 24, weight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    ReaderAction(R.string.reader_done, state::dismissPanel, modifier = Modifier.widthIn(min = 56.dp), textOnly = true)
                }
                ReaderText(stringResource(when (state.playback) {
                    ReaderPlaybackState.COMPLETED -> R.string.reader_complete
                    ReaderPlaybackState.PREPARING -> R.string.reader_preparing_story
                    else -> R.string.reader_sheet_paused
                }), size = 14, color = Muted)
                if (state.panel == ReaderPanel.MORE) {
                    if (state.pageLabel.isNotEmpty()) {
                        ReaderText(state.pageLabel, size = 14, color = Muted, modifier = Modifier.padding(top = 12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            ReaderAction(R.string.reader_back, onPrevious,
                                state.canGoPrevious && state.controlsVisible && !state.moving, Modifier.weight(1f), outlined = true)
                            ReaderAction(R.string.reader_next, onNext,
                                state.canGoNext && state.controlsVisible && !state.moving, Modifier.weight(1f), outlined = true)
                        }
                    }
                    SheetRow(R.string.reader_move_buddy, R.string.reader_move_hint, ReaderIcon.MOVE,
                        state.controlsVisible && !state.moving) { state.beginMove(onInterrupt) }
                    SheetRow(R.string.reader_adjust_title, R.string.reader_adjust_hint, ReaderIcon.SCAN,
                        state.controlsVisible && !state.moving) { state.panel = ReaderPanel.ADJUSTMENTS }
                    if (onListenWithoutAr != null) SheetRow(R.string.reader_listen_without_ar,
                        R.string.reader_audio_only_hint, ReaderIcon.HEADPHONES, true, onListenWithoutAr)
                } else {
                    ReaderText(stringResource(if (state.trackingReady) R.string.reader_gesture_hint else R.string.reader_adjust_tracking), color = Muted)
                    val enabled = state.trackingReady && state.controlsVisible && !state.moving
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        ReaderAction(R.string.reader_smaller, { state.transform = state.transform.adjust(0.9f, 0f) },
                            enabled && state.transform.scale > 0.5f, Modifier.weight(1f), secondary = true)
                        ReaderAction(R.string.reader_larger, { state.transform = state.transform.adjust(1.1f, 0f) },
                            enabled && state.transform.scale < 1.5f, Modifier.weight(1f), secondary = true)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        ReaderAction(R.string.reader_rotate_left, { state.transform = state.transform.adjust(1f, -15f) },
                            enabled, Modifier.weight(1f), secondary = true)
                        ReaderAction(R.string.reader_rotate_right, { state.transform = state.transform.adjust(1f, 15f) },
                            enabled, Modifier.weight(1f), secondary = true)
                    }
                    ReaderAction(R.string.reader_reset_transform, { state.transform = ReaderTransform() }, enabled, secondary = true)
                    ReaderAction(R.string.reader_controls_back, { state.panel = ReaderPanel.MORE }, textOnly = true)
                }
            }
        }
    }
}

@Composable
private fun SheetRow(@StringRes title: Int, @StringRes hint: Int, icon: ReaderIcon, enabled: Boolean, onClick: () -> Unit) {
    Column {
        Row(Modifier.fillMaxWidth().clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .heightIn(min = 76.dp).padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(28.dp)) { ReaderGlyph(icon, if (enabled) Moss else Muted) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                ReaderText(stringResource(title), size = 16, weight = FontWeight.Medium, color = if (enabled) Ink else Muted)
                ReaderText(stringResource(hint), size = 13, color = Muted)
            }
            Box(Modifier.width(20.dp)) { ReaderGlyph(ReaderIcon.NEXT, Muted) }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(Divider))
    }
}

@Composable
private fun Eyebrow(@StringRes label: Int) {
    BasicText(stringResource(label).uppercase(Locale.getDefault()), style = TextStyle(color = Moss, fontFamily = ReaderFont,
        fontSize = 13.sp, lineHeight = 16.sp, letterSpacing = 1.04.sp, fontWeight = FontWeight.SemiBold),
        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
}

@Composable
private fun DockTitle(@StringRes label: Int, compact: Boolean = false) {
    ReaderText(stringResource(label), size = if (compact) 22 else 24, weight = FontWeight.SemiBold,
        modifier = Modifier.semantics { heading() })
}

@Composable
private fun ReaderText(text: String, modifier: Modifier = Modifier, size: Int = 15,
    color: Color = Ink, weight: FontWeight = FontWeight.Normal) {
    BasicText(text, modifier, style = TextStyle(color = color, fontFamily = ReaderFont,
        fontWeight = weight, fontSize = size.sp, lineHeight = (if (size >= 22) size + 6 else size + 5).sp,
        letterSpacing = if (size >= 22) (-0.035 * size).sp else 0.sp))
}

@Composable
private fun ReaderAction(
    @StringRes label: Int, onClick: () -> Unit, enabled: Boolean = true, modifier: Modifier = Modifier.fillMaxWidth(),
    secondary: Boolean = false, textOnly: Boolean = false, icon: ReaderIcon? = null, outlined: Boolean = false,
) {
    val background = if (textOnly || outlined) Color.Transparent else if (secondary) Sage else Ink
    val foreground = if (textOnly) Moss else if (secondary || outlined) Ink else Color.White
    val shape = RoundedCornerShape(if (outlined) 14.dp else 18.dp)
    Row(modifier.defaultMinSize(minWidth = 48.dp, minHeight = if (textOnly || outlined) 48.dp else 56.dp)
        .clip(shape).background(if (enabled || outlined) background else Divider)
        .then(if (outlined) Modifier.border(1.dp, Color(0xFFCCD3CA), shape) else Modifier)
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
        .padding(horizontal = 12.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) ReaderGlyph(icon, if (enabled) foreground else Muted)
        BasicText(stringResource(label), style = TextStyle(color = if (enabled) foreground else Muted,
            fontSize = 16.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
            modifier = androidx.compose.ui.Modifier.weight(1f, fill = false))
    }
}

private enum class ReaderIcon { CLOSE, MORE, PLAY, PAUSE, MIC, WAVE, MOVE, SCAN, REPLAY, NEXT, HEADPHONES }

/** Decorative vector strokes; the surrounding action supplies the localized accessible name. */
@Composable
private fun ReaderGlyph(icon: ReaderIcon, color: Color) {
    Canvas(Modifier.size(if (icon == ReaderIcon.WAVE) 58.dp else 20.dp, 24.dp)) {
        scale(size.width / 24f, size.height / 24f, pivot = Offset.Zero) {
            fun line(x1: Float, y1: Float, x2: Float, y2: Float) =
                drawLine(color, Offset(x1, y1), Offset(x2, y2), strokeWidth = 1.8f, cap = StrokeCap.Round)
            when (icon) {
                ReaderIcon.CLOSE -> { line(6f, 6f, 18f, 18f); line(18f, 6f, 6f, 18f) }
                ReaderIcon.MORE -> listOf(5f, 12f, 19f).forEach { drawCircle(color, 1.8f, Offset(it, 12f)) }
                ReaderIcon.PAUSE -> { drawRect(color, Offset(6f, 4f), Size(4f, 16f)); drawRect(color, Offset(14f, 4f), Size(4f, 16f)) }
                ReaderIcon.PLAY -> {
                    val path = androidx.compose.ui.graphics.Path().apply { moveTo(7f, 4f); lineTo(20f, 12f); lineTo(7f, 20f); close() }
                    drawPath(path, color)
                }
                ReaderIcon.MIC -> {
                    drawRoundRect(color, Offset(9f, 3f), Size(6f, 12f), CornerRadius(3f), style = Stroke(1.8f))
                    drawArc(color, 0f, 180f, false, Offset(5f, 4f), Size(14f, 14f), style = Stroke(1.8f))
                    line(12f, 18f, 12f, 21f); line(8f, 21f, 16f, 21f)
                }
                ReaderIcon.WAVE -> listOf(4f, 12f, 18f, 8f, 16f, 10f, 4f).forEachIndexed { i, h ->
                    line(2f + i * 3.3f, 12f - h / 2, 2f + i * 3.3f, 12f + h / 2) }
                ReaderIcon.NEXT -> { line(9f, 6f, 15f, 12f); line(15f, 12f, 9f, 18f) }
                ReaderIcon.MOVE -> {
                    line(12f, 3f, 12f, 21f); line(3f, 12f, 21f, 12f)
                    line(9f, 6f, 12f, 3f); line(12f, 3f, 15f, 6f)
                    line(9f, 18f, 12f, 21f); line(12f, 21f, 15f, 18f)
                    line(6f, 9f, 3f, 12f); line(3f, 12f, 6f, 15f)
                    line(18f, 9f, 21f, 12f); line(21f, 12f, 18f, 15f)
                }
                ReaderIcon.SCAN -> {
                    line(8f, 3f, 3f, 3f); line(3f, 3f, 3f, 8f); line(16f, 3f, 21f, 3f); line(21f, 3f, 21f, 8f)
                    line(3f, 16f, 3f, 21f); line(3f, 21f, 8f, 21f); line(21f, 16f, 21f, 21f); line(21f, 21f, 16f, 21f)
                    line(7f, 12f, 17f, 12f)
                }
                ReaderIcon.REPLAY -> {
                    drawArc(color, -135f, 290f, false, Offset(4f, 4f), Size(16f, 16f), style = Stroke(1.8f))
                    line(4f, 4f, 4f, 10f); line(4f, 10f, 10f, 10f)
                }
                ReaderIcon.HEADPHONES -> {
                    drawArc(color, 180f, 180f, false, Offset(4f, 3f), Size(16f, 16f), style = Stroke(1.8f))
                    drawRoundRect(color, Offset(3f, 12f), Size(4f, 8f), CornerRadius(2f), style = Stroke(1.8f))
                    drawRoundRect(color, Offset(17f, 12f), Size(4f, 8f), CornerRadius(2f), style = Stroke(1.8f))
                }
            }
        }
    }
}
