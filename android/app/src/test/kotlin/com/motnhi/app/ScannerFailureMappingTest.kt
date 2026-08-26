package com.motnhi.app

import android.app.Activity
import com.motnhi.app.scananypage.ScannerFailureMapper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Lives in src/test, not src/testDebug: ScannerFailureMapper ships in release
 * now, so it has to be covered by every variant's unit-test task.
 */
class ScannerFailureMappingTest {
    @Test
    fun mapsScannerActivityResultsByOrderedDecisionRule() {
        assertNull(
            ScannerFailureMapper.activityResultFailureCode(
                resultCode = Activity.RESULT_OK,
                hasParsedResult = true,
                pageCount = 1,
            ),
        )
        assertEquals(
            "capture_failed",
            ScannerFailureMapper.activityResultFailureCode(
                resultCode = Activity.RESULT_OK,
                hasParsedResult = false,
                pageCount = 0,
            ),
        )
        assertEquals(
            "capture_failed",
            ScannerFailureMapper.activityResultFailureCode(
                resultCode = Activity.RESULT_OK,
                hasParsedResult = true,
                pageCount = 0,
            ),
        )
        assertEquals(
            "cancelled",
            ScannerFailureMapper.activityResultFailureCode(
                resultCode = Activity.RESULT_CANCELED,
                hasParsedResult = true,
                pageCount = 1,
            ),
        )
    }
}
