package com.storybookar.storybook_ar.characterreader

import com.google.ar.core.ArCoreApk

enum class ArCoreAvailabilityDecision {
    Supported,
    NeedsInstall,
    Unsupported,
    Retry,
    Failed,
}

object ArCoreAvailabilityMapper {
    fun map(availability: ArCoreApk.Availability): ArCoreAvailabilityDecision {
        return when (availability) {
            ArCoreApk.Availability.SUPPORTED_INSTALLED ->
                ArCoreAvailabilityDecision.Supported
            ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD,
            ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED ->
                ArCoreAvailabilityDecision.NeedsInstall
            ArCoreApk.Availability.UNKNOWN_CHECKING,
            ArCoreApk.Availability.UNKNOWN_TIMED_OUT ->
                ArCoreAvailabilityDecision.Retry
            ArCoreApk.Availability.UNKNOWN_ERROR ->
                ArCoreAvailabilityDecision.Failed
            else -> {
                if (availability.isUnsupported) {
                    ArCoreAvailabilityDecision.Unsupported
                } else {
                    ArCoreAvailabilityDecision.Failed
                }
            }
        }
    }
}
