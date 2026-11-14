package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class PassageCuePolicyTest {
    @Test fun uninterruptedApproachWarnsAt150MetresWithoutStageChangeAndRetriesFailedAudio() {
        val coordinator = PassageCoordinator()
        val point = PassageTracker.Point("synthetic", "Synthetic", 0.0, 0.0, 1000.0)
        val played = mutableSetOf<String>()
        var firstAttempt: Double? = null
        val attempts = mutableListOf<Double>()
        for ((index, x) in (-400..-75 step 25).withIndex()) {
            val time = (index + 1) * 1000L
            val update = coordinator.update(PassageTracker.Fix(0.0, x / 111195.0, 2.0, time), time, listOf(point))!!
            for (status in update.observed) {
                if (PassageCuePolicy.pending(status, played).contains("near")) {
                    assertEquals("approaching", status.stage)
                    assertFalse(status.changed)
                    attempts.add(status.distance)
                    if (firstAttempt == null) firstAttempt = status.distance // Simulate failed tone.
                    else played.add("near") // The second attempt actually plays.
                }
            }
        }
        assertEquals(150.0, firstAttempt!!, 0.01)
        assertEquals(2, attempts.size)
        assertEquals(125.0, attempts.last(), 0.01)
    }
    @Test fun highPriorityCuesRejectParallelApproachesAndTheOutgoingLeg() {
        val point = PassageTracker.Point("synthetic", "Synthetic", 0.0, 0.0, 1000.0)
        for (lateral in listOf(0.0, 30.0)) {
            val c = PassageCoordinator()
            var eligibleBefore = false
            for ((index, x) in (-400..100 step 25).withIndex()) {
                val time = (index + 1) * 1000L
                val status = c.update(PassageTracker.Fix(lateral / 111195, x / 111195.0, 2.0, time), time, listOf(point))!!.presented!!
                val eligible = PassageCuePolicy.speedEligible(status)
                if (lateral == 30.0 || x > 0) {
                    assertFalse(eligible)
                    if (lateral == 30.0) assertFalse("near" in PassageCuePolicy.pending(status, emptySet()))
                } else if (eligible) eligibleBefore = true
            }
            assertEquals(lateral == 0.0, eligibleBefore)
        }
    }
}
