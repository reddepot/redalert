package com.zaifears.locreminder

import org.junit.Assert.*
import org.junit.Test

class AlarmValidationTest {
    @Test fun nonFiniteCoordinatesAndAnOutOfRangeRadiusCannotReachEitherWritePath() {
        for ((lat, radius) in listOf(Double.NaN to 1000.0, 0.0 to 50.0, 0.0 to Double.POSITIVE_INFINITY)) {
            try {
                AlarmValidation.requireValid("synthetic", "Synthetic", lat, 0.0, radius)
                fail("Invalid destination accepted")
            } catch (_: IllegalArgumentException) { }
        }
        assertThrows(IllegalArgumentException::class.java) { AlarmValidation.requireValid("x".repeat(121), "Synthetic", 0.0, 0.0, 100.0) }
        AlarmValidation.requireValid("synthetic", "Synthetic", 0.0, 0.0, 100.0)
        AlarmValidation.requireValid("synthetic", "Synthetic", 0.0, 0.0, 3000.0)
    }
}
