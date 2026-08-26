package com.motnhi.app.characterreader

/**
 * What the bridge should do the next time it drives the ARCore install flow.
 *
 * ArCoreApk.requestInstall() does not deliver an activity result: it starts the installer with a
 * plain startActivity and reports the outcome by being called again once the host activity
 * resumes. Every step out of this policy therefore has to end in either another request or a
 * terminal failure, or the pending Dart result is orphaned.
 */
enum class ArCoreInstallStep {
    /** First request for this operation. Shows the install prompt. */
    Prompt,

    /** Re-drive after returning from the installer. Must not prompt again. */
    Confirm,

    /** Too many requests without resolving. Fail with `ar_failed` rather than wait forever. */
    GiveUp,
}

object ArCoreInstallPolicy {
    /**
     * The documented flow needs two requests: one that prompts, one that confirms on resume.
     * A third is already anomalous, so it is the last one we make.
     */
    const val MAX_ATTEMPTS = 3

    fun nextStep(attemptsSoFar: Int): ArCoreInstallStep = when {
        attemptsSoFar >= MAX_ATTEMPTS -> ArCoreInstallStep.GiveUp
        attemptsSoFar == 0 -> ArCoreInstallStep.Prompt
        else -> ArCoreInstallStep.Confirm
    }
}
