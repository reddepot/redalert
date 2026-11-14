package com.zaifears.locreminder
import org.junit.Assert.*
import org.junit.Test
class VoicePreviewStateTest {
    @Test fun completionRecordsScreenStateAndClockFromTheActualCallback() {
        var now = 1000L; var screen = true
        val probe = VoicePreviewState({ now }, { screen })
        val ticket = probe.begin("highSpeedBump_300")
        probe.started(ticket); now = 3500; screen = false; probe.completed(ticket)
        assertEquals("completed", probe.snapshot()["state"])
        assertEquals("highSpeedBump_300", probe.snapshot()["asset"])
        assertEquals(1000L, probe.snapshot()["startedAtMillis"])
        assertEquals(3500L, probe.snapshot()["finishedAtMillis"])
        assertEquals(true, probe.snapshot()["finishedWhileScreenOff"])
    }
    @Test fun delayedOldPlayerCannotCompleteANewCategory() {
        val probe = VoicePreviewState({ 1000L }, { false })
        val old = probe.begin("fixedCamera_300"); probe.started(old)
        val current = probe.begin("highSpeedBump_300")
        probe.completed(old); probe.failed(old)
        assertEquals("preparing", probe.snapshot()["state"])
        assertNull(probe.snapshot()["finishedWhileScreenOff"])
        probe.started(current); probe.completed(current)
        assertEquals("highSpeedBump_300", probe.snapshot()["asset"])
    }
    @Test fun cancelledOrUnstartedClipNeverBecomesACompletedTest() {
        val probe = VoicePreviewState({ 1000L }, { false })
        val ticket = probe.begin("fixedCamera_300")
        probe.completed(ticket)
        assertEquals("preparing", probe.snapshot()["state"])
        probe.started(ticket); probe.cancel(); probe.completed(ticket)
        assertEquals("cancelled", probe.snapshot()["state"])
        assertNull(probe.snapshot()["finishedWhileScreenOff"])
    }
}
