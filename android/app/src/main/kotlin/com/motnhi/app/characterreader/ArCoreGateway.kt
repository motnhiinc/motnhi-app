package com.motnhi.app.characterreader

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

    fun checkAvailabilityDiagnostic(): ArCoreAvailabilityDiagnostic {
        val decision = checkAvailability()
        return ArCoreAvailabilityDiagnostic(decision.name, decision)
    }

    fun requestInstall(userRequestedInstall: Boolean): ArCoreInstallOutcome

    fun lastInstallFailureCause(): String? = null
}

class ArCoreApkGateway(private val activity: Activity) : ArCoreGateway {
    private var installFailureCause: String? = null

    override fun checkAvailability(): ArCoreAvailabilityDecision =
        checkAvailabilityDiagnostic().decision

    override fun checkAvailabilityDiagnostic(): ArCoreAvailabilityDiagnostic =
        ArCoreAvailabilityMapper.diagnostic(ArCoreApk.getInstance().checkAvailability(activity))

    override fun requestInstall(userRequestedInstall: Boolean): ArCoreInstallOutcome {
        installFailureCause = null
        return try {
            when (ArCoreApk.getInstance().requestInstall(activity, userRequestedInstall)) {
                ArCoreApk.InstallStatus.INSTALLED -> ArCoreInstallOutcome.Installed
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> ArCoreInstallOutcome.Requested
            }
        } catch (error: UnavailableUserDeclinedInstallationException) {
            installFailureCause = error.javaClass.simpleName
            ArCoreInstallOutcome.Declined
        } catch (error: UnavailableDeviceNotCompatibleException) {
            installFailureCause = error.javaClass.simpleName
            ArCoreInstallOutcome.NotCompatible
        } catch (error: Exception) {
            installFailureCause = error.javaClass.simpleName
            ArCoreInstallOutcome.Failed
        }
    }

    override fun lastInstallFailureCause(): String? = installFailureCause
}
