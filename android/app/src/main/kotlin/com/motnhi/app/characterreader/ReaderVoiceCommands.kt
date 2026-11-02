package com.motnhi.app.characterreader

import java.text.Normalizer
import java.util.Locale

internal enum class ReaderVoiceCommand { READ, PAUSE, REPLAY, NEXT, PREVIOUS, PLACE, MOVE, CANCEL_MOVE }

/** Whole utterances only: a story sentence containing "stop" must not become a command. */
internal object ReaderVoiceCommands {
    private fun normalize(text: String): String = Normalizer.normalize(text.lowercase(Locale.ROOT), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "").replace('đ', 'd')
        .replace(Regex("[^a-z0-9\\s]"), " ").trim().replace(Regex("\\s+"), " ")

    private val phrases = mapOf(
        ReaderVoiceCommand.READ to listOf("read", "read to me", "read the story", "resume", "keep reading", "continue", "doc", "doc cho minh nghe", "doc truyen", "doc tiep"),
        ReaderVoiceCommand.PAUSE to listOf("stop", "pause", "stop reading", "wait", "dung", "dung lai", "tam dung", "dung doc"),
        ReaderVoiceCommand.REPLAY to listOf("again", "read again", "start again", "read it again", "doc lai", "lai nao", "doc lai tu dau"),
        ReaderVoiceCommand.NEXT to listOf("next", "next page", "trang tiep", "trang tiep theo"),
        ReaderVoiceCommand.PREVIOUS to listOf("previous page", "go back", "trang truoc", "quay lai trang truoc"),
        ReaderVoiceCommand.PLACE to listOf("come here", "place here", "stand here", "lai day", "dung day", "dat o day"),
        ReaderVoiceCommand.MOVE to listOf("move", "move here", "di chuyen", "doi cho"),
        ReaderVoiceCommand.CANCEL_MOVE to listOf("cancel move", "stay there", "huy di chuyen", "o yen do"),
    ).flatMap { (command, words) -> words.map { it to command } }.toMap()

    fun parse(text: String): ReaderVoiceCommand? {
        val words = normalize(text).removePrefix("please ").removeSuffix(" please")
            .removeSuffix(" nhe").removeSuffix(" nhe ban")
        return phrases[words]
    }
}
