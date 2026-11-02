package com.motnhi.app.characterreader

import android.content.Intent
import android.content.pm.ResolveInfo
import android.content.pm.ServiceInfo
import android.os.Bundle
import android.os.Looper
import android.speech.RecognitionService
import android.speech.SpeechRecognizer
import com.motnhi.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSpeechRecognizer

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ReaderVoiceInputTest {
    private fun withVoice(check: (ReaderVoiceInput, ReaderUiState, MutableList<ReaderVoiceCommand>) -> Unit) {
        val context = RuntimeEnvironment.getApplication()
        shadowOf(context.packageManager).addResolveInfoForIntent(Intent(RecognitionService.SERVICE_INTERFACE),
            ResolveInfo().apply { serviceInfo = ServiceInfo().apply {
                packageName = "test.speech"; name = "Recognizer"
            } })
        val state = ReaderUiState()
        val commands = mutableListOf<ReaderVoiceCommand>()
        val voice = ReaderVoiceInput(context, state) { commands.add(it) }
        try { check(voice, state, commands) } finally { voice.cancel() }
    }

    private fun result(text: String) = Bundle().apply {
        putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(text))
    }

    @Test fun resultEndsListeningBeforeDispatchAndCancelledTurnsCannotAct() = withVoice { voice, state, commands ->
        voice.listen()
        shadowOf(Looper.getMainLooper()).idle()
        val first = shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer())
        assertTrue(state.listening)
        first.triggerOnResults(result("Đọc lại"))
        assertFalse(state.listening)
        assertEquals(listOf(ReaderVoiceCommand.REPLAY), commands)
        assertTrue(first.isDestroyed)
        voice.listen()
        shadowOf(Looper.getMainLooper()).idle()
        val cancelled = shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer())
        voice.cancel()
        cancelled.triggerOnResults(result("next page"))
        assertEquals(listOf(ReaderVoiceCommand.REPLAY), commands)
        assertFalse(state.listening)
    }

    @Test fun errorsReleaseMicrophoneAndUnknownSpeechNeverExecutes() = withVoice { voice, state, commands ->
        voice.listen()
        shadowOf(Looper.getMainLooper()).idle()
        val first = shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer())
        first.triggerOnError(SpeechRecognizer.ERROR_NO_MATCH)
        assertTrue(first.isDestroyed)
        assertFalse(state.listening)
        assertEquals(R.string.reader_voice_retry, state.voiceStatus)
        voice.listen()
        shadowOf(Looper.getMainLooper()).idle()
        shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer()).triggerOnResults(result("Why is the fox sad?"))
        assertTrue(commands.isEmpty())
        assertEquals(R.string.reader_voice_unknown, state.voiceStatus)
    }
}
