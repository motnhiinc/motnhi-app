package com.motnhi.app.characterreader

import org.junit.Assert.*
import org.junit.Test

class ReaderVoiceCommandsTest {
    @Test fun recognizesVietnameseWithAccentsAndPunctuation() {
        assertEquals(ReaderVoiceCommand.READ, ReaderVoiceCommands.parse("Đọc cho mình nghe nhé!"))
        assertEquals(ReaderVoiceCommand.REPLAY, ReaderVoiceCommands.parse("ĐỌC LẠI"))
        assertEquals(ReaderVoiceCommand.PAUSE, ReaderVoiceCommands.parse("Tạm dừng."))
        assertEquals(ReaderVoiceCommand.NEXT, ReaderVoiceCommands.parse("Trang tiếp theo"))
        assertEquals(ReaderVoiceCommand.PLACE, ReaderVoiceCommands.parse("Lại đây"))
    }

    @Test fun explicitEnglishCommandsDoNotMatchStorySentences() {
        assertEquals(ReaderVoiceCommand.READ, ReaderVoiceCommands.parse("Please read to me."))
        assertEquals(ReaderVoiceCommand.REPLAY, ReaderVoiceCommands.parse("Read it again, please"))
        assertEquals(ReaderVoiceCommand.CANCEL_MOVE, ReaderVoiceCommands.parse("stay there"))
        assertNull(ReaderVoiceCommands.parse("Why did the fox stop reading?"))
        assertNull(ReaderVoiceCommands.parse("Do not read"))
        assertNull(ReaderVoiceCommands.parse(""))
    }
}
