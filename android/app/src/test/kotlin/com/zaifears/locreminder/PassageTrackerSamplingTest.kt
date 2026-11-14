package com.zaifears.locreminder

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class PassageTrackerSamplingTest(
    private val kmh: Int,
    private val seconds: Int,
    private val accuracy: Double,
) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0} km/h, {1} s, accuracy {2} m")
        fun cases(): Collection<Array<Any>> =
            listOf(30, 50, 80, 110, 130).flatMap { speed ->
                listOf(1, 2, 5).flatMap { interval ->
                    listOf(3.0, 8.0, 12.0, 15.0).map { acc ->
                        arrayOf<Any>(speed, interval, acc)
                    }
                }
            }
    }

    private val point = PassageTracker.Point("test", "Test", 0.0, 0.0, 1000.0)
    private val metresPerSecond = kmh / 3.6
    private val spacing = metresPerSecond * seconds

    private fun step(tracker: PassageTracker, x: Double, y: Double, heading: Double, t: Long) =
        tracker.update(PassageTracker.Fix(
            (x * sin(heading) + y * cos(heading)) / 111195.0,
            (x * cos(heading) - y * sin(heading)) / 111195.0,
            accuracy, t), t, listOf(point))!!

    private fun drive(offset: Double, heading: Double, phase: Int): List<PassageTracker.Status> {
        val tracker = PassageTracker()
        val first = -ceil(800.0 / spacing).toInt()
        val last = ceil(150.0 / spacing).toInt() + 1
        return (first..last).map { index ->
            step(tracker, (index + phase / 100.0) * spacing, offset, heading,
                (index - first + 1) * seconds * 1000L)
        }
    }

    @Test fun straightCrossingsAreDetectedForEverySamplingPhase() {
        for (heading in listOf(0.0, 0.7, PI / 2, PI)) {
            for (phase in 0 until 100) {
                val statuses = drive(0.0, heading, phase)
                val context = "heading=$heading phase=$phase stages=${statuses.map { it.stage }}"
                assertEquals(context, 1, statuses.count { it.stage.startsWith("passed") })
                assertEquals(context, 1, statuses.count { it.stage == "after25" })
                val before = statuses.indexOfFirst { it.stage == "before25" }
                val passed = statuses.indexOfFirst { it.stage.startsWith("passed") }
                val after = statuses.indexOfFirst { it.stage == "after25" }
                assertTrue(context, before < passed && passed < after)
                // A 5 s sampling interval may skip the entire warning window.
                if (seconds == 1) assertTrue(context, before >= 0)
                if (before < 0) assertEquals(context, "passed_between_fixes", statuses[passed].stage)
            }
        }
    }

    @Test fun smallLateralOffsetsStillAllowCrossing() {
        for (offset in listOf(-8.0, 8.0)) {
            for (phase in 0 until 100) {
                val statuses = drive(offset, 0.7, phase)
                assertEquals("offset=$offset phase=$phase", 1,
                    statuses.count { it.stage.startsWith("passed") })
            }
        }
    }

    @Test fun parallelRoadsNeverProduceNearOrPassageStages() {
        for (offset in listOf(-20.0, -15.0, 15.0, 20.0)) {
            for (heading in listOf(0.0, 0.7)) {
                for (phase in 0 until 100) {
                    val statuses = drive(offset, heading, phase)
                    assertFalse("offset=$offset heading=$heading phase=$phase",
                        statuses.any { it.stage == "before25" || it.stage.startsWith("passed") ||
                            it.stage == "after25" })
                }
            }
        }
    }

    @Test fun warningUsesTwoSecondsOfSpeedWithThirtyMetreFloor() {
        val threshold = maxOf(30.0, metresPerSecond * 2)
        for (delta in listOf(-0.5, 0.5)) {
            val tracker = PassageTracker()
            var status: PassageTracker.Status? = null
            for (index in 0..4) {
                status = step(tracker, -threshold + delta - (4 - index) * spacing,
                    0.0, 0.0, (index + 1) * seconds * 1000L)
            }
            if (delta > 0) assertEquals("threshold=$threshold", "before25", status!!.stage)
            else assertNotEquals("threshold=$threshold", "before25", status!!.stage)
        }
    }
}
