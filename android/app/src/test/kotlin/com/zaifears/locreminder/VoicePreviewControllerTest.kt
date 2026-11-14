package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class VoicePreviewControllerTest {
    private class Fixture {
        var now = 1000L
        var interactive = true
        val state = VoicePreviewState({ now }, { interactive })
        class Task(val action: () -> Unit, var cancelled: Boolean = false)
        class Lease(val timeout: Long, var released: Boolean = false)
        class Playback(val asset: String, val started: () -> Unit, val failed: () -> Unit, val completed: () -> Unit)
        val tasks = mutableListOf<Task>()
        val leases = mutableListOf<Lease>()
        val plays = mutableListOf<Playback>()
        var acceptsAudio = true
        var reason: String? = null
        val controller = VoicePreviewController(state,
            schedule = { delay, action ->
                assertEquals(5000L, delay)
                val task = Task(action); tasks.add(task)
                val cancel: () -> Unit = { task.cancelled = true }
                cancel
            }, keepAwake = { timeout ->
                val lease = Lease(timeout); leases.add(lease)
                val release: () -> Unit = { lease.released = true }
                release
            }, play = { asset, started, failed, completed ->
                plays.add(Playback(asset, started, failed, completed)); acceptsAudio
            }, stopPlayer = {}, clock = { now }, failureReason = { reason })
    }

    @Test fun delayedPreviewWaitsThenHandsWakeLockToPlaybackAndRecordsScreenState() {
        val f = Fixture()
        assertTrue(f.controller.start("highSpeedBump_300", 5000))
        assertEquals("scheduled", f.controller.snapshot()["state"])
        assertEquals(6000L, f.controller.snapshot()["scheduledForMillis"])
        assertTrue(f.plays.isEmpty())
        assertEquals(13000L, f.leases.single().timeout)
        f.now = 6000; f.interactive = false; f.tasks.single().action()
        assertEquals("preparing", f.controller.snapshot()["state"])
        assertFalse(f.leases.single().released)
        f.plays.single().started()
        assertTrue(f.leases.single().released)
        f.now = 8500; f.plays.single().completed()
        assertEquals("completed", f.controller.snapshot()["state"])
        assertEquals(true, f.controller.snapshot()["startedWhileScreenOff"])
        assertEquals(true, f.controller.snapshot()["finishedWhileScreenOff"])
    }

    @Test fun cancellationDuringCountdownReleasesResourcesAndLateTaskCannotPlay() {
        val f = Fixture()
        f.controller.start("highSpeedBump_300", 5000)
        f.controller.cancel()
        assertTrue(f.tasks.single().cancelled)
        assertTrue(f.leases.single().released)
        f.tasks.single().action()
        assertTrue(f.plays.isEmpty())
        assertEquals("cancelled", f.controller.snapshot()["state"])
    }

    @Test fun replacementCannotPlayOldCategoryOrReleaseTheNewCountdownLock() {
        val f = Fixture()
        f.controller.start("fixedCamera_300", 5000)
        f.now = 6000
        f.tasks[0].action()
        val old = f.plays.single()
        f.controller.start("highSpeedBump_300", 5000)
        assertTrue(f.leases[0].released)
        old.started(); old.failed(); old.completed(); f.tasks[0].action()
        assertFalse(f.leases[1].released)
        assertEquals("scheduled", f.controller.snapshot()["state"])
        assertEquals(1, f.plays.size)
        f.now = 11000; f.tasks[1].action()
        assertEquals("highSpeedBump_300", f.plays.last().asset)
    }

    @Test fun refusalOfAudioAfterCountdownReportsFailureAndReleasesLock() {
        val f = Fixture(); f.acceptsAudio = false
        f.controller.start("highSpeedBump_300", 5000)
        f.now = 6000
        f.tasks.single().action()
        assertEquals("error", f.controller.snapshot()["state"])
        assertTrue(f.leases.single().released)
        assertNull(f.controller.snapshot()["startedWhileScreenOff"])
    }

    @Test fun immediatePreviewDoesNotAcquireAnExtraLockOrTimer() {
        val f = Fixture()
        assertTrue(f.controller.start("highSpeedBump_300"))
        assertTrue(f.tasks.isEmpty()); assertTrue(f.leases.isEmpty())
        f.plays.single().started(); f.plays.single().completed()
        assertEquals(false, f.controller.snapshot()["startedWhileScreenOff"])
    }

    @Test fun invalidDelayCannotCancelAnAlreadyScheduledPreview() {
        val f = Fixture()
        f.controller.start("highSpeedBump_300", 5000)
        try { f.controller.start("fixedCamera_300", 5001); fail("Invalid delay accepted") }
        catch (_: IllegalArgumentException) { }
        assertFalse(f.tasks.single().cancelled)
        assertFalse(f.leases.single().released)
        assertEquals("highSpeedBump_300", f.controller.snapshot()["asset"])
    }

    @Test fun countdownCannotPlayAnAnnouncementAfterItsTimeWindow() {
        val f = Fixture()
        f.controller.start("highSpeedBump_300", 5000)
        f.now = 10000; f.tasks.single().action()
        assertTrue(f.plays.isEmpty())
        assertTrue(f.leases.single().released)
        assertEquals("error", f.controller.snapshot()["state"])
        assertEquals("countdown_expired", f.controller.snapshot()["failureCode"])
    }

    @Test fun focusInterruptionIsRecordedAndALateCompletionCannotHideIt() {
        val f = Fixture()
        f.controller.start("highSpeedBump_300", 5000)
        f.now = 6000; f.interactive = false; f.tasks.single().action()
        f.plays.single().started()
        f.reason = "audio_focus_lost:-2"; f.plays.single().failed()
        f.plays.single().completed()
        assertEquals("error", f.controller.snapshot()["state"])
        assertEquals("audio_focus_lost:-2", f.controller.snapshot()["failureCode"])
        assertNull(f.controller.snapshot()["finishedWhileScreenOff"])
    }
}
