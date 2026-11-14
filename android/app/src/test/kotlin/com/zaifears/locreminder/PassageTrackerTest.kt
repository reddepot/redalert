package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class PassageTrackerTest {
    private val point = PassageTracker.Point("test", "Lieu synthétique", 0.0, 0.0, 1000.0)
    private fun fix(x: Double, y: Double = 0.0, t: Long, acc: Double = 2.0) =
        PassageTracker.Fix(y / 111195.0, x / 111195.0, acc, t)
    private fun step(tracker: PassageTracker, x: Double, t: Long, y: Double = 0.0, acc: Double = 2.0) =
        tracker.update(fix(x, y, t, acc), t, listOf(point))!!

    @Test fun straightPassHasOrderedStagesAndRearmsAfterExit() {
        val tracker = PassageTracker()
        assertEquals("in_zone", step(tracker, -210.0, 1000).stage)
        assertEquals("approaching", step(tracker, -160.0, 2000).stage)
        assertEquals("before25", step(tracker, -20.0, 5000).stage)
        assertEquals("passed", step(tracker, 15.0, 6000).stage)
        assertEquals("after25", step(tracker, 40.0, 7000).stage)
        assertEquals("receding", step(tracker, 80.0, 8000).stage)
        step(tracker, 1110.0, 30000)
        assertEquals("exited", step(tracker, 1120.0, 31000).stage)
        assertEquals("entered", step(tracker, -210.0, 100000).stage)
        assertEquals("approaching", step(tracker, -160.0, 101000).stage)
    }
    @Test fun entryRequiresOutsideEvidenceAndInitialInsideStaysQuiet() {
        val tracker = PassageTracker()
        assertNull(tracker.update(fix(-1200.0, t=1000), 1000, listOf(point)))
        assertNull(tracker.update(fix(-1150.0, t=2000), 2000, listOf(point)))
        assertEquals("entered", step(tracker, -990.0, 5000).stage)
        tracker.reset()
        assertEquals("in_zone", step(tracker, -990.0, 6000).stage)
    }
    @Test fun uncertaintyAtZeroDoesNotLoseSlowCrossing() {
        val tracker = PassageTracker()
        step(tracker, -210.0, 1000)
        step(tracker, -160.0, 2000)
        step(tracker, -20.0, 5000)
        step(tracker, -10.0, 6000)
        step(tracker, -1.0, 7000)
        step(tracker, 1.0, 8000)
        assertEquals("passed", step(tracker, 10.0, 9000).stage)
    }
    @Test fun uTurnBeforePointDoesNotClaimPassage() {
        val tracker = PassageTracker()
        step(tracker, -210.0, 1000)
        step(tracker, -160.0, 2000)
        step(tracker, -100.0, 3000)
        val status = step(tracker, -150.0, 4000)
        assertEquals("receding", status.stage)
    }
    @Test fun parallelRoadOutside25mDoesNotClaimPassage() {
        val tracker = PassageTracker()
        step(tracker, -210.0, 1000, 60.0)
        step(tracker, -160.0, 2000, 60.0)
        step(tracker, -20.0, 5000, 60.0)
        assertFalse(step(tracker, 20.0, 6000, 60.0).stage.startsWith("passed"))
        assertNotEquals("after25", step(tracker, 60.0, 7000, 60.0).stage)
    }
    @Test fun skippedNearFixIsExplicitlyEstimated() {
        val tracker = PassageTracker()
        step(tracker, -210.0, 1000)
        step(tracker, -160.0, 2000)
        step(tracker, -40.0, 4000)
        assertEquals("passed_between_fixes", step(tracker, 40.0, 6000).stage)
    }
    @Test fun staleDuplicateOrUncertainFixesDoNotAdvanceState() {
        val tracker = PassageTracker()
        step(tracker, -210.0, 1000)
        assertNull(tracker.update(fix(-160.0, t=1000), 2000, listOf(point)))
        assertNull(tracker.update(fix(-160.0, t=2000), 8000, listOf(point)))
        assertNull(tracker.update(fix(-160.0, t=3000, acc=200.0), 3000, listOf(point)))
        assertEquals("approaching", step(tracker, -160.0, 4000).stage)
    }
    @Test fun lostGpsNeverInfersCrossingAcrossGap() {
        val tracker = PassageTracker()
        step(tracker, -210.0, 1000)
        step(tracker, -160.0, 2000)
        assertEquals("in_zone", step(tracker, 40.0, 20000).stage)
    }
    @Test fun stationaryJitterDoesNotInventDirection() {
        val tracker = PassageTracker()
        step(tracker, -20.0, 1000, acc=5.0)
        assertEquals("in_zone", step(tracker, -18.0, 2000, acc=5.0).stage)
        assertEquals("in_zone", step(tracker, -21.0, 3000, acc=5.0).stage)
    }
    @Test fun overlappingZonesKeepTargetAndDeletionResetsIt() {
        val tracker = PassageTracker()
        val other = point.copy(id="other", label="Autre", lon=0.001)
        tracker.update(fix(-100.0, t=1000), 1000, listOf(point, other))
        assertEquals("test", tracker.update(fix(100.0, t=5000), 5000, listOf(point, other))!!.id)
        assertEquals("other", tracker.update(fix(100.0, t=6000), 6000, listOf(other))!!.id)
    }

    @Test fun fiveSecondSamplesCanStraddleAnUncertainFixAtZero() {
        val tracker = PassageTracker()
        for ((index, x) in listOf(-150.0, -100.0, -50.0, 0.0).withIndex()) {
            assertFalse(step(tracker, x, (index + 1) * 5000L, acc=15.0).stage.startsWith("passed"))
        }
        assertEquals("passed_between_fixes", step(tracker, 50.0, 25000, acc=15.0).stage)
    }

    @Test fun gapClearsAccumulatedMotionAndCrossingAnchor() {
        val tracker = PassageTracker()
        step(tracker, -150.0, 1000, acc=15.0)
        step(tracker, -100.0, 6000, acc=15.0)
        step(tracker, -50.0, 11000, acc=15.0)
        assertEquals("in_zone", step(tracker, 0.0, 16001, acc=15.0).stage)
        assertFalse(step(tracker, 50.0, 21001, acc=15.0).stage.startsWith("passed"))
    }

    @Test fun stationaryJitterAtFifteenMetreAccuracyDoesNotAccumulateIntoMotion() {
        val tracker = PassageTracker()
        repeat(30) { index ->
            val x = if (index % 2 == 0) -14.0 else 14.0
            assertEquals("in_zone", step(tracker, x, (index + 1) * 1000L, acc=15.0).stage)
        }
    }

    @Test fun uncertaintyAboveFifteenMetresDoesNotConfirmCrossing() {
        val tracker = PassageTracker()
        step(tracker, -150.0, 1000, acc=15.0)
        step(tracker, -100.0, 2000, acc=15.0)
        step(tracker, -50.0, 3000, acc=15.0)
        assertFalse(step(tracker, 20.0, 4000, acc=16.0).stage.startsWith("passed"))
    }
}
