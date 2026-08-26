package com.motnhi.app

import android.app.Activity
import android.content.Intent
import com.motnhi.app.characterreader.CharacterReaderBridge
import com.motnhi.app.scananypage.ScanAnyPageBridge
import io.flutter.plugin.common.BinaryMessenger

class ScanAnyPageBridges private constructor(
    private val scanner: ScanAnyPageBridge,
    private val reader: CharacterReaderBridge,
) {
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        scanner.onActivityResult(requestCode, resultCode, data)
        reader.onActivityResult(requestCode, resultCode, data)
    }

    fun onHostResume() {
        reader.onHostResume()
    }

    companion object {
        const val READER_REQUEST_CODE = 0x51A2

        fun register(activity: Activity, messenger: BinaryMessenger): ScanAnyPageBridges {
            return ScanAnyPageBridges(
                scanner = ScanAnyPageBridge(
                    activity = activity,
                    messenger = messenger,
                    requestCode = SCANNER_REQUEST_CODE,
                ),
                reader = CharacterReaderBridge.create(
                    activity = activity,
                    messenger = messenger,
                    readerRequestCode = READER_REQUEST_CODE,
                ),
            )
        }
    }
}
