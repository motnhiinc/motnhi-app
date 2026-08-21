package com.storybookar.storybook_ar

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger

class ScanAnyPageBridges private constructor() {
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) = Unit

    companion object {
        fun register(activity: Activity, messenger: BinaryMessenger): ScanAnyPageBridges =
            ScanAnyPageBridges()
    }
}
