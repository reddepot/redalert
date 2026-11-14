package com.zaifears.locreminder
import org.junit.Assert.*
import org.junit.Test

class PassageVoiceCadenceTest {
    @Test fun anotherPointIsNotSilencedByEightSecondRepetitionGate() {
        val cadence = PassageVoiceCadence()
        cadence.record("first", 1000)
        assertFalse(cadence.allows("first", 4000, false, false))
        assertTrue(cadence.allows("second", 4000, false, false))
    }
    @Test fun samePointCanSpeakAgainWhenItsGateExpires() {
        val cadence = PassageVoiceCadence()
        cadence.record("point", 1000)
        assertFalse(cadence.allows("point", 8999, false, false))
        assertTrue(cadence.allows("point", 9000, false, false))
    }
    @Test fun previewAndUrgencyDoNotWaitForTheRepetitionGate() {
        val cadence = PassageVoiceCadence()
        cadence.record("point", 1000)
        assertTrue(cadence.allows("point", 1100, true, false))
        assertTrue(cadence.allows("point", 1100, false, true))
    }
}
