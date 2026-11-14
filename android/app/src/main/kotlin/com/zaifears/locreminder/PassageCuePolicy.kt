package com.zaifears.locreminder

/** Evaluate every fresh observation, not just changes of the displayed stage. */
internal object PassageCuePolicy {
    private const val APPROACH_METRES = 150.0
    fun speedEligible(status: PassageTracker.Status): Boolean =
        status.approachAligned && status.stage in setOf("approaching", "before25")

    fun pending(status: PassageTracker.Status, played: Set<String>): Set<String> {
        val cue = when (status.stage) {
            "entered" -> "entered"
            "before25" -> "near"
            "passed", "passed_between_fixes" -> "passed"
            "approaching" -> if (status.approachAligned && status.distance <= APPROACH_METRES) "near" else null
            else -> null
        }
        return if (cue != null && cue !in played) setOf(cue) else emptySet()
    }
}
