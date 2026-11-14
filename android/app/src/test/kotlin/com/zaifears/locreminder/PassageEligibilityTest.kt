package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class PassageEligibilityTest {
    private val point = PassageTracker.Point("synthetic", "Synthetic", 0.0, 0.0, 1000.0)
    private fun fix(x: Double, time: Long) = PassageTracker.Fix(0.0, x / 111195, 2.0, time)

    @Test fun courseMismatchHidesTargetWithoutLosingItsApproachAxis() {
        val tracker = PassageCoordinator()
        tracker.update(fix(-240.0, 1000), 1000, listOf(point), setOf(point.id))
        assertTrue(tracker.update(fix(-180.0, 2000), 2000, listOf(point), setOf(point.id))!!.presented!!.approachAligned)
        val hidden = tracker.update(fix(-120.0, 3000), 3000, listOf(point), emptySet())!!
        assertNull(hidden.presented)
        assertEquals(point, tracker.points()[point.id])
        assertTrue(hidden.observed.single().approachAligned)
        val resumed = tracker.update(fix(-60.0, 4000), 4000, listOf(point), setOf(point.id))!!
        assertTrue(resumed.presented!!.approachAligned)
        assertNotEquals("entered", resumed.presented!!.stage)
    }

    @Test fun hiddenFocusDoesNotSuppressAnotherApplicablePoint() {
        val other = point.copy(id="other", lon=100.0/111195)
        val tracker = PassageCoordinator()
        val both = listOf(point, other)
        tracker.update(fix(-220.0, 1000), 1000, both)
        val update = tracker.update(fix(-180.0, 2000), 2000, both, setOf(other.id))!!
        assertEquals(other.id, update.presented!!.id)
        assertEquals(setOf(point.id, other.id), update.observed.map { it.id }.toSet())
    }

    @Test fun disarmingStillRemovesThePointAndItsGeometry() {
        val tracker = PassageCoordinator()
        tracker.update(fix(-240.0,1000),1000,listOf(point))
        tracker.update(fix(-180.0,2000),2000,listOf(point))
        tracker.update(fix(-120.0,3000),3000,emptyList())
        assertTrue(tracker.points().isEmpty())
    }
}
