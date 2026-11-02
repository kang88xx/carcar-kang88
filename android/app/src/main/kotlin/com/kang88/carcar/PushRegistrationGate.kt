package com.kang88.carcar

/** Serializes registration and SDK token deletion across Activity instances. */
class PushRegistrationGate {
    private var generation = 0L
    private var active: Long? = null
    private var deletions = 0

    @Synchronized fun begin(): Long? {
        if (active != null || deletions != 0) return null
        generation += 1
        active = generation
        return generation
    }
    @Synchronized fun isCurrent(attempt: Long) = active == attempt
    @Synchronized fun finish(attempt: Long): Boolean {
        if (active != attempt) return false
        active = null
        return true
    }
    @Synchronized fun cancel() { generation += 1; active = null }
    @Synchronized fun beginDelete() { cancel(); deletions += 1 }
    @Synchronized fun endDelete() { check(deletions > 0); deletions -= 1 }
    @Synchronized fun beginDiscardIfIdle(): Boolean {
        if (active != null || deletions != 0) return false
        beginDelete()
        return true
    }
}
