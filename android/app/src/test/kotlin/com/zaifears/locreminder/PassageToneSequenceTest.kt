package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class PassageToneSequenceTest {
    private class Fixture {
        val pending = linkedMapOf<Runnable, Long>()
        val played = mutableListOf<Pair<Int, Int>>()
        var granted = true
        var plays = true
        var released = 0
        var stopped = 0
        val sequence = PassageToneSequence(
            post = { task, delay -> pending[task] = delay },
            remove = { pending.remove(it); Unit },
            requestFocus = { granted },
            releaseFocus = { released++ },
            play = { id, duration -> played.add(id to duration); plays },
            stop = { stopped++ },
        )
        fun runNext() { val task = pending.minBy { it.value }.key; pending.remove(task); task.run() }
    }

    @Test fun stopsAndCancelsEveryRemainingRepeat() {
        val f = Fixture()
        assertTrue(f.sequence.start(1, 3))
        assertEquals(3, f.pending.size)
        f.sequence.cancel()
        assertTrue(f.pending.isEmpty())
        assertEquals(1, f.played.size)
        assertEquals(1, f.stopped)
        assertEquals(1, f.released)
        f.sequence.cancel()
        assertEquals(1, f.released)
    }
    @Test fun completionReleasesFocusAfterFinalToneAndBoundsRepetitions() {
        val f = Fixture()
        assertTrue(f.sequence.start(1, 100))
        while (f.pending.isNotEmpty()) f.runNext()
        assertEquals(3, f.played.size)
        assertEquals(1, f.released)
        assertFalse(f.sequence.busy)
    }
    @Test fun overlappingSequenceIsRetryableRatherThanReplacingTheActiveOne() {
        val f = Fixture()
        assertTrue(f.sequence.start(1, 3))
        assertFalse(f.sequence.start(2, 3))
        while (f.pending.isNotEmpty()) f.runNext()
        assertTrue(f.played.all { it.first == 1 })
        assertTrue(f.sequence.start(2, 1))
    }
    @Test fun refusedFocusDoesNotPlayOrConsumeTheSequence() {
        val f = Fixture(); f.granted = false
        assertFalse(f.sequence.start(1, 3))
        assertTrue(f.played.isEmpty())
        assertTrue(f.pending.isEmpty())
        assertEquals(0, f.released)
        f.granted = true
        assertTrue(f.sequence.start(1, 3))
    }
    @Test fun firstToneFailureReleasesFocusWithoutSchedulingMore() {
        val f = Fixture(); f.plays = false
        assertFalse(f.sequence.start(1, 3))
        assertEquals(1, f.released)
        assertTrue(f.pending.isEmpty())
    }
    @Test fun callbackAlreadyDequeuedCannotAffectANewSequence() {
        val f = Fixture()
        assertTrue(f.sequence.start(1, 3))
        val stale = f.pending.keys.toList()
        f.sequence.cancel()
        assertTrue(f.sequence.start(2, 1))
        stale.forEach { it.run() }
        assertEquals(listOf(1 to 150, 2 to 250), f.played)
        assertTrue(f.sequence.busy)
        assertEquals(1, f.released)
        f.runNext()
        assertEquals(2, f.released)
    }
    @Test fun laterToneFailureStopsTheRest() {
        val f = Fixture(); assertTrue(f.sequence.start(1, 3))
        f.plays = false; f.runNext()
        assertEquals(2, f.played.size)
        assertTrue(f.pending.isEmpty())
        assertEquals(1, f.released)
    }
}
