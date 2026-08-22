package com.storybookar.storybook_ar.characterreader

import android.os.Handler
import android.os.Looper

/**
 * Main-thread dispatch for the bridge. A JVM test cannot build a Looper, so this is injected and
 * the test runs everything inline while still controlling when a delayed poll fires.
 */
interface Scheduler {
    fun runOnMain(action: () -> Unit)

    fun postDelayed(delayMs: Long, action: () -> Unit)
}

class MainLooperScheduler : Scheduler {
    private val handler = Handler(Looper.getMainLooper())

    override fun runOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            handler.post(action)
        }
    }

    override fun postDelayed(delayMs: Long, action: () -> Unit) {
        handler.postDelayed(action, delayMs)
    }
}
