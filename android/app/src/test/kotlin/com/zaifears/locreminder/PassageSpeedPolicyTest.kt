package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class PassageSpeedPolicyTest {
    private fun point(id: String, limit: Int?) = AlarmEntry(id, "Synthetic", 0.0, 0.0, 1000.0,
        repeatOnEveryEntry=true, speedLimitKmh=limit)
    private fun status(id: String, distance: Double=200.0, aligned: Boolean=true, stage: String="approaching") =
        PassageTracker.Status(id, "Synthetic", stage, distance, 2.0, 1000, false, aligned)

    @Test fun pointWithoutLimitCannotHideSimultaneousWarning() {
        val points = listOf(point("focus", null), point("next", 50)).associateBy { it.id }
        val warning = PassageSpeedPolicy.select(listOf(status("focus", 50.0), status("next")),
            points, 70.0/3.6, points.keys)!!
        assertEquals("next", warning.point.id)
    }
    @Test fun passedOrOppositePointCannotCreateWarning() {
        val points = listOf(point("passed", 50), point("opposite", 50)).associateBy { it.id }
        assertNull(PassageSpeedPolicy.select(listOf(status("passed", stage="passed"), status("opposite")),
            points, 70.0/3.6, setOf("passed")))
    }
    @Test fun unknownOrInvalidSpeedCannotWarnEvenWithAKnownLimit() {
        for (speed in listOf(null, Double.NaN, Double.POSITIVE_INFINITY, -1.0, 71.0)) {
            assertFalse(PassageSpeedPolicy.eligible(status("test"), point("test",50),speed))
        }
    }
    @Test fun everyCandidateKeepsItsOwnZoneAndAlignment() {
        assertFalse(PassageSpeedPolicy.eligible(status("test",301.0),point("test",50),70.0/3.6))
        assertFalse(PassageSpeedPolicy.eligible(status("test",201.0),point("test",50).copy(radius=200.0),70.0/3.6))
        assertFalse(PassageSpeedPolicy.eligible(status("test", aligned=false),point("test",50),70.0/3.6))
        assertFalse(PassageSpeedPolicy.eligible(status("test"),point("test",50),55.0/3.6))
        assertTrue(PassageSpeedPolicy.eligible(status("test"),point("test",50),60.0/3.6))
    }
    @Test fun aSpeedReductionInvalidatesThePendingWarning() {
        val status = status("test"); val point=point("test",50)
        assertTrue(PassageSpeedPolicy.eligible(status, point,70.0/3.6))
        assertFalse(PassageSpeedPolicy.eligible(status, point,50.0/3.6))
    }
}
