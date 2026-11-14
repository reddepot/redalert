package com.zaifears.locreminder

/** Reliable speed and every eligible point, independent of notification focus. */
internal object PassageSpeedPolicy {
    private const val MARGIN_KMH = 8
    private const val ZONE_METRES = 300.0
    data class Warning(val status: PassageTracker.Status, val point: AlarmEntry, val kmh: Int)

    fun eligible(status: PassageTracker.Status, point: AlarmEntry, speedMps: Double?): Boolean {
        val speed = speedMps?.takeIf { it.isFinite() && it in 0.0..70.0 } ?: return false
        val limit = point.speedLimitKmh ?: return false
        return PassageCuePolicy.speedEligible(status) &&
            status.distance <= minOf(point.radius, ZONE_METRES) && speed * 3.6 >= limit + MARGIN_KMH
    }

    fun select(observed: List<PassageTracker.Status>, points: Map<String, AlarmEntry>,
               speedMps: Double?, applicable: Set<String>): Warning? = observed
        .asSequence().filter { it.id in applicable }
        .mapNotNull { status -> points[status.id]?.takeIf { eligible(status, it, speedMps) }
            ?.let { Warning(status, it, (speedMps!! * 3.6).toInt()) } }
        .minByOrNull { it.status.distance }
}
