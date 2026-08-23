package com.storybookar.storybook_ar.characterreader

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.addCallback
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RequiresApi
import java.io.File
import java.io.FileNotFoundException

class CharacterReaderActivity : ComponentActivity() {
    private val ui = ReaderUiState()
    private var mediaPlayer: MediaPlayer? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var legacyFocusHeld = false
    private var playbackStarted = false
    private var placed = false
    private var terminal = false

    /**
     * Both entry points normalise onto this list, so there is exactly one playback path. The
     * single-clip scan-any-page flow is simply a one-page, one-clip story.
     */
    private var pages: List<StoryReaderPage> = emptyList()
    private var pageIndex = 0
    private var clipIndex = 0

    /** Insertion-ordered so the player receives pages in the order the child heard them. */
    private val pagesRead = LinkedHashSet<String>()
    private var storyMode = false

    /**
     * Registered at construction, before the activity is STARTED, as the Activity Result API
     * requires. ARCore's built-in permission handler is not used: on denial it opens the app's
     * system settings and never reports a failure, so the reader would sit on a black screen
     * with Close as the only way out. iOS surfaces the same denial as `ar_failed`.
     */
    private val cameraPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) showScene() else finishWith("ar_failed")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val resolved = resolvePages()
        if (resolved == null) {
            finishWith("audio_missing")
            return
        }
        pages = resolved
        if (!modelExists()) {
            finishWith("model_missing")
            return
        }

        // Only a failure preparing the very first clip is terminal. Once the scene is up, a
        // later clip failing is surfaced in-scene so the child keeps their placed character.
        if (!preparePlayer()) {
            finishWith("audio_failed")
            return
        }
        syncPageUi()

        onBackPressedDispatcher.addCallback(this) {
            finishWith(if (playbackStarted) "completed" else "cancelled")
        }

        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            showScene()
        } else {
            cameraPermission.launch(Manifest.permission.CAMERA)
        }
    }

    /**
     * Re-validates every path even though the bridge already did. The extras are a trust
     * boundary of their own, and the check is cheap next to starting an AR session.
     */
    private fun resolvePages(): List<StoryReaderPage>? {
        val validator = AudioPathValidator(cacheDir)

        val pagesJson = intent.getStringExtra(EXTRA_PAGES_JSON)
        if (pagesJson != null) {
            storyMode = true
            val decoded = StoryReaderPageCodec.decode(pagesJson)
            if (decoded.isEmpty()) return null

            val validated = decoded.map { page ->
                val clips = page.audioFilePaths.mapNotNull { validator.validate(it)?.path }
                if (clips.size != page.audioFilePaths.size) return null
                page.copy(audioFilePaths = clips)
            }
            pageIndex = StoryReaderPages.clampIndex(
                intent.getIntExtra(EXTRA_INITIAL_PAGE_INDEX, 0),
                validated.size,
            )
            return validated
        }

        val audioFile = validator.validate(intent.getStringExtra(EXTRA_AUDIO_FILE_PATH))
            ?: return null
        return listOf(
            StoryReaderPage(pageId = "", pageNumber = 1, audioFilePaths = listOf(audioFile.path)),
        )
    }

    private fun showScene() {
        if (terminal) return
        setContent {
            CharacterReaderScreen(
                state = ui,
                modelAssetFileName = MODEL_FILENAME,
                onFailure = ::finishWith,
                onPlaced = {
                    placed = true
                    ui.guidance = GUIDANCE_READY
                    ui.controlsVisible = true
                },
                onReadClick = ::togglePlayback,
                onPreviousClick = { goToPage(-1) },
                onNextClick = { goToPage(1) },
                onCloseClick = {
                    finishWith(if (playbackStarted) "completed" else "cancelled")
                },
            )
        }
    }

    /**
     * Narration must not keep playing over the launcher or lock screen. The AR session pauses
     * itself (ARSceneView registers its own lifecycle observers); the audio does not. iOS pauses
     * it in applicationWillResignActive.
     */
    override fun onPause() {
        super.onPause()
        if (terminal) return
        val player = mediaPlayer ?: return
        if (!player.isPlaying) return
        player.pause()
        abandonAudioFocus()
        ui.guidance = "Reading paused"
        ui.readLabel = "Resume"
        ui.speaking = false
    }

    override fun onDestroy() {
        releaseAudio()
        super.onDestroy()
    }

    private fun currentClipPath(): String? =
        pages.getOrNull(pageIndex)?.audioFilePaths?.getOrNull(clipIndex)

    /** Builds a player for the current clip. Returns false instead of finishing the activity. */
    private fun preparePlayer(): Boolean {
        releaseAudio()
        val path = currentClipPath() ?: return false

        val player = MediaPlayer()
        mediaPlayer = player
        return try {
            player.apply {
                setAudioAttributes(speechAttributes())
                setDataSource(File(path).path)
                setOnCompletionListener { onClipCompleted() }
                setOnErrorListener { _, _, _ ->
                    abandonAudioFocus()
                    showAudioRetry()
                    true
                }
                prepare()
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * A page's clips play back to back. Only when the last one ends is the page finished — this
     * is what keeps multi-segment curated pages from being cut off after their first sentence.
     */
    private fun onClipCompleted() {
        abandonAudioFocus()
        val page = pages.getOrNull(pageIndex) ?: return

        if (clipIndex + 1 < page.audioFilePaths.size) {
            clipIndex++
            if (preparePlayer() && startPlayer()) return
            showAudioRetry()
            return
        }

        mediaPlayer?.seekTo(0)
        ui.guidance = if (storyMode && pageIndex < pages.size - 1) {
            "Page finished - Tap next"
        } else {
            "Reading complete"
        }
        ui.readLabel = "Read"
        ui.speaking = false
    }

    /**
     * Moves between pages without touching the AR session or the placed anchor: only the audio
     * data source changes, which is what lets the character stay exactly where the child put it.
     */
    private fun goToPage(delta: Int) {
        if (!placed || !storyMode) return
        val target = pageIndex + delta
        if (target < 0 || target >= pages.size) return

        val wasSpeaking = ui.speaking
        pageIndex = target
        clipIndex = 0
        syncPageUi()

        if (!preparePlayer()) {
            showAudioRetry()
            return
        }
        if (wasSpeaking) {
            if (!startPlayer()) showAudioRetry()
        } else {
            ui.guidance = GUIDANCE_READY
            ui.readLabel = "Read"
            ui.speaking = false
        }
    }

    private fun syncPageUi() {
        if (!storyMode) return
        ui.pageLabel = "Page ${pageIndex + 1} of ${pages.size}"
        ui.canGoPrevious = pageIndex > 0
        ui.canGoNext = pageIndex < pages.size - 1
    }

    private fun startPlayer(): Boolean {
        val player = mediaPlayer ?: return false
        if (!requestAudioFocus()) return false
        return try {
            player.start()
            playbackStarted = true
            pages.getOrNull(pageIndex)?.pageId?.takeIf { it.isNotEmpty() }?.let(pagesRead::add)
            ui.guidance = "Reading aloud"
            ui.readLabel = "Pause"
            ui.speaking = true
            true
        } catch (_: IllegalStateException) {
            abandonAudioFocus()
            false
        }
    }

    private fun showAudioRetry() {
        ui.guidance = "Audio couldn't play - Tap Retry"
        ui.readLabel = "Retry"
        ui.speaking = false
    }

    private fun togglePlayback() {
        if (!placed) return
        val player = mediaPlayer ?: return
        if (player.isPlaying) {
            player.pause()
            abandonAudioFocus()
            ui.guidance = "Reading paused"
            ui.readLabel = "Resume"
            ui.speaking = false
            return
        }

        if (!startPlayer()) showAudioRetry()
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        if (focusChange == AudioManager.AUDIOFOCUS_LOSS ||
            focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
        ) {
            mediaPlayer?.pause()
            ui.guidance = "Reading paused"
            ui.readLabel = "Resume"
            ui.speaking = false
        }
    }

    private fun speechAttributes(): AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

    /**
     * AudioFocusRequest is API 26 and this module ships at minSdk 24, so the modern path lives in
     * its own method: the verifier never has to resolve it in a frame that runs on API 24/25.
     * Without the split, tapping Read on such a device throws NoClassDefFoundError, the activity
     * dies with RESULT_CANCELED and no extra, and Dart reads the crash as a user cancel.
     */
    private fun requestAudioFocus(): Boolean {
        val manager = getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return requestAudioFocusApi26(manager)
        }
        legacyFocusHeld = true
        @Suppress("DEPRECATION")
        return manager.requestAudioFocus(
            focusListener,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
        ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun requestAudioFocusApi26(manager: AudioManager): Boolean {
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(speechAttributes())
            .setOnAudioFocusChangeListener(focusListener)
            .build()
        audioFocusRequest = request
        return manager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonAudioFocus() {
        val manager = getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            abandonAudioFocusApi26(manager)
            return
        }
        if (!legacyFocusHeld) return
        legacyFocusHeld = false
        @Suppress("DEPRECATION")
        manager.abandonAudioFocus(focusListener)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun abandonAudioFocusApi26(manager: AudioManager) {
        val request = audioFocusRequest ?: return
        manager.abandonAudioFocusRequest(request)
        audioFocusRequest = null
    }

    private fun releaseAudio() {
        abandonAudioFocus()
        mediaPlayer?.release()
        mediaPlayer = null
    }

    private fun modelExists(): Boolean {
        return try {
            assets.open(MODEL_FILENAME).use { }
            true
        } catch (_: FileNotFoundException) {
            false
        }
    }

    private fun finishWith(code: String) {
        if (terminal) return
        terminal = true
        releaseAudio()
        val resultCode = if (code == CharacterReaderResultMapper.COMPLETED) {
            RESULT_OK
        } else {
            RESULT_CANCELED
        }
        val data = Intent().putExtra(CharacterReaderResultMapper.EXTRA_TERMINAL_CODE, code)
        if (storyMode) {
            // Carried on every terminal path, including cancel: cancel is the normal way to
            // leave AR and the child's progress through the story still matters.
            data.putExtra(
                CharacterReaderResultMapper.EXTRA_LAST_PAGE_ID,
                pages.getOrNull(pageIndex)?.pageId,
            )
            data.putStringArrayListExtra(
                CharacterReaderResultMapper.EXTRA_PAGES_READ,
                ArrayList(pagesRead),
            )
        }
        setResult(resultCode, data)
        finish()
    }

    companion object {
        const val EXTRA_AUDIO_FILE_PATH = "storybook_ar.character_reader.AUDIO_FILE_PATH"
        const val EXTRA_PAGES_JSON = "storybook_ar.character_reader.PAGES_JSON"
        const val EXTRA_INITIAL_PAGE_INDEX = "storybook_ar.character_reader.INITIAL_PAGE_INDEX"
        const val MODEL_FILENAME = "scan_any_page_character.glb"
    }
}
