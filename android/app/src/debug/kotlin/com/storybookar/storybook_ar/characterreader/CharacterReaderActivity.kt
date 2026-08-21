package com.storybookar.storybook_ar.characterreader

import android.app.Activity
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.RequiresApi
import java.io.File
import java.io.FileNotFoundException

class CharacterReaderActivity : Activity() {
    private var mediaPlayer: MediaPlayer? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var legacyFocusHeld = false
    private var playbackStarted = false
    private var terminal = false
    private lateinit var guidanceLabel: TextView
    private lateinit var readButton: Button
    private lateinit var waveBadge: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val audioPath = intent.getStringExtra(EXTRA_AUDIO_FILE_PATH)
        val audioFile = AudioPathValidator(cacheDir).validate(audioPath)
        if (audioFile == null) {
            finishWith("audio_missing")
            return
        }
        if (!modelExists()) {
            finishWith("model_missing")
            return
        }

        configureView()
        prepareAudio(audioFile)
    }

    override fun onBackPressed() {
        finishWith(if (playbackStarted) "completed" else "cancelled")
    }

    override fun onDestroy() {
        releaseAudio()
        super.onDestroy()
    }

    private fun configureView() {
        val root = FrameLayout(this).apply {
            setBackgroundColor(0xFF000000.toInt())
        }
        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(32, 32, 32, 32)
        }
        guidanceLabel = TextView(this).apply {
            text = "Character ready"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 20f
            gravity = Gravity.CENTER
        }
        waveBadge = TextView(this).apply {
            text = "Reading aloud"
            setTextColor(0xFFFFFFFF.toInt())
            visibility = View.GONE
            gravity = Gravity.CENTER
        }
        readButton = Button(this).apply {
            text = "Read"
            setOnClickListener { togglePlayback() }
        }
        val closeButton = Button(this).apply {
            text = "Close"
            setOnClickListener {
                finishWith(if (playbackStarted) "completed" else "cancelled")
            }
        }
        controls.addView(guidanceLabel)
        controls.addView(waveBadge)
        controls.addView(readButton)
        controls.addView(closeButton)
        root.addView(
            controls,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )
        setContentView(root)
    }

    private fun prepareAudio(audioFile: File) {
        try {
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(speechAttributes())
                setDataSource(audioFile.path)
                setOnCompletionListener {
                    abandonAudioFocus()
                    seekTo(0)
                    guidanceLabel.text = "Reading complete"
                    readButton.text = "Read"
                    waveBadge.visibility = View.GONE
                }
                setOnErrorListener { _, _, _ ->
                    abandonAudioFocus()
                    guidanceLabel.text = "Audio couldn't play - Tap Retry"
                    readButton.text = "Retry"
                    waveBadge.visibility = View.GONE
                    true
                }
                prepare()
            }
        } catch (_: Exception) {
            finishWith("audio_failed")
        }
    }

    private fun togglePlayback() {
        val player = mediaPlayer ?: return
        if (player.isPlaying) {
            player.pause()
            abandonAudioFocus()
            guidanceLabel.text = "Reading paused"
            readButton.text = "Resume"
            waveBadge.visibility = View.GONE
            return
        }

        if (!requestAudioFocus()) {
            guidanceLabel.text = "Audio couldn't play - Tap Retry"
            readButton.text = "Retry"
            waveBadge.visibility = View.GONE
            return
        }

        try {
            player.start()
            playbackStarted = true
            guidanceLabel.text = "Reading aloud"
            readButton.text = "Pause"
            waveBadge.visibility = View.VISIBLE
        } catch (_: IllegalStateException) {
            abandonAudioFocus()
            guidanceLabel.text = "Audio couldn't play - Tap Retry"
            readButton.text = "Retry"
            waveBadge.visibility = View.GONE
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        if (focusChange == AudioManager.AUDIOFOCUS_LOSS ||
            focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
        ) {
            mediaPlayer?.pause()
            guidanceLabel.text = "Reading paused"
            readButton.text = "Resume"
            waveBadge.visibility = View.GONE
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
        setResult(resultCode, data)
        finish()
    }

    companion object {
        const val EXTRA_AUDIO_FILE_PATH = "storybook_ar.character_reader.AUDIO_FILE_PATH"
        const val MODEL_FILENAME = "scan_any_page_character.glb"
    }
}
