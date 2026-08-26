package com.motnhi.app

import android.app.Activity
import com.google.ar.core.ArCoreApk
import com.motnhi.app.characterreader.ArCoreAvailabilityDecision
import com.motnhi.app.characterreader.ArCoreAvailabilityMapper
import com.motnhi.app.characterreader.ArCoreInstallPolicy
import com.motnhi.app.characterreader.ArCoreInstallStep
import com.motnhi.app.characterreader.CharacterReaderResultMapper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * ARCore character-reader mapping only. The scanner's cases moved to
 * src/test/.../ScannerFailureMappingTest once the scanner shipped in release.
 */
class NativeFailureMappingTest {
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

    @Test
    fun promptsForArCoreInstallOnceThenConfirmsOnResumeWithinABound() {
        // requestInstall() reports an install by being called again after the host resumes, so the
        // first call is the only one allowed to prompt.
        assertEquals(ArCoreInstallStep.Prompt, ArCoreInstallPolicy.nextStep(0))
        assertEquals(ArCoreInstallStep.Confirm, ArCoreInstallPolicy.nextStep(1))
        assertEquals(ArCoreInstallStep.Confirm, ArCoreInstallPolicy.nextStep(2))
    }

    @Test
    fun givesUpOnArCoreInstallRatherThanLeavingTheResultPending() {
        // Every step has to terminate: an unbounded resume/re-request cycle would orphan the
        // pending Dart result, which is the defect this policy exists to prevent.
        assertEquals(
            ArCoreInstallStep.GiveUp,
            ArCoreInstallPolicy.nextStep(ArCoreInstallPolicy.MAX_ATTEMPTS),
        )
        assertEquals(
            ArCoreInstallStep.GiveUp,
            ArCoreInstallPolicy.nextStep(ArCoreInstallPolicy.MAX_ATTEMPTS + 1),
        )
    }
}
