package com.zaifears.locreminder

/** Monitoring radius and spoken timing are separate. No exact distance from an old fix. */
internal object SpokenPassagePolicy {
    private val distances = listOf(30, 50, 75, 100, 150, 200, 250, 300, 400, 500, 600, 750, 1000, 1250, 1500, 2000, 2500, 3000)
    private val types = setOf("fixedCamera", "redLightCamera", "averageSpeedCamera", "levelCrossing", "levelCrossingLowClearance", "highSpeedBump", "dangerZone", "sharpTurn", "rumbleStrip", "roadDip", "roadNarrowing", "steepDescent", "roadWorks", "trafficJam", "other")
    fun pending(status: PassageTracker.Status, played: Set<String>, reminder: Boolean, speedMps: Double? = null): Set<String> {
        if (!status.approachAligned || status.stage !in setOf("entered", "approaching", "before25")) return emptySet()
        if (speedMps != null && speedMps < 1) return emptySet()
        val firstDistance = speedMps?.let { (it * 15).coerceIn(100.0, 1000.0) } ?: 300.0
        val nearDistance = speedMps?.let { (it * 6).coerceIn(30.0, 200.0) } ?: 150.0
        if ("entered" !in played && status.distance <= firstDistance) return setOf("entered")
        return if ("entered" in played && reminder && status.distance <= nearDistance && "near" !in played) setOf("near") else emptySet()
    }
    fun distanceAtPlayback(status: PassageTracker.Status, now: Long, speedMps: Double?): Double? {
        if (!fresh(status, now)) return null
        val age = (now - status.elapsed) / 1000.0
        val usableSpeed = speedMps?.takeIf { it.isFinite() && it in 0.0..70.0 }
        if (usableSpeed == null && age > 1) return null
        val projected = status.distance - (usableSpeed ?: 0.0) * age
        return projected.takeIf { it > 0 }
    }
    fun asset(type: String, cue: String, distance: Double, speedMps: Double? = null): String {
        val kind = type.takeIf { it in types } ?: "other"
        if (cue == "speed") return "speed_warning"
        if (cue == "near" || distance < 40 || (speedMps != null && speedMps > 0 && distance / speedMps < 4)) return "${kind}_near"
        val rounded = distances.minBy { kotlin.math.abs(it - distance) }
        return "${kind}_$rounded"
    }
    fun fresh(status: PassageTracker.Status, now: Long): Boolean =
        now - status.elapsed in 0..3000 && status.accuracy.isFinite() && status.accuracy in 0.0..40.0 && status.distance.isFinite() && status.distance >= 0
}
