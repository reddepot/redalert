package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class WatchHealthTest {
    @Test fun registrationAloneIsNotEvidenceOfAFixAndFreshnessExpiresWithoutNewCallbacks() {
        assertEquals("acquiring", WatchHealth.state(true, false, true, 0, 1000))
        assertEquals("fresh", WatchHealth.state(true, false, true, 1000, 2000))
        assertEquals("stale", WatchHealth.state(true, false, true, 1000, 16001))
        assertEquals("dormant", WatchHealth.state(true, true, false, 1000, 16001))
        assertEquals("stopped", WatchHealth.state(false, false, false, 1000, 16001))
    }
    @Test fun futureTimestampCannotClaimARecentPosition() {
        assertEquals("acquiring", WatchHealth.state(true, false, true, 2000, 1000))
    }
    @Test fun anExpectedSlowFixIsNotCurrentAndNotYetAProviderFailure() {
        assertEquals("economy", WatchHealth.state(true, false, true, 1000, 16001, 60000))
        assertEquals("stale", WatchHealth.state(true, false, true, 1000, 121001, 60000))
        assertEquals("stale", WatchHealth.state(true, false, true, 1000, 16001, 1000))
    }
}
