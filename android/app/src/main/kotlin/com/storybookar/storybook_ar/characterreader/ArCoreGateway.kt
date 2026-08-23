package com.storybookar.storybook_ar.characterreader

import android.app.Activity
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException

/** Outcome of one install request, with ARCore's exceptions already folded in. */
enum class ArCoreInstallOutcome {
    Installed,
    Requested,
    Declined,
    NotCompatible,
    Failed,
}

/**
 * The bridge's view of ARCore. Exists so the install flow can be driven from a JVM test: the real
 * implementation reaches ArCoreApk's statics and an Activity, neither of which a unit test has.
 */
interface ArCoreGateway {
    fun checkAvailability(): ArCoreAvailabilityDecision

    fun requestInstall(userRequestedInstall: Boolean): ArCoreInstallOutcome
}

class ArCoreApkGateway(private val activity: Activity) : ArCoreGateway {
    override fun checkAvailability(): ArCoreAvailabilityDecision =
        ArCoreAvailabilityMapper.map(ArCoreApk.getInstance().checkAvailability(activity))

    override fun requestInstall(userRequestedInstall: Boolean): ArCoreInstallOutcome =
        try {
            when (ArCoreApk.getInstance().requestInstall(activity, userRequestedInstall)) {
                ArCoreApk.InstallStatus.INSTALLED -> ArCoreInstallOutcome.Installed
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> ArCoreInstallOutcome.Requested
            }
        } catch (_: UnavailableUserDeclinedInstallationException) {
            ArCoreInstallOutcome.Declined
        } catch (_: UnavailableDeviceNotCompatibleException) {
            ArCoreInstallOutcome.NotCompatible
        } catch (_: Exception) {
            ArCoreInstallOutcome.Failed
        }
}
