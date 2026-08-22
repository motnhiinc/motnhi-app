package com.storybookar.storybook_ar.scananypage

import android.app.Activity

object ScannerFailureMapper {
    fun activityResultFailureCode(
        resultCode: Int,
        hasParsedResult: Boolean,
        pageCount: Int,
    ): String? {
        if (resultCode != Activity.RESULT_OK) return "cancelled"
        if (!hasParsedResult || pageCount <= 0) return "capture_failed"
        return null
    }
}
