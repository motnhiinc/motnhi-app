package com.motnhi.app.characterreader

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.motnhi.app.R

/** One explicit listening turn. No recording across navigation, narration or backgrounding. */
internal class ReaderVoiceInput(
    private val context: Context,
    private val state: ReaderUiState,
    private val onCommand: (ReaderVoiceCommand) -> Unit,
) {
    private var recognizer: SpeechRecognizer? = null
    private var generation = 0

    fun cancel() {
        generation++ // Late results from an interrupted turn cannot change playback.
        val old = recognizer
        recognizer = null
        state.listening = false
        state.voiceStatus = R.string.reader_voice_hint
        old?.cancel()
        old?.destroy()
    }

    fun listen() {
        cancel()
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            state.voiceStatus = R.string.reader_voice_unavailable
            return
        }
        val turn = generation
        try {
            val speech = if (Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            } else SpeechRecognizer.createSpeechRecognizer(context)
            recognizer = speech
            speech.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onPartialResults(partialResults: Bundle?) = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit
                override fun onError(error: Int) {
                    if (turn != generation) return
                    cancel()
                    state.voiceStatus = if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS)
                        R.string.reader_voice_permission else R.string.reader_voice_retry
                }
                override fun onResults(results: Bundle?) {
                    if (turn != generation) return
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                    val command = text?.let(ReaderVoiceCommands::parse)
                    cancel()
                    if (command == null) state.voiceStatus = R.string.reader_voice_unknown
                    else {
                        onCommand(command)
                        if (state.voiceStatus != R.string.reader_voice_hint) state.panel = ReaderPanel.VOICE
                    }
                }
            })
            state.listening = true
            state.voiceStatus = R.string.reader_listening
            speech.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, context.resources.configuration.locales[0].toLanguageTag())
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            })
        } catch (_: Exception) {
            cancel()
            state.voiceStatus = R.string.reader_voice_unavailable
        }
    }
}
