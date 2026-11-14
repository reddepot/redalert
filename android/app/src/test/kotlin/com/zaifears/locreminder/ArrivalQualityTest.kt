package com.zaifears.locreminder
import org.junit.Assert.*
import org.junit.Test

class ArrivalQualityTest {
    @Test fun aCoarseFixCannotTriggerASmallDestinationZone() {
        assertFalse(ArrivalQuality.confirms(0.0, 400.0, 100.0))
        assertFalse(ArrivalQuality.confirms(0.0, 3000.0, 100.0))
    }
    @Test fun uncertaintyMustFitEvenWhenTheEstimatedPointIsInside() {
        assertTrue(ArrivalQuality.confirms(80.0, 20.0, 100.0))
        assertFalse(ArrivalQuality.confirms(81.0, 20.0, 100.0))
    }
    @Test fun aWideExplicitZoneStillAllowsItsOwnAccuracy() {
        assertTrue(ArrivalQuality.confirms(100.0, 400.0, 500.0))
    }
    @Test fun unknownAndInvalidInputsRemainUnconfirmed() {
        for (accuracy in listOf(null, -1.0, Double.NaN, Double.POSITIVE_INFINITY))
            assertFalse(ArrivalQuality.confirms(0.0, accuracy, 100.0))
        assertFalse(ArrivalQuality.confirms(Double.NaN, 2.0, 100.0))
        assertFalse(ArrivalQuality.confirms(0.0, 2.0, 0.0))
    }
}
