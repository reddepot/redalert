package com.zaifears.locreminder
import org.junit.Assert.*
import org.junit.Test
class DrivingApproachTest {
    private fun status(distance: Double) = PassageTracker.Status("synthetic", "Synthetic", "approaching", distance, 4.0, 1000, false, true)
    @Test fun citySequenceUsesTimeBeforePoint() {
        val speed=50.0/3.6
        assertTrue(SpokenPassagePolicy.pending(status(300.0), emptySet(), true, speed).isEmpty())
        assertEquals(setOf("entered"), SpokenPassagePolicy.pending(status(200.0), emptySet(), true, speed))
        assertEquals("fixedCamera_200", SpokenPassagePolicy.asset("fixedCamera","entered",200.0,speed))
        assertTrue(SpokenPassagePolicy.pending(status(120.0),setOf("entered"),true,speed).isEmpty())
        assertEquals(setOf("near"), SpokenPassagePolicy.pending(status(80.0),setOf("entered"),true,speed))
    }
    @Test fun fasterApproachWarnsEarlierWithoutWideningEveryPointDefinition() {
        assertEquals(setOf("entered"), SpokenPassagePolicy.pending(status(500.0),emptySet(),true,130.0/3.6))
        assertEquals(setOf("near"), SpokenPassagePolicy.pending(status(180.0),setOf("entered"),true,130.0/3.6))
    }
    @Test fun playbackAccountsForTravelSinceTheFixAndDropsPassedPoint() {
        val projected=SpokenPassagePolicy.distanceAtPlayback(status(180.0),3500,36.0)!!
        assertEquals(90.0,projected,0.001)
        assertEquals("fixedCamera_near",SpokenPassagePolicy.asset("fixedCamera","entered",projected,36.0))
        assertNull(SpokenPassagePolicy.distanceAtPlayback(status(60.0),3500,36.0))
        assertNull(SpokenPassagePolicy.distanceAtPlayback(status(180.0),3500,null))
    }
    @Test fun directionWrapsAndUnknownDoesNotSuppress() {
        assertTrue(TravelDirection.applies(0.0,359.0))
        assertTrue(TravelDirection.applies(null,180.0))
        assertTrue(TravelDirection.applies(90.0,null))
        assertFalse(TravelDirection.applies(90.0,270.0))
        assertTrue(TravelDirection.applies(90.0,120.0))
    }
    @Test fun fullTrackerAllowsAnAlignedMotorwayWarningBefore250Metres() {
        val tracker = PassageTracker()
        val point = PassageTracker.Point("synthetic", "Synthetic", 0.0, 0.0, 1100.0)
        tracker.update(PassageTracker.Fix(0.0, -540.0 / 111195.0, 2.0, 1000), 1000, listOf(point))
        val state = tracker.update(PassageTracker.Fix(0.0, -504.0 / 111195.0, 2.0, 2000), 2000, listOf(point))!!
        assertTrue("An aligned approach must be usable before the crossing axis is frozen", state.approachAligned)
        assertEquals(setOf("entered"), SpokenPassagePolicy.pending(state, emptySet(), true, 36.0))
    }
    @Test fun earlyWarningStillRejectsParallelAndRecedingSegments() {
        val point = PassageTracker.Point("synthetic", "Synthetic", 0.0, 0.0, 1100.0)
        val parallel = PassageTracker()
        parallel.update(PassageTracker.Fix(25.0 / 111195.0, -540.0 / 111195.0, 2.0, 1000), 1000, listOf(point))
        val side = parallel.update(PassageTracker.Fix(25.0 / 111195.0, -504.0 / 111195.0, 2.0, 2000), 2000, listOf(point))!!
        assertFalse(side.approachAligned)
        val receding = PassageTracker()
        receding.update(PassageTracker.Fix(0.0, -540.0 / 111195.0, 2.0, 1000), 1000, listOf(point))
        val away = receding.update(PassageTracker.Fix(0.0, -576.0 / 111195.0, 2.0, 2000), 2000, listOf(point))!!
        assertTrue(SpokenPassagePolicy.pending(away, emptySet(), true, 36.0).isEmpty())
    }
    @Test fun everySupportedRoadCategoryHasItsOwnVoiceAsset() {
        for (type in listOf("fixedCamera", "redLightCamera", "averageSpeedCamera", "levelCrossing", "levelCrossingLowClearance", "highSpeedBump", "dangerZone", "sharpTurn", "rumbleStrip", "roadDip", "roadNarrowing", "steepDescent", "roadWorks", "trafficJam", "other")) {
            assertEquals("${type}_200", SpokenPassagePolicy.asset(type,"entered",200.0))
        }
    }
}
