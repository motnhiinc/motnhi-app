package com.storybookar.storybook_ar

class OneShotGate {
    private var claimed = false

    @Synchronized
    fun claim(): Boolean {
        if (claimed) return false
        claimed = true
        return true
    }
}

class OneAtATimeGate {
    private var inProgress = false

    @Synchronized
    fun tryStart(): Boolean {
        if (inProgress) return false
        inProgress = true
        return true
    }

    @Synchronized
    fun finish(): Boolean {
        if (!inProgress) return false
        inProgress = false
        return true
    }

    @Synchronized
    fun isInProgress(): Boolean = inProgress
}
