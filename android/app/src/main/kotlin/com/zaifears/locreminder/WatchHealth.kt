package com.zaifears.locreminder

/** A registered listener is acquiring a fix, not evidence that a position was received. */
internal object WatchHealth {
    const val STALE_MILLIS = 15_000L
    fun state(watching: Boolean, dormant: Boolean, registered: Boolean, lastFix: Long, now: Long, interval: Long = 1000L): String = when {
        !watching -> "stopped"
        dormant -> "dormant"
        !registered -> "unavailable"
        lastFix <= 0 || lastFix > now -> "acquiring"
        now - lastFix <= STALE_MILLIS -> "fresh"
        interval > STALE_MILLIS && now - lastFix <= interval * 2 -> "economy"
        else -> "stale"
    }
}
