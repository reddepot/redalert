package com.zaifears.locreminder

internal object TravelDirection {
    /** Unknown course never silently disables a point. Bearing is travel direction. */
    fun applies(expected: Double?, measured: Double?): Boolean {
        if (expected == null || measured == null || !expected.isFinite() || !measured.isFinite()) return true
        val delta = kotlin.math.abs(((measured - expected) % 360 + 540) % 360 - 180)
        return delta <= 60
    }
}
