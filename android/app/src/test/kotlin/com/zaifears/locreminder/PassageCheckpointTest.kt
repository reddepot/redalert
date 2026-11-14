package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class PassageCheckpointTest {
    private val point = PassageTracker.Point("synthetic", "Synthetic point", 0.0, 0.0, 1000.0)
    private fun step(c: PassageCoordinator, x: Double, t: Long, points: List<PassageTracker.Point> = listOf(point), y: Double = 0.0) =
        c.update(PassageTracker.Fix(y / 111195, x / 111195, 2.0, t), t, points)
    private fun approach(c: PassageCoordinator) {
        step(c, -210.0, 1000); step(c, -160.0, 2000); step(c, -20.0, 5000)
    }
    private fun restart(c: PassageCoordinator, now: Long = 5000): PassageCoordinator {
        val bytes = PassageCheckpoint.encode(c, mapOf(point.id to setOf("near")), 7)
        return PassageCoordinator().also {
            assertEquals(setOf("near"), PassageCheckpoint.restore(bytes, it, 7, now)!![point.id])
        }
    }

    @Test fun crossingSurvivesProcessRecreation() {
        val c = PassageCoordinator(); approach(c)
        val restored = restart(c)
        assertEquals("passed", step(restored, 15.0, 6000)!!.presented!!.stage)
        assertEquals("after25", step(restored, 40.0, 7000)!!.presented!!.stage)
    }

    @Test fun interruptionOverFiveSecondsCannotInventCrossing() {
        val c = PassageCoordinator(); approach(c)
        val restored = restart(c, 11000)
        assertEquals("in_zone", step(restored, 40.0, 11000)!!.presented!!.stage)
    }

    @Test fun uncertainZeroAndCrossingAnchorSurviveRestart() {
        val c = PassageCoordinator(); approach(c)
        step(c, -1.0, 6000)
        assertEquals("passed", step(restart(c, 6000), 10.0, 7000)!!.presented!!.stage)
    }

    @Test fun passedAndAfterAnnouncementAreNotRepeatedAfterRestart() {
        val c = PassageCoordinator(); approach(c)
        step(c, 15.0, 6000); step(c, 40.0, 7000)
        assertEquals("receding", step(restart(c, 7000), 60.0, 8000)!!.presented!!.stage)
    }

    @Test fun unchangedStageAndDuplicateFixStayQuietAfterRestart() {
        val c = PassageCoordinator(); approach(c)
        val restored = restart(c)
        assertNull(step(restored, -20.0, 5000))
        assertTrue(step(restored, -15.0, 6000)!!.changed.isEmpty())
    }

    @Test fun outsideEvidenceSurvivesRestart() {
        val c = PassageCoordinator()
        step(c, -1200.0, 1000); step(c, -1150.0, 2000)
        assertEquals("entered", step(restart(c, 2000), -990.0, 5000)!!.presented!!.stage)
    }

    @Test fun editedOrDeletedPointCannotInheritCrossing() {
        val c = PassageCoordinator(); approach(c)
        val restored = restart(c)
        assertEquals("in_zone", step(restored, 15.0, 6000, listOf(point.copy(lon=10.0/111195)))!!.presented!!.stage)
        assertNull(step(restored, 20.0, 7000, emptyList())!!.presented)
        assertTrue(restored.points().isEmpty())
    }

    @Test fun parallelRoadStillCannotConfirmCrossingAfterRestart() {
        val c = PassageCoordinator()
        step(c, -210.0, 1000, y=30.0); step(c, -160.0, 2000, y=30.0); step(c, -20.0, 5000, y=30.0)
        assertFalse(step(restart(c), 15.0, 6000, y=30.0)!!.presented!!.stage.startsWith("passed"))
    }

    @Test fun overlappingPointsKeepIndependentState() {
        val c = PassageCoordinator()
        val points = listOf(point, point.copy(id="second", lon=40.0/111195))
        step(c, -210.0, 1000, points); step(c, -160.0, 2000, points); step(c, -20.0, 5000, points)
        val update = step(restart(c), 15.0, 6000, points)!!
        assertTrue(update.changed.any { it.id == point.id && it.stage == "passed" })
        assertFalse(update.changed.any { it.id == "second" && it.stage.startsWith("passed") })
    }

    @Test fun otherBootFutureTimeAndUnsupportedVersionAreRejected() {
        val c = PassageCoordinator(); approach(c)
        val bytes = PassageCheckpoint.encode(c, emptyMap(), 7)
        assertNull(PassageCheckpoint.restore(bytes, PassageCoordinator(), 8, 5000))
        assertNull(PassageCheckpoint.restore(bytes, PassageCoordinator(), -1, 5000))
        assertNull(PassageCheckpoint.restore(bytes, PassageCoordinator(), 7, 4999))
        bytes[3] = 99
        assertNull(PassageCheckpoint.restore(bytes, PassageCoordinator(), 7, 5000))
    }

    @Test fun truncatedOrTrailingDataIsRejectedWithoutPartialRestore() {
        val c = PassageCoordinator(); approach(c)
        val bytes = PassageCheckpoint.encode(c, emptyMap(), 7)
        for (length in bytes.indices) {
            val restored = PassageCoordinator()
            assertNull(PassageCheckpoint.restore(bytes.copyOf(length), restored, 7, 5000))
            assertTrue(restored.points().isEmpty())
        }
        assertNull(PassageCheckpoint.restore(bytes + byteArrayOf(1), PassageCoordinator(), 7, 5000))
    }

    @Test fun emptyStateAndCuesForDeletedPointsAreHandled() {
        val c = PassageCoordinator()
        val bytes = PassageCheckpoint.encode(c, mapOf("deleted" to setOf("near")), 7)
        assertEquals(emptyMap<String, Set<String>>(), PassageCheckpoint.restore(bytes, PassageCoordinator(), 7, 1000))
    }
}
