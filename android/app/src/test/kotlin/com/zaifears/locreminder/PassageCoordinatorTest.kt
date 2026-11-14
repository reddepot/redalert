package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class PassageCoordinatorTest {
    @Test fun overlappingZonesDoNotHideNextPointAfterFirstPassage() {
        val coordinator = PassageCoordinator()
        val first = PassageTracker.Point("first", "Premier", 0.0, 0.0, 1000.0)
        val second = first.copy(id="second", label="Second", lon=200.0/111195)
        val points = listOf(first, second)
        fun step(x: Double, t: Long) = coordinator.update(
            PassageTracker.Fix(0.0, x/111195, 2.0, t), t, points)!!.presented!!
        assertEquals("first", step(-210.0, 1000).id)
        step(-160.0, 2000)
        step(-20.0, 5000)
        step(20.0, 6000)
        assertEquals("after25", step(60.0, 7000).stage)
        assertEquals("second", step(100.0, 8000).id)
        assertEquals("second", step(180.0, 10000).id)
        assertEquals("before25", step(181.0, 11000).stage)
        assertEquals("passed", step(215.0, 12000).stage)
    }

    @Test fun duplicateSamplesCannotConfirmExit() {
        val coordinator = PassageCoordinator()
        val points = listOf(PassageTracker.Point("test", "Test", 0.0, 0.0, 1000.0))
        coordinator.update(PassageTracker.Fix(0.0, 0.0, 2.0, 1000), 1000, points)
        val outside = PassageTracker.Fix(0.0, 1200.0/111195, 2.0, 2000)
        assertNotEquals("exited", coordinator.update(outside, 2000, points)!!.presented!!.stage)
        assertNull(coordinator.update(outside, 2000, points))
        assertEquals("exited", coordinator.update(outside.copy(elapsed=3000), 3000, points)!!.presented!!.stage)
    }

    /**
     * The case the display focus used to swallow: two radar points 40 m apart,
     * the first one keeping the notification. The second point's approach must
     * still be reported, or a driver hears one of the two.
     */
    @Test fun aTransitionOnASecondPointIsReportedEvenWhileTheFirstHoldsFocus() {
        val coordinator = PassageCoordinator()
        val first = PassageTracker.Point("first", "Premier", 0.0, 0.0, 1000.0)
        val second = first.copy(id = "second", label = "Second", lon = 40.0 / 111195)
        val points = listOf(first, second)

        val seen = mutableSetOf<String>()
        var t = 1000L
        var x = -400.0
        while (x <= 120.0) {
            val update = coordinator.update(
                PassageTracker.Fix(0.0, x / 111195, 4.0, t), t, points)
            update?.changed?.forEach { seen.add("${it.id}:${it.stage}") }
            x += 36.0   // 130 km/h, one fix per second
            t += 1000
        }

        assertTrue("the first point must be reported: $seen",
            seen.any { it.startsWith("first:") })
        assertTrue("the second point must reach the driver too, focus or not: $seen",
            seen.any { it.startsWith("second:passed") } ||
                seen.any { it.startsWith("second:before25") })
    }
}
