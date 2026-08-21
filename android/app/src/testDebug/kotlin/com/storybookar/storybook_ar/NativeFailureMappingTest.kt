package com.storybookar.storybook_ar

import android.app.Activity
import com.google.ar.core.ArCoreApk
import com.storybookar.storybook_ar.characterreader.ArCoreAvailabilityDecision
import com.storybookar.storybook_ar.characterreader.ArCoreAvailabilityMapper
import com.storybookar.storybook_ar.characterreader.CharacterReaderResultMapper
import com.storybookar.storybook_ar.scananypage.ScannerFailureMapper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NativeFailureMappingTest {
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

    @Test
    fun mapsReaderActivityResultsToContractCodes() {
        assertEquals(
            "completed",
            CharacterReaderResultMapper.terminalCode(
                Activity.RESULT_OK,
                CharacterReaderResultMapper.COMPLETED,
            ),
        )
        assertEquals(
            "model_missing",
            CharacterReaderResultMapper.terminalCode(Activity.RESULT_CANCELED, "model_missing"),
        )
        assertEquals(
            "cancelled",
            CharacterReaderResultMapper.terminalCode(Activity.RESULT_CANCELED, null),
        )
        assertEquals(
            "ar_failed",
            CharacterReaderResultMapper.terminalCode(Activity.RESULT_OK, null),
        )
        assertEquals(
            "ar_failed",
            CharacterReaderResultMapper.terminalCode(Activity.RESULT_OK, "not_a_contract_code"),
        )
    }

    @Test
    fun mapsArCoreAvailabilityWithBoundedTransientSemantics() {
        assertEquals(
            ArCoreAvailabilityDecision.Supported,
            ArCoreAvailabilityMapper.map(ArCoreApk.Availability.SUPPORTED_INSTALLED),
        )
        assertEquals(
            ArCoreAvailabilityDecision.NeedsInstall,
            ArCoreAvailabilityMapper.map(ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED),
        )
        assertEquals(
            ArCoreAvailabilityDecision.Retry,
            ArCoreAvailabilityMapper.map(ArCoreApk.Availability.UNKNOWN_CHECKING),
        )
        assertEquals(
            ArCoreAvailabilityDecision.Failed,
            ArCoreAvailabilityMapper.map(ArCoreApk.Availability.UNKNOWN_ERROR),
        )
        assertEquals(
            ArCoreAvailabilityDecision.Unsupported,
            ArCoreAvailabilityMapper.map(
                ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE,
            ),
        )
    }
}
