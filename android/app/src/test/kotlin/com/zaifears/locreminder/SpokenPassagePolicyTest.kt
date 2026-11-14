package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class SpokenPassagePolicyTest {
    private fun status(stage: String = "approaching", aligned: Boolean = true, distance: Double = 300.0) =
        PassageTracker.Status("synthetic", "Synthetic", stage, distance, 5.0, 1000, false, aligned)
    @Test fun waitsForConfirmedApproachAndRetriesUntilPlaybackStarts() {
        assertTrue(SpokenPassagePolicy.pending(status(aligned = false), emptySet(), false).isEmpty())
        assertEquals(setOf("entered"), SpokenPassagePolicy.pending(status(), emptySet(), false))
        assertEquals(setOf("entered"), SpokenPassagePolicy.pending(status(), emptySet(), false))
        assertTrue(SpokenPassagePolicy.pending(status(), setOf("entered"), false).isEmpty())
    }
    @Test fun noRoutinePassageOrRepeatedReminder() {
        assertTrue(SpokenPassagePolicy.pending(status("passed"), emptySet(), true).isEmpty())
        assertTrue(SpokenPassagePolicy.pending(status(distance = 100.0), setOf("entered"), false).isEmpty())
        assertEquals(setOf("near"), SpokenPassagePolicy.pending(status(distance = 100.0), setOf("entered"), true))
        assertTrue(SpokenPassagePolicy.pending(status(distance = 100.0), setOf("entered", "near"), true).isEmpty())
    }
    @Test fun noPreciseDistanceFromOldOrUncertainFix() {
        assertTrue(SpokenPassagePolicy.fresh(status(), 4000))
        assertFalse(SpokenPassagePolicy.fresh(status(), 4001))
        assertFalse(SpokenPassagePolicy.fresh(status().copy(accuracy = 41.0), 2000))
        assertFalse(SpokenPassagePolicy.fresh(status().copy(distance = Double.NaN), 2000))
    }
    @Test fun typeAndApproximateDistanceChooseCompletePhrase() {
        assertEquals("fixedCamera_300", SpokenPassagePolicy.asset("fixedCamera", "entered", 302.0))
        assertEquals("redLightCamera_near", SpokenPassagePolicy.asset("redLightCamera", "entered", 20.0))
        assertEquals("other_1000", SpokenPassagePolicy.asset("unknown", "entered", 1020.0))
        assertEquals("speed_warning", SpokenPassagePolicy.asset("fixedCamera", "speed", 100.0))
    }
}
