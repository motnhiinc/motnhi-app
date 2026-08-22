package com.storybookar.storybook_ar

import android.app.Activity
import android.content.Intent
import com.storybookar.storybook_ar.scananypage.ScanAnyPageBridge
import io.flutter.plugin.common.BinaryMessenger

/**
 * Release/profile registers the ML Kit page scanner only. The ARCore character
 * reader stays debug-only, which is what keeps every AR entry out of the
 * release manifest.
 */
class ScanAnyPageBridges private constructor(
    private val scanner: ScanAnyPageBridge,
) {
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        scanner.onActivityResult(requestCode, resultCode, data)
    }

    // Only the ARCore reader needs a resume signal (ArCoreApk.requestInstall()
    // reports its outcome on resume, not via an activity result).
    fun onHostResume() = Unit

    companion object {
        fun register(activity: Activity, messenger: BinaryMessenger): ScanAnyPageBridges =
            ScanAnyPageBridges(
                scanner = ScanAnyPageBridge(
                    activity = activity,
                    messenger = messenger,
                    requestCode = SCANNER_REQUEST_CODE,
                ),
            )
    }
}
